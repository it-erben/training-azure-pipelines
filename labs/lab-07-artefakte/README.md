# Lab 07: Build-Artefakte erzeugen und publizieren

## Hintergrund

Build-Artefakte sind die Ergebnisse eines Build-Prozesses: kompilierte Binaries,
Pakete, Konfigurationsdateien oder Deployables. In Azure Pipelines gibt es zwei
Mechanismen:

- **Pipeline Artifacts** (empfohlen): Schneller Upload/Download, verwendet Azure
  Pipelines internen Speicher. Keywords: `publish` und `download`.
- **Build Artifacts (Legacy)**: Älterer Mechanismus, verwendet
  `PublishBuildArtifacts@1` und `DownloadBuildArtifacts@0` Tasks.

Artefakte überleben die Lebensdauer eines Jobs und können zwischen Stages, Jobs
und sogar zwischen Pipeline-Runs geteilt werden. In Lab 06 haben wir Artefakte
bereits genutzt, um Build-Ergebnisse zwischen Stages zu übertragen. In diesem
Lab vertiefen wir das Thema: Wir erzeugen ein Build-Manifest mit Metadaten,
publizieren Test-Reports im JUnit-Format und verifizieren in einer eigenen
Stage, dass alle erwarteten Artefakte vorhanden und vollständig sind.

Zusätzlich lernen wir den `PublishTestResults@2`-Task kennen, der
Test-Ergebnisse im JUnit-Format an Azure DevOps übergibt. Die Ergebnisse
erscheinen dann im
**Tests**-Tab des Pipeline-Runs - mit Übersicht über bestandene und
fehlgeschlagene Tests, Laufzeiten und Trends über mehrere Builds hinweg.

## Aufgabenstellung

### Schritt 1: Build-Skript erstellen

Für dieses Lab erweitern wir das Projekt um ein Build-Skript, das die Anwendung
baut und ein Build-Manifest mit Metadaten erzeugt. Das Manifest enthält
Informationen wie die Build-Nummer, den Git-Commit und eine Liste der erzeugten
Dateien. Solche Manifeste sind in der Praxis nützlich, um nachzuvollziehen,
welcher Code in welchem Build enthalten ist.

Erstelle die Datei **build.sh** im Wurzelverzeichnis deines
`hello-pipeline`-Repositorys:

```bash
#!/bin/bash
set -e

echo "=== Build gestartet ==="
BUILD_NUMBER=${1:-"local"}
echo "Build Number: $BUILD_NUMBER"

# Erstelle dist-Verzeichnis
rm -rf dist
mkdir -p dist

# Dateien kopieren
cp src/*.js dist/
cp index.html dist/

# Version in die App einbauen
echo "const BUILD_INFO = { version: '1.0.0', build: '$BUILD_NUMBER', date: '$(date -u +%Y-%m-%dT%H:%M:%SZ)' };" >> dist/app.js

# Build-Manifest erstellen
cat > dist/build-manifest.json << MANIFESTEOF
{
  "version": "1.0.0",
  "buildNumber": "$BUILD_NUMBER",
  "buildDate": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "gitCommit": "$(git rev-parse HEAD 2>/dev/null || echo 'unknown')",
  "gitBranch": "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')",
  "files": $(find dist -type f -name '*.js' -o -name '*.html' | sort | python3 -c "import sys,json; print(json.dumps([l.strip().replace('dist/','') for l in sys.stdin]))")
}
MANIFESTEOF

echo ""
echo "=== Build erfolgreich ==="
echo "Artefakte in dist/:"
ls -la dist/
echo ""
echo "Build-Manifest:"
cat dist/build-manifest.json
```

Das Skript nimmt die Build-Nummer als Argument entgegen (oder verwendet
`"local"` als Fallback), kopiert die Anwendungsdateien in ein `dist/`-
Verzeichnis und erzeugt ein JSON-Manifest mit Build-Metadaten. In der Pipeline
übergeben wir die vordefinierte Variable `$(Build.BuildNumber)`, sodass jeder
Build eindeutig identifizierbar ist.

Mache das Skript ausführbar:

**Bash auf UNIX-Systemen (Linux, macOS):**
```bash
git checkout master
git add build.sh
chmod +x build.sh
```

**PowerShell:**
```powershell
git checkout master
git add build.sh
# chmod existiert nicht auf Windows. Stattdessen setzen wir das
# Executable-Bit direkt im Git-Index — der Pipeline-Agent (Linux)
# braucht es, damit bash das Skript ausführen kann.
git update-index --chmod=+x build.sh
```

### Schritt 2: Test-Report-Generator erstellen

Azure DevOps kann Test-Ergebnisse im JUnit-XML-Format einlesen und im
**Tests**-Tab des Pipeline-Runs visualisieren. Da unser minimales Test-Framework
aus Lab 06 kein JUnit-XML erzeugt, erstellen wir ein kleines Skript, das einen
Report im richtigen Format generiert.

Erstelle die Datei **test/generate-report.sh**:

```bash
#!/bin/bash
mkdir -p test-results

cat > test-results/test-report.xml << XMLEOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites tests="3" failures="0" time="0.42">
  <testsuite name="hello-pipeline" tests="3" failures="0" time="0.42">
    <testcase name="greet returns correct message" time="0.12"/>
    <testcase name="add(2,3) returns 5" time="0.15"/>
    <testcase name="add(-1,1) returns 0" time="0.15"/>
  </testsuite>
</testsuites>
XMLEOF

echo "Test-Report erstellt: test-results/test-report.xml"
```

Das Skript erzeugt eine statische JUnit-XML-Datei mit drei bestandenen Tests. In
einem realen Projekt würde das Test-Framework (z. B. Jest, Mocha, pytest) diesen
Report automatisch erzeugen. Hier simulieren wir das Ergebnis, um den
`PublishTestResults@2`-Task zu demonstrieren.

Mache auch dieses Skript ausführbar:

**Bash auf UNIX-Systemen (Linux, macOS):**
```bash
chmod +x test/generate-report.sh
```

**PowerShell:**
```powershell
git add test/generate-report.sh
git update-index --chmod=+x test/generate-report.sh
```

### Schritt 3: Pipeline mit Artefakt-Management

Jetzt erstellen wir eine Pipeline mit drei Stages, die den vollständigen
Artefakt-Lebenszyklus abbilden: Erzeugen, Testen und Verifizieren. Ersetze den
Inhalt von `azure-pipelines.yml`:

```yaml
trigger:
  branches:
    include:
      - master

variables:
  nodeVersion: '20.x'

stages:
  # ===== Build Stage =====
  - stage: Build
    displayName: 'Build'
    jobs:
      - job: BuildApp
        displayName: 'Build Application'
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - task: NodeTool@0
            inputs:
              versionSpec: '$(nodeVersion)'
            displayName: 'Node.js installieren'

          - script: bash build.sh $(Build.BuildNumber)
            displayName: 'Build ausführen'

          # Pipeline Artifact publizieren (empfohlene Methode)
          - publish: $(System.DefaultWorkingDirectory)/dist
            artifact: app-dist
            displayName: 'App-Artefakte publizieren'

          # Build-Manifest separat publizieren
          - publish: $(System.DefaultWorkingDirectory)/dist/build-manifest.json
            artifact: build-metadata
            displayName: 'Build-Metadata publizieren'

  # ===== Test Stage =====
  - stage: Test
    displayName: 'Test'
    dependsOn: Build
    jobs:
      - job: RunTests
        displayName: 'Tests ausführen'
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - task: NodeTool@0
            inputs:
              versionSpec: '$(nodeVersion)'
            displayName: 'Node.js installieren'

          - script: npm test
            displayName: 'Unit Tests'

          # Test-Report generieren
          - script: bash test/generate-report.sh
            displayName: 'Test-Report generieren'

          # Test-Ergebnisse publizieren (JUnit-Format)
          - task: PublishTestResults@2
            inputs:
              testResultsFormat: 'JUnit'
              testResultsFiles: 'test-results/test-report.xml'
              testRunTitle: 'Unit Tests'
            displayName: 'Test-Ergebnisse publizieren'

          # Test-Report als Artefakt
          - publish: $(System.DefaultWorkingDirectory)/test-results
            artifact: test-reports
            displayName: 'Test-Reports publizieren'

  # ===== Verify Stage =====
  - stage: Verify
    displayName: 'Verify Artifacts'
    dependsOn:
      - Build
      - Test
    jobs:
      - job: VerifyArtifacts
        displayName: 'Artefakte verifizieren'
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          # Artefakte herunterladen
          - download: current
            artifact: app-dist
            displayName: 'App-Artefakte herunterladen'

          - download: current
            artifact: build-metadata
            displayName: 'Build-Metadata herunterladen'

          - download: current
            artifact: test-reports
            displayName: 'Test-Reports herunterladen'

          - script: |
              echo "=== Heruntergeladene Artefakte ==="
              echo ""
              echo "--- App Distribution ---"
              ls -la $(Pipeline.Workspace)/app-dist/
              echo ""
              echo "--- Build Metadata ---"
              cat $(Pipeline.Workspace)/build-metadata/build-manifest.json
              echo ""
              echo "--- Test Reports ---"
              ls -la $(Pipeline.Workspace)/test-reports/
              echo ""
              echo "=== Validierung ==="
              # Prüfe, ob alle erwarteten Dateien vorhanden sind
              for file in app.js app-dist/index.html; do
                base=$(basename $file)
                if [ -f "$(Pipeline.Workspace)/app-dist/$base" ]; then
                  echo "OK: $base gefunden"
                else
                  echo "FEHLER: $base fehlt!"
                  exit 1
                fi
              done
              echo ""
              echo "Alle Artefakte erfolgreich verifiziert!"
            displayName: 'Artefakte prüfen und validieren'
```

Gehe die Pipeline Abschnitt für Abschnitt durch:

- **Build-Stage**: Ruft das Build-Skript auf und übergibt
  `$(Build.BuildNumber)` als Argument. Anschließend werden zwei separate
  Artefakte publiziert: `app-dist` enthält die komplette Distribution (alle
  Dateien im `dist/`-Verzeichnis), `build-metadata` enthält nur das
  Build-Manifest. Die Trennung erlaubt es, in späteren Stages gezielt nur die
  Metadaten herunterzuladen, ohne die gesamte Distribution zu übertragen.
- **Test-Stage**: Führt die Unit Tests aus und generiert anschließend den
  JUnit-XML-Report. Der `PublishTestResults@2`-Task übergibt diesen Report an
  Azure DevOps, wo er im **Tests**-Tab des Pipeline-Runs erscheint. Zusätzlich
  wird der Report als Artefakt `test-reports` publiziert, damit er auch
  außerhalb von Azure DevOps verfügbar ist (z. B. für externe Reporting-Tools).
- **Verify-Stage**: Hängt von **beiden** vorherigen Stages ab
  (`dependsOn: [Build, Test]`) und lädt alle drei Artefakte herunter. Die
  heruntergeladenen Dateien landen unter
  `$(Pipeline.Workspace)/<artefakt-name>/`. Ein Validierungsskript prüft, ob
  alle erwarteten Dateien vorhanden sind, und bricht mit Exit-Code 1 ab, falls
  etwas fehlt. In der Praxis könnte diese Stage auch Checksummen prüfen oder
  Artefakte signieren.

### Schritt 4: Committen und Pipeline starten

```bash
git add build.sh test/generate-report.sh azure-pipelines.yml
git commit -m "Add artifact publishing and verification"
git push origin master
```

### Schritt 5: Artefakte im Browser ansehen

1. Öffne den Pipeline-Run im Browser.
2. Klicke auf **"Summary"** (oder "Zusammenfassung").
3. Im Bereich **"Related"** siehst du die publizierten Artefakte:
    - `app-dist` (3 Dateien: `app.js`, `index.html`, `build-manifest.json`)
    - `build-metadata` (1 Datei: `build-manifest.json`)
    - `test-reports` (1 Datei: `test-report.xml`)
4. Klicke auf ein Artefakt, um es herunterzuladen oder die Dateien zu
   durchsuchen. Azure DevOps zeigt eine Datei-Übersicht mit Größe und Pfad.
5. Wechsle zum Tab **"Tests"**: Hier siehst du die vom
   `PublishTestResults@2`-Task publizierten Ergebnisse - drei bestandene Tests
   mit Laufzeiten. Bei mehreren Builds zeigt Azure DevOps hier auch Trends an
   (z. B. ob die Testanzahl wächst oder Tests instabil sind).

## Aufräumen

Kein Aufräumen nötig - Artefakte werden automatisch nach der konfigurierten
Aufbewahrungsdauer (Standard: 30 Tage) gelöscht. Die Aufbewahrungsdauer kann
unter **Project Settings > Settings > Retention policy** angepasst werden.
