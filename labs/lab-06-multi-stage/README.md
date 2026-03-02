# Lab 06: Multi-Stage Pipelines

## Hintergrund

Bisher hatten unsere Pipelines eine flache Struktur: ein Pool, eine Liste von
Steps. Das genügt für einfache Builds, aber reale Projekte durchlaufen mehrere
Phasen - Build, Test, Deploy nach Staging, Deploy nach Production. Jede Phase
hat eigene Anforderungen: unterschiedliche Agents, Bedingungen oder manuelle
Genehmigungen.

Azure Pipelines bildet das über eine dreistufige Hierarchie ab:

- **Stages**: Die oberste Ebene. Jede Stage repräsentiert eine Phase im
  Gesamtprozess (z. B. "Build", "Test", "Deploy"). Stages laufen standardmäßig
  nacheinander, können aber mit `dependsOn` auch parallel geschaltet werden.
- **Jobs**: Innerhalb einer Stage können mehrere Jobs definiert werden. Jobs
  **ohne** `dependsOn` laufen **parallel** auf unterschiedlichen Agents - das
  beschleunigt z. B. das gleichzeitige Ausführen von Unit Tests und Lint Checks.
- **Steps**: Die kleinste Einheit. Jeder Step ist ein einzelner Befehl oder
  Task, der innerhalb eines Jobs sequenziell ausgeführt wird.

Zusätzlich lernen wir in diesem Lab zwei wichtige Konzepte kennen:

- **Artefakte** (`publish` / `download`): Da jede Stage auf einem eigenen Agent
  läuft, gehen Dateien zwischen Stages verloren. Mit `publish` speicherst du
  Dateien als Artefakt, und mit `download` lädst du sie in einer späteren Stage
  wieder herunter.
- **Conditions**: Mit `condition` kannst du steuern, ob eine Stage überhaupt
  ausgeführt wird - z. B. nur auf dem `master`-Branch oder nur wenn alle
  vorherigen Stages erfolgreich waren.

## Aufgabenstellung

### Schritt 1: Node.js-Beispielprojekt erstellen

Für eine Multi-Stage-Pipeline brauchen wir eine Anwendung, die tatsächlich
gebaut und getestet werden kann. Wir erstellen ein einfaches Node.js-Projekt mit
Build-Skript, Tests und Lint-Check. Node.js eignet sich gut, da es auf den
Microsoft-hosted Agents vorinstalliert ist und keine Kompilierung erfordert.

Erstelle die folgenden Dateien in deinem `hello-pipeline`-Repository:

**package.json** - definiert die Projekt-Metadaten und die Skripte, die die
Pipeline später aufruft (`npm run build`, `npm test`, `npm run lint`):

```json
{
  "name": "hello-pipeline",
  "version": "1.0.0",
  "description": "Demo-App für Multi-Stage Pipeline",
  "main": "src/app.js",
  "scripts": {
    "build": "echo 'Building app...' && mkdir -p dist && cp src/*.js dist/ && cp index.html dist/",
    "test": "echo 'Running tests...' && node test/test.js",
    "lint": "echo 'Linting...' && echo 'No lint errors found.'"
  }
}
```

Erstelle die Verzeichnisse und die Anwendungsdatei:

**Bash:**

```bash
mkdir -p src test
```

**PowerShell:**

```powershell
New-Item -ItemType Directory -Force -Path src, test | Out-Null
```

**src/app.js** - eine einfache Node.js-Anwendung mit zwei Funktionen, die wir
später testen:

```javascript
function greet(name) {
    return `Hello, ${name}! Welcome to Azure Pipelines.`;
}

function add(a, b) {
    return a + b;
}

module.exports = {greet, add};
```

**test/test.js** - ein minimales Test-Framework ohne externe Abhängigkeiten. Die
Tests prüfen, ob die Funktionen aus `app.js` korrekt arbeiten. Bei einem
fehlgeschlagenen Test endet das Skript mit Exit-Code 1, was die Pipeline als
"failed" markiert:

```javascript
const {greet, add} = require('../src/app');

let passed = 0;
let failed = 0;

function assert(condition, message) {
    if (condition) {
        console.log(`  PASS: ${message}`);
        passed++;
    } else {
        console.log(`  FAIL: ${message}`);
        failed++;
    }
}

console.log('Running tests...\n');
assert(greet('World') === 'Hello, World! Welcome to Azure Pipelines.', 'greet returns correct message');
assert(add(2, 3) === 5, 'add(2,3) returns 5');
assert(add(-1, 1) === 0, 'add(-1,1) returns 0');

console.log(`\nResults: ${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
```

### Schritt 2: Multi-Stage Pipeline erstellen

Jetzt erstellen wir die Pipeline mit vier Stages, die eine typische CI/CD- Kette
abbilden:

1. **Build**: Baut die Anwendung und publiziert die Artefakte.
2. **Test**: Führt Unit Tests und Lint-Check parallel in zwei Jobs aus.
3. **Deploy Staging**: Simuliert ein Deployment in die Staging-Umgebung (nur auf
   `master`).
4. **Deploy Production**: Simuliert ein Deployment in die Produktion (nur auf
   `master`, nach erfolgreichem Staging-Deployment).

Ersetze den Inhalt von `azure-pipelines.yml`:

```yaml
trigger:
  branches:
    include:
      - master

variables:
  nodeVersion: '20.x'
  buildConfiguration: 'Release'

stages:
  # ===== Stage 1: Build =====
  - stage: Build
    displayName: 'Build Stage'
    jobs:
      - job: BuildJob
        displayName: 'Build Application'
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - task: NodeTool@0
            inputs:
              versionSpec: '$(nodeVersion)'
            displayName: 'Node.js installieren'

          - script: npm run build
            displayName: 'Anwendung bauen'

          - script: |
              echo "Build-Artefakte:"
              ls -la dist/
            displayName: 'Build-Ergebnis prüfen'

          # Artefakte für nächste Stage bereitstellen
          - publish: $(System.DefaultWorkingDirectory)/dist
            artifact: app-build
            displayName: 'Build-Artefakte publizieren'

  # ===== Stage 2: Test (parallel Jobs) =====
  - stage: Test
    displayName: 'Test Stage'
    dependsOn: Build
    jobs:
      - job: UnitTests
        displayName: 'Unit Tests'
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - task: NodeTool@0
            inputs:
              versionSpec: '$(nodeVersion)'
            displayName: 'Node.js installieren'

          - script: npm test
            displayName: 'Unit Tests ausführen'

      - job: LintCheck
        displayName: 'Code Quality'
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - script: npm run lint
            displayName: 'Lint ausführen'

  # ===== Stage 3: Deploy Staging (nur auf master) =====
  - stage: DeployStaging
    displayName: 'Deploy to Staging'
    dependsOn: Test
    condition: and(succeeded(), eq(variables['Build.SourceBranchName'], 'master'))
    jobs:
      - job: DeployJob
        displayName: 'Deploy to Staging'
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - download: current
            artifact: app-build
            displayName: 'Build-Artefakte herunterladen'

          - script: |
              echo "=== Deployment nach Staging ==="
              echo "Artefakte:"
              ls -la $(Pipeline.Workspace)/app-build/
              echo ""
              echo "Simuliere Deployment..."
              echo "Deployment nach Staging erfolgreich!"
            displayName: 'Staging Deployment (simuliert)'

  # ===== Stage 4: Deploy Production =====
  - stage: DeployProduction
    displayName: 'Deploy to Production'
    dependsOn: DeployStaging
    condition: and(succeeded(), eq(variables['Build.SourceBranchName'], 'master'))
    jobs:
      - job: DeployProd
        displayName: 'Deploy to Production'
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - download: current
            artifact: app-build
            displayName: 'Build-Artefakte herunterladen'

          - script: |
              echo "=== Deployment nach Production ==="
              echo "Artefakte:"
              ls -la $(Pipeline.Workspace)/app-build/
              echo ""
              echo "Simuliere Production Deployment..."
              echo "Deployment nach Production erfolgreich!"
            displayName: 'Production Deployment (simuliert)'
```

Gehe die Pipeline Abschnitt für Abschnitt durch:

- **Build-Stage**: Verwendet den `NodeTool@0`-Task, um eine bestimmte
  Node.js-Version zu installieren. Nach dem Build wird das `dist/`-Verzeichnis
  mit `publish` als Artefakt namens `app-build` gespeichert. Ohne diesen Schritt
  wären die Build-Ergebnisse in den nachfolgenden Stages nicht verfügbar, da
  jede Stage auf einem frischen Agent läuft.
- **Test-Stage**: Hat `dependsOn: Build`, wartet also auf die Build-Stage.
  Enthält zwei Jobs (`UnitTests` und `LintCheck`), die **parallel** laufen, da
  sie keine `dependsOn`-Beziehung zueinander haben. Das spart Zeit.
- **Deploy-Stages**: Beide haben eine `condition`, die prüft, ob der Build auf
  dem `master`-Branch läuft. `and(succeeded(), eq(...))` stellt sicher, dass die
  Stage nur ausgeführt wird, wenn (a) alle vorherigen Stages erfolgreich waren
  und (b) der Branch `master` ist. Auf Feature-Branches werden die Deploy-Stages
  übersprungen.
- **Artefakt-Download**: In den Deploy-Stages wird mit `download: current`
  das zuvor publizierte Artefakt heruntergeladen. `current` bezieht sich auf den
  aktuellen Pipeline-Run.

### Schritt 3: Committen und Pipeline beobachten

Committe alle neuen Dateien und pushe auf `master`. Die Pipeline wird automatisch
gestartet und durchläuft alle vier Stages:

```bash
git add package.json src/app.js test/test.js azure-pipelines.yml
git commit -m "Add multi-stage pipeline with Node.js app"
git push origin master
```

### Schritt 4: Pipeline-Visualisierung anschauen

Azure DevOps zeigt Multi-Stage-Pipelines in einer grafischen Übersicht an, die
den Ablauf und die Abhängigkeiten zwischen den Stages visualisiert.

1. Öffne die Pipeline im Browser unter **Pipelines** und klicke auf den
   laufenden Build.
2. Du siehst jetzt die **Stage-Übersicht** - eine horizontale Kette mit vier
   Stages: Build > Test > Deploy Staging > Deploy Production. Jede Stage zeigt
   ihren Status (wartend, laufend, erfolgreich, fehlgeschlagen).
3. Klicke auf eine einzelne Stage, um deren Jobs und Steps zu sehen. Die
   Detail-Ansicht zeigt die Konsolenausgabe jedes Steps.
4. Beachte in der **Test-Stage**: Die zwei Jobs (`UnitTests` und `LintCheck`)
   werden nebeneinander dargestellt, da sie parallel laufen. Vergleiche die
   Start- und Endzeiten, um zu sehen, dass sie tatsächlich gleichzeitig
   ausgeführt werden.

### Schritt 5: Feature-Branch testen

Um die Conditions in Aktion zu sehen, erstellen wir einen Feature-Branch und
beobachten, welche Stages übersprungen werden:

**Bash:**

```bash
git checkout -b feature/test-condition
echo "// neue Funktion" >> src/app.js
git add src/app.js
git commit -m "Test branch condition"
git push origin feature/test-condition
```

**PowerShell:**

```powershell
git checkout -b feature/test-condition
Add-Content -Path src/app.js -Value "// neue Funktion" -NoNewline:$false
git add src/app.js
git commit -m "Test branch condition"
git push origin feature/test-condition
```

Da `feature/test-condition` nicht im CI-Trigger steht, wird der Build nicht
automatisch gestartet. Starte die Pipeline manuell im Browser: Gehe zu
**Pipelines > hello-pipeline**, klicke auf **"Run pipeline"** und wähle den
Branch `feature/test-condition`.

Beobachte das Ergebnis: **Build** und **Test** werden ausgeführt, aber die
beiden **Deploy-Stages werden übersprungen** (grau dargestellt). Der Grund ist
die `condition: eq(variables['Build.SourceBranchName'], 'master')` - auf einem
Feature-Branch ist diese Bedingung nicht erfüllt. So stellst du sicher, dass nur
getesteter Code auf `master` deployed wird.

## Aufräumen

Lösche den Feature-Branch, da er nur für den Test benötigt wurde:

```bash
git checkout master
git branch -d feature/test-condition
git push origin --delete feature/test-condition
```
