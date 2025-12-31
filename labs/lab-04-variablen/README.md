# Lab 04: Variablen und Variable Groups

## Hintergrund

Variablen machen Pipelines flexibel und wiederverwendbar. Statt Werte wie
Umgebungsnamen, Versionsnummern oder Konfigurationseinstellungen direkt in die
Pipeline-Steps zu schreiben, lagerst du sie in Variablen aus. So kannst du
dieselbe Pipeline für verschiedene Umgebungen oder Konfigurationen verwenden,
ohne den YAML-Code zu duplizieren.

Azure Pipelines kennt mehrere Arten von Variablen:

- **Pipeline-Variablen** (`variables:`): Direkt in der YAML-Datei definiert. Sie
  sind fest an diese Pipeline gebunden und werden beim Start des Builds
  aufgelöst.
- **Variable Groups**: Zentral verwaltete Variablen-Gruppen, die über die
  Azure-DevOps-Oberfläche oder CLI erstellt werden. Vorteil: Mehrere Pipelines
  können dieselbe Variable Group einbinden, und Änderungen an den Werten wirken
  sich sofort auf alle Pipelines aus - ohne YAML-Änderung.
- **Vordefinierte Variablen**: Automatisch von Azure Pipelines bereitgestellt
  (z. B. `Build.BuildId`, `System.TeamProject`). Sie liefern Kontext über den
  aktuellen Build, den Agent und das Projekt.
- **Parameter** (`parameters:`): Eingabewerte, die beim manuellen Start einer
  Pipeline gesetzt werden können. Im Gegensatz zu Variablen haben Parameter
  einen definierten Typ (string, boolean, etc.) und können Auswahloptionen
  anbieten.

Wichtig ist die Unterscheidung der Syntax:

- `$(variableName)` - wird zur **Laufzeit** (Runtime) aufgelöst.
- `${{ expression }}` - wird beim **Parsen der YAML-Datei** (Compile-Time)
  ausgewertet, also bevor der Build überhaupt startet.
- `$VARIABLENAME` - in Bash-Skripten werden Pipeline-Variablen automatisch als
  Umgebungsvariablen bereitgestellt (Großbuchstaben, Punkte werden zu
  Unterstrichen).

## Aufgabenstellung

### Schritt 1: Variable Group erstellen

Bevor wir die Pipeline anlegen, erstellen wir zunächst eine **Variable Group**.
Variable Groups werden außerhalb des Repositorys in Azure DevOps verwaltet. Das
bedeutet, du kannst ihre Werte ändern, ohne einen neuen Commit zu machen. Dies
ist besonders nützlich für umgebungsspezifische Einstellungen, die sich zwischen
Deployments unterscheiden.

**Bash:**
```bash
# Erstelle eine Variable Group namens "common-settings" mit drei Variablen.
# --authorize true gibt die Gruppe für alle Pipelines im Projekt frei.
# Ohne dieses Flag müsstest du beim ersten Pipeline-Lauf die Nutzung
# der Gruppe manuell genehmigen.
az pipelines variable-group create \
  --name "common-settings" \
  --variables \
    ENVIRONMENT=development \
    APP_VERSION=1.0.0 \
    TEAM_NAME=training-team \
  --authorize true \
  --output table
```

**PowerShell:**
```powershell
# Erstelle eine Variable Group namens "common-settings" mit drei Variablen.
# --authorize true gibt die Gruppe für alle Pipelines im Projekt frei.
# Ohne dieses Flag müsstest du beim ersten Pipeline-Lauf die Nutzung
# der Gruppe manuell genehmigen.
az pipelines variable-group create `
  --name "common-settings" `
  --variables `
    ENVIRONMENT=development `
    APP_VERSION=1.0.0 `
    TEAM_NAME=training-team `
  --authorize true `
  --output table
```

Du kannst die erstellte Variable Group auch im Browser unter **Pipelines >
Library** einsehen und bearbeiten.

### Schritt 2: Pipeline mit Variablen erstellen

Jetzt erstellen wir eine Pipeline, die alle Variablen-Arten demonstriert:
Inline-Variablen, Variable Groups, Parameter, vordefinierte Variablen und
dynamisch zur Laufzeit erzeugte Variablen.

Ersetze den Inhalt von `azure-pipelines.yml` in deinem Repository
`hello-pipeline` mit folgendem Inhalt:

```yaml
trigger:
  branches:
    include:
      - main

# Parameter: Können beim manuellen Start gesetzt werden
parameters:
  - name: deployTarget
    displayName: 'Deployment-Ziel'
    type: string
    default: 'staging'
    values:
      - development
      - staging
      - production

  - name: runTests
    displayName: 'Tests ausführen?'
    type: boolean
    default: true

# Inline-Variablen
# Hinweis: Sobald eine Variable Group eingebunden wird, müssen alle
# Variablen in der Listen-Syntax (- name/value) definiert werden.
variables:
  - name: buildConfiguration
    value: 'Release'
  - name: appName
    value: 'hello-pipeline-app'
  - name: isMain
    value: ${{ eq(variables['Build.SourceBranchName'], 'main') }}

  # Variable Group einbinden
  - group: common-settings

pool:
  vmImage: 'ubuntu-22.04'

steps:
  - script: |
      echo "=== Inline-Variablen ==="
      echo "Build Configuration: $(buildConfiguration)"
      echo "App Name:            $(appName)"
      echo "Is Main Branch:      $(isMain)"
    displayName: 'Inline-Variablen anzeigen'

  - script: |
      echo "=== Variable Group: common-settings ==="
      echo "Environment: $(ENVIRONMENT)"
      echo "App Version: $(APP_VERSION)"
      echo "Team Name:   $(TEAM_NAME)"
    displayName: 'Variable Group Werte anzeigen'

  - script: |
      echo "=== Parameter ==="
      echo "Deploy Target: ${{ parameters.deployTarget }}"
      echo "Run Tests:     ${{ parameters.runTests }}"
    displayName: 'Parameter anzeigen'

  - script: |
      echo "=== Vordefinierte Variablen ==="
      echo "Build ID:         $(Build.BuildId)"
      echo "Build Number:     $(Build.BuildNumber)"
      echo "Source Branch:    $(Build.SourceBranch)"
      echo "Agent Name:       $(Agent.Name)"
      echo "Agent OS:         $(Agent.OS)"
      echo "System.TeamProject: $(System.TeamProject)"
      echo "Pipeline Workspace: $(Pipeline.Workspace)"
    displayName: 'Vordefinierte Variablen anzeigen'

  - script: |
      echo "=== Variablen in Bash ==="
      echo "Als Umgebungsvariable: $BUILDCONFIGURATION"
      echo "Als Umgebungsvariable: $APPNAME"
      echo "Als Umgebungsvariable: $ENVIRONMENT"
      echo ""
      echo "Hinweis: In Bash werden Variablennamen in Grossbuchstaben"
      echo "umgewandelt und Punkte/Leerzeichen durch Unterstriche ersetzt."
      echo "Beispiel: Build.BuildId -> BUILD_BUILDID = $BUILD_BUILDID"
    displayName: 'Variablen als Umgebungsvariablen'

  - script: |
      echo "=== Dynamische Variablen setzen ==="
      # Variable für nachfolgende Steps setzen
      echo "##vso[task.setvariable variable=dynamicVar]Wert-$(date +%H%M%S)"
      echo "##vso[task.setvariable variable=buildTimestamp]$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    displayName: 'Dynamische Variablen erzeugen'

  - script: |
      echo "=== Dynamische Variablen lesen ==="
      echo "Dynamic Var:     $(dynamicVar)"
      echo "Build Timestamp: $(buildTimestamp)"
    displayName: 'Dynamische Variablen verwenden'

  - ${{ if eq(parameters.runTests, true) }}:
      - script: |
          echo "Tests werden ausgeführt..."
          echo "Zielumgebung: ${{ parameters.deployTarget }}"
          echo "(In einem echten Projekt würde hier z.B. pytest oder npm test laufen)"
        displayName: 'Tests ausführen'
```

Gehe die Datei Abschnitt für Abschnitt durch, um die verschiedenen Konzepte zu
verstehen:

- **`parameters`**: Definiert zwei Eingabefelder, die beim manuellen Start der
  Pipeline erscheinen. `deployTarget` bietet eine Auswahl aus drei Umgebungen,
  `runTests` ist ein Boolean-Schalter.
- **`variables`**: Enthält statische Inline-Variablen, einen Compile-Time-
  Ausdruck (`${{ eq(...) }}`), der prüft, ob der Build auf `main` läuft, und
  bindet die zuvor erstellte Variable Group ein. Wichtig: Sobald eine Variable
  Group (`- group:`) eingebunden wird, müssen **alle** Variablen in der
  Listen-Syntax (`- name: / value:`) statt der Kurzform (`key: value`)
  definiert werden - Azure Pipelines erlaubt kein Mischen der beiden Formate.
- **Steps "Dynamische Variablen"**: Zeigen, wie man zur Laufzeit neue Variablen
  erzeugt. Der Befehl `##vso[task.setvariable ...]` ist ein sogenanntes
  **Logging Command** - ein spezielles Format, das Azure Pipelines in der
  Konsolenausgabe erkennt und als Anweisung interpretiert. Die so gesetzten
  Variablen sind erst in **nachfolgenden** Steps verfügbar, nicht im selben.
- **Bedingte Ausführung** (`${{ if ... }}`): Der letzte Step wird nur eingefügt,
  wenn der Parameter `runTests` auf `true` steht. Da dies ein
  Compile-Time-Ausdruck ist, wird der Step bei `false` komplett aus der Pipeline
  entfernt. Er erscheint dann nicht einmal im Build-Log.

### Schritt 3: Committen und pushen

Committe die geänderte Pipeline-Datei und pushe sie. Da der CI-Trigger auf
`main` konfiguriert ist, wird automatisch ein Build ausgelöst:

```bash
git add azure-pipelines.yml
git commit -m "Add variables and parameters demo"
git push origin main
```

Dieser automatisch ausgelöste Build verwendet die **Default-Werte** der
Parameter (`deployTarget: staging`, `runTests: true`), da er nicht manuell
gestartet wurde.

Gehe nun im Browser zu **Pipelines** und klicke auf die Pipeline
**hello-pipeline**. Prüfe im Log, dass die Variablen wie erwartet mit den
Default-Werten ausgegeben werden.

### Schritt 4: Pipeline manuell mit Parametern starten

Im vorherigen Schritt wurde die Pipeline durch einen Push automatisch ausgelöst.
Dabei gelten die Default-Werte der Parameter. Jetzt starten wir die Pipeline *
*manuell**, um andere Parameter-Werte zu übergeben.

1. Gehe im Browser zu **Pipelines** und klicke auf die Pipeline
   **hello-pipeline**.
2. Klicke oben rechts auf **"Run pipeline"**.
3. Es erscheint ein Dialog mit den Parameter-Eingabefeldern, die wir in der
   YAML-Datei unter `parameters:` definiert haben:
    - **Deployment-Ziel**: Wähle **"production"** (statt des Defaults
      "staging"). Im Build-Log des Steps "Parameter anzeigen" wirst du diesen
      Wert sehen.
    - **Tests ausführen?**: Lass den Haken auf **true**. Wenn du ihn
      deaktivierst und den Build erneut startest, wirst du sehen, dass der
      Step "Tests ausführen" komplett aus dem Build verschwindet.
4. Klicke auf **"Run"** und vergleiche die Ausgabe mit dem vorherigen
   (automatisch ausgelösten) Build.

Alternativ kannst du die Pipeline auch per CLI mit Parametern starten:

```bash
# Pipeline-ID herausfinden
az pipelines list --output table
```

**Bash:**
```bash
# Pipeline mit Parametern starten (ersetze <pipeline-id> durch die
# tatsächliche ID). Die Parameter werden als Key=Value-Paare übergeben.
az pipelines run --id <pipeline-id> \
  --parameters deployTarget=production runTests=true
```

**PowerShell:**
```powershell
# Pipeline mit Parametern starten (ersetze <pipeline-id> durch die
# tatsächliche ID). Die Parameter werden als Key=Value-Paare übergeben.
az pipelines run --id <pipeline-id> `
  --parameters deployTarget=production runTests=true
```

Gehe nun im Browser zu **Pipelines** und klicke auf die Pipeline
**hello-pipeline**. Prüfe im Log, dass die Werte so von dir belegt
ausgegeben werden.

### Schritt 5: Variable Group aktualisieren

Ein großer Vorteil von Variable Groups ist, dass du ihre Werte jederzeit ändern
kannst, ohne den Pipeline-Code anzufassen. Der nächste Build verwendet dann
automatisch die aktualisierten Werte. Das ist besonders praktisch für Werte wie
Versionsnummern oder Konfigurationseinstellungen, die sich häufig ändern.

```bash
# Zeige alle Variable Groups an. In der Spalte "ID" findest du die
# numerische Group-ID, die du für die folgenden Befehle brauchst.
az pipelines variable-group list --output table
```

**Bash:**
```bash
# Füge eine neue Variable zur Gruppe hinzu (ersetze <group-id> durch die
# tatsächliche ID aus der vorherigen Ausgabe, z. B. 1).
az pipelines variable-group variable create \
  --group-id <group-id> \
  --name "LOG_LEVEL" \
  --value "info"

# Ändere den Wert einer bestehenden Variable. Ab dem nächsten Build wird
# die Pipeline den neuen Wert "1.1.0" statt "1.0.0" verwenden.
az pipelines variable-group variable update \
  --group-id <group-id> \
  --name "APP_VERSION" \
  --value "1.1.0"
```

**PowerShell:**
```powershell
# Füge eine neue Variable zur Gruppe hinzu (ersetze <group-id> durch die
# tatsächliche ID aus der vorherigen Ausgabe, z. B. 1).
az pipelines variable-group variable create `
  --group-id <group-id> `
  --name "LOG_LEVEL" `
  --value "info"

# Ändere den Wert einer bestehenden Variable. Ab dem nächsten Build wird
# die Pipeline den neuen Wert "1.1.0" statt "1.0.0" verwenden.
az pipelines variable-group variable update `
  --group-id <group-id> `
  --name "APP_VERSION" `
  --value "1.1.0"
```

```bash
# Zeige alle Variablen der Gruppe zur Kontrolle an.
az pipelines variable-group show --group-id <group-id> --output json | jq
```

Starte die Pipeline erneut (per Browser oder CLI), um zu prüfen, dass der Step
"Variable Group Werte anzeigen" jetzt `APP_VERSION: 1.1.0` und die neue Variable
`LOG_LEVEL: info` ausgibt.

## Validierung

Prüfe per CLI und im Browser, dass Variable Group und Pipeline korrekt
funktionieren:

```bash
# Prüfe, ob die Variable Group existiert und die erwarteten Variablen enthält.
az pipelines variable-group list --output table

# Prüfe den Status des letzten Builds.
az pipelines runs list --top 1 --output table
```

Öffne im Browser das Build-Log und prüfe die einzelnen Steps:

- Alle `$(...)` -Platzhalter sollten durch tatsächliche Werte ersetzt sein. Wenn
  ein Platzhalter unaufgelöst bleibt (z. B. `$(UNBEKANNT)` steht wortwörtlich in
  der Ausgabe), ist die Variable nicht definiert oder falsch geschrieben.
- Die dynamischen Variablen (`dynamicVar`, `buildTimestamp`) sollten im zweiten
  Step ("Dynamische Variablen verwenden") Werte zeigen, die im ersten Step
  ("Dynamische Variablen erzeugen") gesetzt wurden.

Wir sind mit dieser Aufgabe nun fertig.

Die Variable Group `common-settings` wird in späteren Labs noch verwendet - lösche sie daher nicht.
