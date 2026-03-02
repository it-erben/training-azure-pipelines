# Lab 20: Pipeline-Templates und Wiederverwendung

## Hintergrund

Wenn mehrere Pipelines ähnliche Schritte haben (Build, Test, Deploy), führt
Copy-Paste schnell zu Wartungsproblemen: Eine Verbesserung in einer Pipeline
muss manuell in allen anderen nachgezogen werden. Bug-Fixes werden vergessen,
Konfigurationen driften auseinander, und Standards lassen sich nicht
durchsetzen.

**Pipeline Templates** lösen dieses Problem nach dem DRY-Prinzip ("Don't
Repeat Yourself"). Ein Template ist eine YAML-Datei, die wiederverwendbare
Pipeline-Bausteine definiert. Azure Pipelines unterstützt vier Arten von
Templates:

- **Step Templates**: Wiederverwendbare Sequenzen von Steps. Der häufigste
  Typ — z. B. "Node.js installieren, Abhängigkeiten laden, Build ausführen"
  als Template, das jede Pipeline einbinden kann.
- **Job Templates**: Wiederverwendbare Jobs mit Pool-Konfiguration und Steps.
  Nützlich für Standard-Jobs wie "Build Job" oder "Deploy Job".
- **Stage Templates**: Wiederverwendbare Stages mit Jobs. Ermöglichen
  komplette Pipeline-Abschnitte (z. B. eine vollständige CI/CD-Kette) als
  Template.
- **Variable Templates**: Gemeinsame Variablen-Definitionen. Zentrale
  Konfiguration von Werten wie Node-Version, Azure-Subscription oder
  Resource-Group-Name.

Templates können im **selben Repository** oder in einem **separaten
Template-Repository** liegen. Letzteres ist besonders nützlich für
organisationsweite Standards: Ein Platform-Team pflegt die Templates zentral,
und alle Projekt-Pipelines binden sie über `resources.repositories` ein.

### Template-Parameter

Templates akzeptieren **Parameter**, die beim Einbinden gesetzt werden können.
Parameter haben einen Typ (`string`, `boolean`, `number`, `object`), einen
optionalen Default-Wert und optionale Einschränkungen (`values`). Beim
Parsen der YAML-Datei (`${{ }}`-Syntax, Compile-Time) werden die Parameter
aufgelöst und das Template wird "inline" in die Pipeline eingefügt.

### Template-Referenzen

Templates werden mit dem `template`-Keyword eingebunden:

```yaml
# Template aus demselben Repository (relativer Pfad)
- template: templates/build-steps.yml

# Template aus einem externen Repository (mit @alias)
- template: steps/nodejs-build.yml@templates
```

Das `@templates`-Suffix verweist auf ein Repository, das unter
`resources.repositories` mit dem Alias `templates` definiert ist.

## Aufgabenstellung

### Schritt 1: Template-Repository erstellen

Wir erstellen ein separates Repository für die Templates, damit sie
projektübergreifend nutzbar sind. In der Praxis pflegt oft ein Platform- oder
DevOps-Team dieses Repository.

```bash
# Neues Repository für Templates erstellen
az repos create --name "pipeline-templates" --output table
```

**Bash:**

```bash
# Klonen
cd ~
git clone https://dev.azure.com/<organisations-name>/<dein-projektname>/_git/pipeline-templates
cd pipeline-templates
```

**PowerShell:**

```powershell
# Klonen
Set-Location $HOME
git clone https://dev.azure.com/<organisations-name>/<dein-projektname>/_git/pipeline-templates
Set-Location pipeline-templates
```

Erstelle die Verzeichnisstruktur für die verschiedenen Template-Typen:

**Bash:**

```bash
mkdir -p steps jobs stages variables
```

**PowerShell:**

```powershell
New-Item -ItemType Directory -Force -Path steps, jobs, stages, variables | Out-Null
```

### Schritt 2: Step-Templates erstellen

Step-Templates sind die granularsten Bausteine. Jedes Template definiert eine
Sequenz von Steps, die in beliebigen Jobs eingebunden werden kann.

Erstelle die Datei **steps/nodejs-build.yml** — ein Template für den
Standard-Build-Prozess einer Node.js-Anwendung. Es installiert die gewünschte
Node.js-Version, lädt die Abhängigkeiten und führt den Build aus:

```yaml
# Step-Template: Node.js Build
# Verwendung:
#   - template: steps/nodejs-build.yml
#     parameters:
#       nodeVersion: '20.x'

parameters:
  - name: nodeVersion
    type: string
    default: '20.x'
  - name: workingDirectory
    type: string
    default: '$(System.DefaultWorkingDirectory)'

steps:
  - task: NodeTool@0
    inputs:
      versionSpec: ${{ parameters.nodeVersion }}
    displayName: 'Node.js ${{ parameters.nodeVersion }} installieren'

  - script: |
      echo "Node.js Version: $(node --version)"
      echo "npm Version: $(npm --version)"
    displayName: 'Versionen prüfen'
    workingDirectory: ${{ parameters.workingDirectory }}

  - script: npm ci || npm install
    displayName: 'Abhängigkeiten installieren'
    workingDirectory: ${{ parameters.workingDirectory }}

  - script: npm run build --if-present
    displayName: 'Build ausführen'
    workingDirectory: ${{ parameters.workingDirectory }}
```

Beachte die Template-Mechanismen:

- **`parameters`**: Definiert die Eingabewerte des Templates. `nodeVersion`
  hat den Default `'20.x'`, kann aber beim Einbinden überschrieben werden.
  `workingDirectory` erlaubt es, den Build in einem Unterverzeichnis
  auszuführen (z. B. in einem Monorepo).
- **`${{ parameters.nodeVersion }}`**: Compile-Time-Ausdruck. Der Wert wird
  beim Parsen der YAML-Datei eingesetzt — bevor der Build startet.
- **`npm ci || npm install`**: Fallback-Strategie. `npm ci` ist für CI/CD
  optimiert (schneller, strikter), funktioniert aber nur wenn eine
  `package-lock.json` existiert. Falls nicht, wird `npm install` verwendet.

Erstelle die Datei **steps/run-tests.yml** — ein Template für Tests mit
optionaler Publizierung der Testergebnisse:

```yaml
# Step-Template: Tests ausführen und Ergebnisse publizieren
parameters:
  - name: testCommand
    type: string
    default: 'npm test'
  - name: testResultsFormat
    type: string
    default: 'JUnit'
    values:
      - JUnit
      - NUnit
      - VSTest
      - XUnit
  - name: testResultsFiles
    type: string
    default: '**/test-results.xml'

steps:
  - script: ${{ parameters.testCommand }}
    displayName: 'Tests ausführen'
    continueOnError: true

  - task: PublishTestResults@2
    condition: always()
    inputs:
      testResultsFormat: ${{ parameters.testResultsFormat }}
      testResultsFiles: ${{ parameters.testResultsFiles }}
      testRunTitle: 'Automated Tests'
    displayName: 'Testergebnisse publizieren'
```

Dieses Template zeigt zwei weitere Patterns:

- **`values`**: Schränkt die erlaubten Werte für `testResultsFormat` ein.
  Azure Pipelines meldet beim Parsen einen Fehler, wenn ein ungültiger Wert
  übergeben wird.
- **`continueOnError: true`**: Der Test-Step darf fehlschlagen, ohne dass die
  Pipeline abbricht. So kann der nachfolgende
  `PublishTestResults@2`-Step die Ergebnisse trotzdem publizieren.
- **`condition: always()`**: Der PublishTestResults-Step läuft auch dann, wenn
  der Test-Step fehlgeschlagen ist — genau das ist gewünscht, damit die
  Testergebnisse im Azure DevOps UI sichtbar sind.

### Schritt 3: Job-Templates erstellen

Job-Templates kapseln komplette Jobs inklusive Pool-Konfiguration. Sie
bündeln typischerweise mehrere Step-Templates zu einem logischen Ganzen.

Erstelle die Datei **jobs/build-job.yml** — ein Standard-Build-Job, der das
Step-Template aus Schritt 2 einbindet und optional ein Artefakt publiziert:

```yaml
# Job-Template: Standard Build Job
parameters:
  - name: nodeVersion
    type: string
    default: '20.x'
  - name: publishArtifact
    type: boolean
    default: true
  - name: artifactName
    type: string
    default: 'build-output'

jobs:
  - job: Build
    displayName: 'Build (${{ parameters.nodeVersion }})'
    pool:
      vmImage: 'ubuntu-latest'
    steps:
      - template: ../steps/nodejs-build.yml
        parameters:
          nodeVersion: ${{ parameters.nodeVersion }}

      - ${{ if parameters.publishArtifact }}:
        - publish: $(System.DefaultWorkingDirectory)/dist
          artifact: ${{ parameters.artifactName }}
          displayName: 'Artefakte publizieren'
```

Beachte die **verschachtelten Templates**: Das Job-Template bindet das
Step-Template `../steps/nodejs-build.yml` ein und leitet den
`nodeVersion`-Parameter durch. Die bedingte Artefakt-Publizierung
(`${{ if parameters.publishArtifact }}`) ermöglicht es, das Template
sowohl in CI-Pipelines (mit Artefakt) als auch in PR-Validierungs-Pipelines
(ohne Artefakt) zu verwenden.

Erstelle die Datei **jobs/deploy-job.yml** — ein Deployment-Job-Template mit
Environment-Integration:

```yaml
# Job-Template: Deployment Job
parameters:
  - name: environment
    type: string
  - name: azureSubscription
    type: string
  - name: appName
    type: string
  - name: artifactName
    type: string
    default: 'build-output'

jobs:
  - deployment: Deploy
    displayName: 'Deploy to ${{ parameters.environment }}'
    pool:
      vmImage: 'ubuntu-latest'
    environment: ${{ parameters.environment }}
    strategy:
      runOnce:
        deploy:
          steps:
            - script: |
                echo "Deploying to ${{ parameters.environment }}"
                echo "App: ${{ parameters.appName }}"
                echo "Artefakte:"
                ls -la $(Pipeline.Workspace)/${{ parameters.artifactName }}/
              displayName: 'Deployment Info'

            # In einem realen Szenario würde hier der AzureWebApp-Task stehen
            - script: |
                echo "Deployment nach ${{ parameters.environment }} abgeschlossen!"
              displayName: 'Deploy'
```

Dieses Template hat **Pflicht-Parameter** (`environment`, `azureSubscription`,
`appName`) ohne Default-Wert. Azure Pipelines meldet beim Parsen einen
Fehler, wenn diese Parameter beim Einbinden nicht angegeben werden.

### Schritt 4: Stage-Template erstellen

Stage-Templates kapseln komplette Pipeline-Abschnitte — mehrere Stages mit
Jobs, Abhängigkeiten und Bedingungen. Sie eignen sich für
organisationsweite Standards: "Jede Anwendung durchläuft Build, Test und
Deploy in dieser Reihenfolge."

Erstelle die Datei **stages/standard-pipeline.yml** — eine vollständige
CI/CD-Kette aus Build-, Test- und Deploy-Stages:

```yaml
# Stage-Template: Standard CI/CD Pipeline
# Enthält Build, Test und Deploy Stages
parameters:
  - name: nodeVersion
    type: string
    default: '20.x'
  - name: environments
    type: object
    default:
      - name: dev
        dependsOn: Test
      - name: staging
        dependsOn: DeployDev
  - name: azureSubscription
    type: string
    default: ''
  - name: appNamePrefix
    type: string
    default: 'myapp'
  - name: runTests
    type: boolean
    default: true

stages:
  # Build Stage
  - stage: Build
    displayName: 'Build'
    jobs:
      - template: ../jobs/build-job.yml
        parameters:
          nodeVersion: ${{ parameters.nodeVersion }}

  # Test Stage (optional)
  - ${{ if parameters.runTests }}:
    - stage: Test
      displayName: 'Test'
      dependsOn: Build
      jobs:
        - job: RunTests
          pool:
            vmImage: 'ubuntu-latest'
          steps:
            - template: ../steps/nodejs-build.yml
              parameters:
                nodeVersion: ${{ parameters.nodeVersion }}
            - template: ../steps/run-tests.yml

  # Deploy Stages (dynamisch aus environments-Parameter)
  - ${{ each env in parameters.environments }}:
    - stage: Deploy${{ env.name }}
      displayName: 'Deploy ${{ env.name }}'
      dependsOn: ${{ env.dependsOn }}
      jobs:
        - template: ../jobs/deploy-job.yml
          parameters:
            environment: ${{ env.name }}
            azureSubscription: ${{ parameters.azureSubscription }}
            appName: '${{ parameters.appNamePrefix }}-${{ env.name }}'
```

Dieses Template zeigt zwei fortgeschrittene Mechanismen:

- **`${{ if parameters.runTests }}`**: Bedingte Stage. Wenn `runTests` auf
  `false` steht, wird die Test-Stage komplett aus der Pipeline entfernt —
  sie erscheint nicht einmal im Build-Log. Das ist ein Compile-Time-Ausdruck,
  kein Runtime-Condition.
- **`${{ each env in parameters.environments }}`**: Iteration über ein
  Object-Array. Für jeden Eintrag im `environments`-Parameter wird eine
  Deploy-Stage generiert. So kann die aufrufende Pipeline beliebig viele
  Zielumgebungen definieren — das Template erzeugt automatisch die
  entsprechenden Stages. Der `dependsOn`-Wert aus dem Array steuert die
  Reihenfolge.

### Schritt 5: Variable-Template erstellen

Variable-Templates zentralisieren Konfigurationswerte. Alle Pipelines, die
das Template einbinden, verwenden automatisch dieselben Werte — Änderungen
wirken sich sofort auf alle aus.

Erstelle die Datei **variables/common.yml**:

```yaml
# Gemeinsame Variablen für alle Pipelines
variables:
  nodeVersion: '20.x'
  buildConfiguration: 'Release'
  azureSubscription: 'azure-training-connection'
  resourceGroup: 'rg-pipeline-training'
  location: 'westeurope'
```

### Schritt 6: Templates committen und pushen

```bash
git add -A
git commit -m "Add pipeline templates library"
git push origin master
```

### Schritt 7: Templates in der Anwendungs-Pipeline verwenden

Jetzt wechseln wir zurück zum Anwendungs-Repository und binden die Templates
aus dem Template-Repository ein. Die Verbindung zwischen den Repositories
wird über `resources.repositories` hergestellt.

**Bash:**

```bash
cd ~/hello-pipeline
```

**PowerShell:**

```powershell
Set-Location $HOME/hello-pipeline
```

Ersetze den Inhalt von `azure-pipelines.yml`:

```yaml
trigger:
  branches:
    include:
      - master

resources:
  repositories:
    - repository: templates
      type: git
      name: <dein-projektname>/pipeline-templates
      ref: refs/heads/master

# Gemeinsame Variablen aus Template
variables:
  - template: variables/common.yml@templates

stages:
  # Variante 1: Einzelne Templates einbinden
  - stage: Build
    displayName: 'Build'
    jobs:
      - job: BuildApp
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - template: steps/nodejs-build.yml@templates
            parameters:
              nodeVersion: $(nodeVersion)

          - script: |
              echo "Build mit Template erfolgreich!"
              echo "Node Version: $(nodeVersion)"
              echo "Configuration: $(buildConfiguration)"
            displayName: 'Build-Info'

          - publish: $(System.DefaultWorkingDirectory)
            artifact: app-build
            displayName: 'Artefakte publizieren'

  - stage: Test
    displayName: 'Test'
    dependsOn: Build
    jobs:
      - job: TestApp
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - template: steps/nodejs-build.yml@templates
          - template: steps/run-tests.yml@templates
            parameters:
              testCommand: 'npm test'

  - stage: DeployDev
    displayName: 'Deploy Dev'
    dependsOn: Test
    jobs:
      - template: jobs/deploy-job.yml@templates
        parameters:
          environment: 'dev'
          azureSubscription: $(azureSubscription)
          appName: 'hello-pipeline-dev'
```

Gehe die Pipeline Abschnitt für Abschnitt durch:

- **`resources.repositories`**: Definiert das externe Repository mit dem
  Alias `templates`. `type: git` bedeutet, dass es ein Azure Repos
  Git-Repository im selben Projekt ist. `name` folgt dem Format
  `<projekt>/<repository>`. `ref: refs/heads/master` pinnt die Templates auf
  den `master`-Branch — in der Praxis würde man einen Tag verwenden
  (z. B. `ref: refs/tags/v1.0`), um stabile Versionen zu garantieren.
- **`variables` mit Template**: Statt Variablen direkt in der Pipeline zu
  definieren, werden sie aus `variables/common.yml@templates` geladen. Das
  `@templates`-Suffix verweist auf das externe Repository.
- **Step-Template-Einbindung**: `template: steps/nodejs-build.yml@templates`
  bindet das Node.js-Build-Template ein. Parameter werden über den
  `parameters`-Block übergeben. Ohne Parameter-Block werden die
  Default-Werte des Templates verwendet (wie in der Test-Stage).
- **Job-Template-Einbindung**: In der DeployDev-Stage wird ein komplettes
  Job-Template eingebunden. Beachte den Unterschied: Step-Templates stehen
  innerhalb eines `steps:`-Blocks, Job-Templates innerhalb eines
  `jobs:`-Blocks.

### Schritt 8: Committen und Pipeline beobachten

```bash
git add azure-pipelines.yml
git commit -m "Use pipeline templates from shared repository"
git push origin master
```

Beobachte den Pipeline-Run im Browser. Die Steps, die aus Templates stammen,
erscheinen in der Pipeline wie reguläre Steps — du siehst die
`displayName`-Werte aus den Templates (z. B. "Node.js 20.x installieren",
"Abhängigkeiten installieren").

## Validierung

```bash
# Prüfe, ob das Template-Repository existiert
az repos list --output table

# Pipeline-Status
az pipelines runs list --top 1 --output table
```

Öffne im Browser den Pipeline-Run und prüfe:

- Die Steps aus dem Template `steps/nodejs-build.yml` erscheinen in der
  Build-Stage: "Node.js 20.x installieren", "Versionen prüfen",
  "Abhängigkeiten installieren", "Build ausführen".
- Die Steps aus `steps/run-tests.yml` erscheinen in der Test-Stage.
- Der Deploy-Job aus `jobs/deploy-job.yml` erscheint in der DeployDev-Stage.
- Die Variablen `$(nodeVersion)` und `$(buildConfiguration)` werden mit den
  Werten aus dem Variable-Template aufgelöst.

## Erwartetes Ergebnis

Die Pipeline verwendet Templates aus dem separaten Repository. Im Build-Log
siehst du die Steps, die aus den Templates kommen:

```
Node.js 20.x installieren
Versionen prüfen
Abhängigkeiten installieren
Build ausführen
Build-Info
```

Die Steps erscheinen in der Pipeline wie reguläre Steps — es ist im Log
nicht direkt erkennbar, dass sie aus einem Template stammen. Um die aufgelöste
YAML-Datei zu sehen, klicke beim Pipeline-Run auf die drei Punkte (...) >
**"Download full YAML"**.

## Aufräumen

Das Template-Repository kann für zukünftige Projekte nützlich sein. Falls du
es löschen möchtest:

```bash
# Repository-ID herausfinden
az repos list --output table

# Repository löschen (ersetze <repo-id> durch die tatsächliche ID)
# az repos delete --id <repo-id> --yes
```

## Tipps und Troubleshooting

- **"Template not found"**: Prüfe den Repository-Namen in
  `resources.repositories`. Das Format ist `<projekt>/<repository>`. Prüfe
  auch, ob der Branch (`ref`) existiert und ob die Template-Datei am
  angegebenen Pfad liegt.
- **Template-Referenz mit und ohne `@`**: Templates aus dem **eigenen
  Repository** brauchen kein `@`-Suffix (z. B. `template: templates/build.yml`).
  Templates aus **externen Repositories** brauchen `@<alias>` (z. B.
  `template: steps/build.yml@templates`).
- **Pflicht-Parameter**: Parameter ohne Default-Wert müssen beim Einbinden
  angegeben werden. Azure Pipelines meldet beim Parsen einen Fehler, wenn ein
  Pflicht-Parameter fehlt.
- **Verschachtelte Templates**: Templates können andere Templates einbinden
  (wie unser Job-Template, das Step-Templates einbindet). Achte auf
  **zirkuläre Referenzen** — Template A bindet Template B ein, das wiederum
  Template A einbindet. Azure Pipelines erkennt das und meldet einen Fehler.
- **Versionierung**: Verwende `ref: refs/tags/v1.0` statt
  `ref: refs/heads/master` für stabile Template-Versionen. So kannst du
  Templates weiterentwickeln, ohne laufende Pipelines zu brechen. Pipelines
  aktualisieren auf eine neue Version durch Ändern des `ref`-Werts.
- **Template-Debugging**: Bei Fehlern in Templates zeigt Azure DevOps die
  aufgelöste (expandierte) YAML-Datei an. Klicke beim Pipeline-Run auf die
  drei Punkte (...) > **"Download full YAML"**. Die heruntergeladene Datei
  zeigt die Pipeline mit allen eingefügten Templates — nützlich für die
  Fehlersuche.
- **`extends`-Templates**: Neben `template` gibt es `extends` — ein
  Mechanismus, bei dem das Template die **Grundstruktur** der Pipeline
  vorgibt und die aufrufende Pipeline nur noch Parameter übergibt. Das ist
  nützlich für Sicherheitsrichtlinien: Das Platform-Team definiert
  Pflicht-Steps (z. B. Security Scans), die kein Projekt-Team überspringen
  kann.
