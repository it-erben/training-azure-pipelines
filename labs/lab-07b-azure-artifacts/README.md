# Lab 07b: npm-Pakete in Azure Artifacts publizieren

## Hintergrund

In Lab 07 haben wir **Pipeline Artifacts** kennengelernt: temporäre Artefakte,
die zwischen Stages eines Pipeline-Runs geteilt werden. Pipeline Artifacts sind
ephemer - sie dienen dem Datenaustausch innerhalb einer Pipeline und werden nach
der konfigurierten Aufbewahrungsdauer automatisch gelöscht.

**Azure Artifacts** ist ein anderer Mechanismus: eine permanente Paket-Registry,
die in Azure DevOps integriert ist. Hier können npm-, NuGet-, Maven-, Python-
und Universal Packages dauerhaft gespeichert und versioniert werden. Andere
Projekte und Pipelines können diese Pakete als Abhängigkeiten konsumieren - genau
wie Pakete von npmjs.com oder NuGet.org.

Die zentrale Organisationseinheit in Azure Artifacts ist der **Feed**: eine
Sammlung von Paketen, die entweder auf Projekt- oder Organisations-Ebene
existiert. Feeds können **Upstream Sources** einbinden - z. B. npmjs.com als
Proxy. Dann werden öffentliche Pakete beim ersten Abruf im Feed gecacht, und alle
Abhängigkeiten kommen aus einer einzigen Quelle.

In diesem Lab erstellen wir ein kleines Utility-Paket und publizieren es über
eine Pipeline in einen Azure Artifacts Feed.

## Aufgabenstellung

### Schritt 1: Azure Artifacts Feed erstellen

Ein Feed ist die Sammlung, in der unsere npm-Pakete gespeichert werden. Wir
erstellen einen projekt-scoped Feed über die Azure DevOps UI:

1. Gehe zu **Artifacts** im linken Menü deines Projekts.
2. Klicke auf **"Create Feed"**.
3. Name: `npm-training`.
4. Visibility: **"Members of your Microsoft Entra tenant"** (Standard).
5. Setze den Haken bei **"Include packages from common public sources"** - das
   aktiviert Upstream Sources (npmjs.com wird als Proxy eingebunden).
6. Klicke auf **"Create"**.

Der Feed ist jetzt unter **Artifacts > npm-training** sichtbar. Damit die
Pipeline Pakete in den Feed publizieren kann, muss der Build Service als
**Contributor** berechtigt werden:

1. Öffne den Feed **npm-training** und klicke auf das Zahnrad-Symbol
   (**Feed Settings**).
2. Wechsle zum Tab **"Permissions"**.
3. Klicke auf **"Add users/groups"**.
4. Suche nach **"[dein Projektname] Build Service"** (z. B.
   `teilnehmer01 Build Service (iterben)`).
5. Rolle: **Contributor**.
6. Klicke auf **"Save"**.

### Schritt 2: Utility-Paket erstellen

Wir erstellen ein kleines Node.js-Paket, das die Hilfsfunktionen `greet()` und
`add()` aus Lab 06 als wiederverwendbares Modul bereitstellt. In der Praxis
werden geteilte Funktionen häufig als interne Pakete über eine Paket-Registry
verteilt, statt Code zwischen Repositories zu kopieren.

Erstelle ein neues Verzeichnis `hello-utils` im Wurzelverzeichnis deines
`hello-pipeline`-Repositorys:

**Bash:**

```bash
mkdir -p hello-utils
```

**PowerShell:**

```powershell
New-Item -ItemType Directory -Force -Path hello-utils | Out-Null
```

Erstelle die Datei **hello-utils/package.json**:

```json
{
  "name": "hello-pipeline-utils",
  "version": "1.0.0",
  "description": "Utility-Funktionen fuer hello-pipeline",
  "main": "index.js",
  "scripts": {
    "test": "echo 'Running tests...' && node index.test.js"
  }
}
```

Erstelle die Datei **hello-utils/index.js**:

```javascript
function greet(name) {
    return `Hello, ${name}! Welcome to Azure Pipelines.`;
}

function add(a, b) {
    return a + b;
}

module.exports = {greet, add};
```

Erstelle die Datei **hello-utils/index.test.js** mit denselben Tests wie in
Lab 06:

```javascript
const {greet, add} = require('./index');

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

Das Paket hat keine externen Abhängigkeiten und kann mit `npm test` getestet
werden. Der Name `hello-pipeline-utils` ist bewusst unscoped (kein
`@scope/`-Prefix), da scoped Packages eine zusätzliche `.npmrc`-Konfiguration
erfordern.

### Schritt 3: Pipeline mit Publish-Stage

Jetzt erstellen wir eine Pipeline mit zwei Stages: **Build & Test** baut und
testet das Paket, **Publish** veröffentlicht es im Azure Artifacts Feed.

Ersetze den Inhalt von `azure-pipelines.yml`:

```yaml
trigger:
  branches:
    include:
      - master

variables:
  nodeVersion: '20.x'

stages:
  # ===== Build & Test =====
  - stage: BuildAndTest
    displayName: 'Build & Test'
    jobs:
      - job: BuildJob
        displayName: 'Build and Test Package'
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - task: NodeTool@0
            inputs:
              versionSpec: '$(nodeVersion)'
            displayName: 'Node.js installieren'

          - script: |
              cd hello-utils
              npm test
            displayName: 'Unit Tests ausführen'

          - script: |
              cd hello-utils
              npm version 1.0.$(Build.BuildId) --no-git-tag-version
            displayName: 'Version setzen'

          - publish: $(System.DefaultWorkingDirectory)/hello-utils
            artifact: hello-utils-package
            displayName: 'Paket als Pipeline Artifact publizieren'

  # ===== Publish to Feed =====
  - stage: Publish
    displayName: 'Publish to Feed'
    dependsOn: BuildAndTest
    jobs:
      - job: PublishJob
        displayName: 'Publish npm Package'
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - download: current
            artifact: hello-utils-package
            displayName: 'Pipeline Artifact herunterladen'

          - task: Npm@1
            displayName: 'npm publish'
            inputs:
              command: 'publish'
              workingDir: '$(Pipeline.Workspace)/hello-utils-package'
              publishRegistry: 'useFeed'
              publishFeed: '$(System.TeamProject)/npm-training'
```

Gehe die Pipeline Abschnitt für Abschnitt durch:

- **Build & Test**: Installiert Node.js, wechselt in das `hello-utils`-
  Verzeichnis und führt die Tests aus. Anschließend wird die Version mit
  `npm version 1.0.$(Build.BuildId) --no-git-tag-version` auf einen eindeutigen
  Wert gesetzt. `$(Build.BuildId)` ist eine aufsteigende Zahl, die Azure
  Pipelines für jeden Build vergibt. Das `--no-git-tag-version`-Flag verhindert,
  dass npm versucht, einen Git-Tag zu erstellen (was auf dem Build-Agent
  fehlschlagen würde). Danach wird das gesamte `hello-utils`-Verzeichnis als
  Pipeline Artifact gespeichert.
- **Dynamische Versionierung**: npm-Registries lehnen das Publizieren einer
  Version ab, die bereits existiert. Durch die Verwendung von `$(Build.BuildId)`
  im Patch-Segment (z. B. `1.0.42`, `1.0.43`, ...) erhält jeder Build
  automatisch eine eindeutige Version.
- **Publish**: Lädt das Pipeline Artifact herunter und verwendet den `Npm@1`-Task
  mit `command: publish`, um das Paket im Feed zu veröffentlichen.
  `publishRegistry: useFeed` weist den Task an, die Authentifizierung über Azure
  Pipelines abzuwickeln (kein manuelles Token nötig). `publishFeed` referenziert
  den Feed im Format `<projektname>/<feedname>`. Die vordefinierte Variable
  `$(System.TeamProject)` wird automatisch mit dem Namen des aktuellen Azure
  DevOps Projekts aufgelöst, sodass kein manueller Platzhalter ersetzt werden
  muss.

### Schritt 4: Committen und Pipeline starten

```bash
git add hello-utils/ azure-pipelines.yml
git commit -m "Add npm package publishing to Azure Artifacts"
git push origin master
```

Beim ersten Lauf der Pipeline mit dem `Npm@1`-Task muss die Nutzung
möglicherweise einmalig genehmigt werden. Öffne den Pipeline-Run im Browser -
du siehst eine Meldung wie *"This pipeline needs permission to access a resource
before this run can continue"*. Klicke auf **"View"** und dann auf **"Permit"**.

### Schritt 5: Paket im Feed prüfen

Nach erfolgreichem Pipeline-Run kannst du das Paket im Feed sehen:

1. Gehe zu **Artifacts** im linken Menü.
2. Wähle den Feed **npm-training**.
3. Du siehst das Paket `hello-pipeline-utils` in der Liste.
4. Klicke auf das Paket, um Details zu sehen: Version, Publish-Datum und
   Description.
5. Starte die Pipeline ein zweites Mal (z. B. über **"Run pipeline"** im
   Browser). Nach dem zweiten Run erscheint eine neue Version im Feed (z. B.
   `1.0.43` statt `1.0.42`).

## Aufräumen

Lösche den Feed über die Azure DevOps UI:

1. Gehe zu **Artifacts > npm-training**.
2. Klicke auf das Zahnrad-Symbol (**Feed Settings**).
3. Klicke auf **"Delete Feed"** und bestätige.

Das Verzeichnis `hello-utils/` kann im Repository bleiben oder gelöscht werden.
