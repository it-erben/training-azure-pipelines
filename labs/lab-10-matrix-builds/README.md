# Lab 10: Matrix-Builds für mehrere Plattformen/Versionen

## Hintergrund

Wenn eine Anwendung auf mehreren Plattformen (Windows, Linux, macOS) oder mit
verschiedenen Runtime-Versionen (Node 18, 20, 22) laufen soll, müsste man ohne
Matrix-Builds für jede Kombination einen eigenen Job schreiben. Bei 2
Betriebssystemen und 3 Node-Versionen wären das 6 nahezu identische
Job-Definitionen - mit dem einzigen Unterschied in `vmImage` und
`versionSpec`. Das ist fehleranfällig und schwer wartbar.

Die **Matrix-Strategie** löst dieses Problem: Du definierst eine Tabelle aus
Variablen-Kombinationen, und Azure Pipelines generiert daraus automatisch einen
Job pro Kombination. Jeder generierte Job erhält die Variablen seiner
Kombination als Pipeline-Variablen, die in `pool`, `steps` und überall sonst
verwendet werden können.

Die Matrix wird unter `strategy.matrix` definiert. Jeder Eintrag ist ein
benanntes Set von Variablen:

```yaml
strategy:
  matrix:
    Linux_Node20:
      vmImage: 'ubuntu-latest'
      nodeVersion: '20.x'
    Windows_Node20:
      vmImage: 'windows-latest'
      nodeVersion: '20.x'
```

Aus dieser Definition erzeugt Azure Pipelines zwei Jobs: `Test Linux_Node20`
und `Test Windows_Node20`. Der Job-Name setzt sich aus dem `displayName` des
Jobs und dem Matrix-Eintragsnamen zusammen.

Mit `maxParallel` kannst du begrenzen, wie viele Matrix-Jobs gleichzeitig
laufen. Das ist nützlich, wenn du nur eine begrenzte Anzahl paralleler Agents
hast (in der kostenlosen Azure-DevOps-Stufe ist das 1 paralleler Job).

## Aufgabenstellung

### Schritt 1: Plattformübergreifendes Test-Skript erstellen

Für die Matrix-Tests erstellen wir ein Test-Skript, das plattformspezifische
Informationen ausgibt und Plattform-abhängiges Verhalten prüft. So können wir in
den Build-Logs jedes Matrix-Jobs sehen, auf welcher Plattform und mit welcher
Node-Version er tatsächlich gelaufen ist.

Erstelle die Datei **test/cross-platform-test.js**:

```javascript
const os = require('os');
const {greet, add} = require('../src/app');

console.log('=== Cross-Platform Test ===');
console.log(`Platform: ${os.platform()}`);
console.log(`Architecture: ${os.arch()}`);
console.log(`Node Version: ${process.version}`);
console.log(`OS Release: ${os.release()}`);
console.log('');

let passed = 0;
let failed = 0;

function test(name, fn) {
    try {
        fn();
        console.log(`  PASS: ${name}`);
        passed++;
    } catch (e) {
        console.log(`  FAIL: ${name} - ${e.message}`);
        failed++;
    }
}

function assertEqual(actual, expected) {
    if (actual !== expected) {
        throw new Error(`Expected "${expected}", got "${actual}"`);
    }
}

test('greet function works', () => {
    assertEqual(greet('Test'), 'Hello, Test! Welcome to Azure Pipelines.');
});

test('add function works', () => {
    assertEqual(add(10, 20), 30);
});

test('platform-specific path separator', () => {
    const sep = require('path').sep;
    if (os.platform() === 'win32') {
        assertEqual(sep, '\\');
    } else {
        assertEqual(sep, '/');
    }
});

test('environment variable access', () => {
    // Diese Variable wird in der Pipeline gesetzt
    const testEnv = process.env.TEST_ENV || 'not-set';
    console.log(`    TEST_ENV = ${testEnv}`);
    // Kein assertEqual -- nur prüfen, dass Zugriff funktioniert
});

console.log(`\nResults: ${passed} passed, ${failed} failed`);
console.log(`Platform: ${os.platform()} | Node: ${process.version}`);
if (failed > 0) process.exit(1);
```

Das Skript importiert die Funktionen `greet` und `add` aus `src/app.js` (aus Lab
06) und führt vier Tests aus:

- **greet und add**: Prüft die Grundfunktionalität - diese Tests sollten auf
  allen Plattformen identisch funktionieren.
- **platform-specific path separator**: Prüft, ob der Pfad-Separator dem
  erwarteten Wert entspricht (`/` auf Linux/macOS, `\` auf Windows). Das ist ein
  typisches Beispiel für plattformspezifisches Verhalten, das man in einer
  Matrix testen würde.
- **environment variable access**: Liest eine Umgebungsvariable, die von der
  Pipeline gesetzt wird. So lässt sich prüfen, ob die Matrix-Variablen korrekt
  an das Skript übergeben werden.

### Schritt 2: Pipeline mit Matrix-Strategie

Jetzt erstellen wir eine Pipeline mit zwei Matrix-Stages: eine, die über
Betriebssysteme **und** Node-Versionen variiert (2×2 = 4 Jobs), und eine
einfachere, die nur über Python-Versionen variiert (3 Jobs). So siehst du
verschiedene Muster für den Einsatz von Matrix-Strategien.

Ersetze den Inhalt von `azure-pipelines.yml`:

```yaml
trigger:
  branches:
    include:
      - main

# ===== Variante 1: Matrix mit OS und Node-Versionen =====
stages:
  - stage: MatrixTest
    displayName: 'Matrix: OS x Node Versionen'
    jobs:
      - job: TestMatrix
        displayName: 'Test'
        strategy:
          matrix:
            Linux_Node18:
              vmImage: 'ubuntu-latest'
              nodeVersion: '18.x'
              osName: 'Linux'
            Linux_Node20:
              vmImage: 'ubuntu-latest'
              nodeVersion: '20.x'
              osName: 'Linux'
            Windows_Node18:
              vmImage: 'windows-latest'
              nodeVersion: '18.x'
              osName: 'Windows'
            Windows_Node20:
              vmImage: 'windows-latest'
              nodeVersion: '20.x'
              osName: 'Windows'
          maxParallel: 4  # Alle gleichzeitig ausführen

        pool:
          vmImage: $(vmImage)

        steps:
          - task: NodeTool@0
            inputs:
              versionSpec: '$(nodeVersion)'
            displayName: 'Node.js $(nodeVersion) installieren'

          - script: |
              echo "=== Matrix-Konfiguration ==="
              echo "OS:           $(osName)"
              echo "Node Version: $(nodeVersion)"
              echo "VM Image:     $(vmImage)"
              echo "Agent:        $(Agent.Name)"
              echo "Agent OS:     $(Agent.OS)"
              node --version
            displayName: 'Konfiguration anzeigen'

          - script: node test/cross-platform-test.js
            displayName: 'Cross-Platform Tests'
            env:
              TEST_ENV: 'matrix-$(osName)-$(nodeVersion)'

  # ===== Variante 2: Einfache Versions-Matrix =====
  - stage: SimpleMatrix
    displayName: 'Einfache Versions-Matrix'
    dependsOn: MatrixTest
    jobs:
      - job: VersionCheck
        displayName: 'Version'
        strategy:
          matrix:
            Python39:
              pythonVersion: '3.9'
            Python310:
              pythonVersion: '3.10'
            Python312:
              pythonVersion: '3.12'
          maxParallel: 3

        pool:
          vmImage: 'ubuntu-latest'

        steps:
          - task: UsePythonVersion@0
            inputs:
              versionSpec: '$(pythonVersion)'
            displayName: 'Python $(pythonVersion) installieren'

          - script: |
              echo "Python Version: $(python3 --version)"
              echo "pip Version: $(pip --version)"
              python3 -c "import sys; print(f'Python {sys.version} auf {sys.platform}')"
            displayName: 'Python-Version prüfen'

  # ===== Zusammenfassung =====
  - stage: Summary
    displayName: 'Zusammenfassung'
    dependsOn:
      - MatrixTest
      - SimpleMatrix
    jobs:
      - job: ShowSummary
        displayName: 'Matrix-Ergebnis'
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - script: |
              echo "=== Matrix-Build Zusammenfassung ==="
              echo ""
              echo "Stage 1: OS x Node.js Matrix"
              echo "  - Linux + Node 18"
              echo "  - Linux + Node 20"
              echo "  - Windows + Node 18"
              echo "  - Windows + Node 20"
              echo "  -> 4 parallele Jobs"
              echo ""
              echo "Stage 2: Python Versions-Matrix"
              echo "  - Python 3.9"
              echo "  - Python 3.10"
              echo "  - Python 3.12"
              echo "  -> 3 parallele Jobs"
              echo ""
              echo "Gesamt: 7 Matrix-Jobs + 1 Summary = 8 Jobs"
              echo ""
              echo "Alle Matrix-Kombinationen erfolgreich getestet!"
            displayName: 'Zusammenfassung anzeigen'
```

Gehe die Pipeline Abschnitt für Abschnitt durch:

- **MatrixTest-Stage**: Definiert eine 2×2-Matrix aus Betriebssystemen (Linux,
  Windows) und Node-Versionen (18, 20). Jeder Matrix-Eintrag (z. B.
  `Linux_Node18`) setzt drei Variablen: `vmImage` für den Agent-Pool,
  `nodeVersion` für die Node.js-Installation und `osName` als lesbare
  Bezeichnung. Beachte, dass `pool.vmImage` die Matrix-Variable `$(vmImage)`
  verwendet - so läuft jeder Job auf dem passenden Betriebssystem. Der
  `env`-Block am `script`-Step übergibt eine Umgebungsvariable an das
  Test-Skript, die die aktuelle Matrix-Kombination enthält.
- **SimpleMatrix-Stage**: Zeigt eine einfachere Matrix, die nur über eine
  Dimension variiert: drei Python-Versionen auf demselben Betriebssystem
  (Linux). Der `UsePythonVersion@0`-Task installiert die angegebene
  Python-Version auf dem Agent. Dieses Muster ist typisch für Bibliotheken, die
  Kompatibilität mit mehreren Runtime-Versionen garantieren müssen.
- **Summary-Stage**: Hängt von beiden Matrix-Stages ab und gibt eine
  Zusammenfassung aus. Sie dient vor allem dazu, die Gesamtstruktur der Pipeline
  zu demonstrieren: 7 Matrix-Jobs + 1 Summary-Job = 8 Jobs insgesamt.
- **`maxParallel: 4`**: Erlaubt, dass alle 4 Matrix-Jobs gleichzeitig laufen.
  Wenn du diesen Wert auf 2 setzt, werden nur 2 Jobs gleichzeitig ausgeführt,
  und die anderen 2 warten. Bei der kostenlosen Azure-DevOps-Stufe (1 paralleler
  Job) laufen die Jobs ohnehin nacheinander - `maxParallel` hat dann keine
  praktische Auswirkung.

### Schritt 3: Committen und beobachten

```bash
git add test/cross-platform-test.js azure-pipelines.yml
git commit -m "Add matrix build strategy"
git push origin main
```

### Schritt 4: Matrix-Visualisierung im Browser

Azure DevOps zeigt Matrix-Jobs in einer übersichtlichen Darstellung an, in der
du sofort siehst, welche Kombinationen erfolgreich waren und welche nicht.

1. Öffne den Pipeline-Run im Browser.
2. In der Stage **"Matrix: OS x Node Versionen"** siehst du **4 parallele Jobs**
   nebeneinander:
    - Test Linux_Node18
    - Test Linux_Node20
    - Test Windows_Node18
    - Test Windows_Node20
3. Klicke auf einen einzelnen Job, um das Log zu sehen. Im Step
   "Konfiguration anzeigen" findest du die konkreten Werte der Matrix-Variablen.
   Vergleiche die Ausgabe zwischen einem Linux- und einem Windows-Job - du
   siehst unterschiedliche Werte für `Agent.OS` und
   `Agent.Name`.
4. Im Step "Cross-Platform Tests" siehst du den plattformspezifischen Test:
   Auf Linux wird `/` als Pfad-Separator erwartet, auf Windows `\`.
5. In der Stage **"Einfache Versions-Matrix"** siehst du 3 Jobs mit
   verschiedenen Python-Versionen. Prüfe im Log, dass jeder Job die korrekte
   Version verwendet.

## Validierung

Prüfe per CLI, dass der Build erfolgreich war:

```bash
# Build-Status prüfen
az pipelines runs list --top 1 --output table
```

Öffne im Browser das Build-Log und prüfe die folgenden Punkte:

- Alle 7 Matrix-Jobs (4 + 3) und der Summary-Job sind grün.
- Im Log jedes Matrix-Jobs stimmen die angezeigten Variablen (OS, Node-Version
  bzw. Python-Version) mit dem Job-Namen überein.
- Die Cross-Platform-Tests bestehen auf allen Plattformen.

## Erwartetes Ergebnis

Die Pipeline-Visualisierung zeigt:

```
MatrixTest Stage:
  +-- Test Linux_Node18    [grün]
  +-- Test Linux_Node20    [grün]
  +-- Test Windows_Node18  [grün]
  +-- Test Windows_Node20  [grün]

SimpleMatrix Stage:
  +-- Version Python39     [grün]
  +-- Version Python310    [grün]
  +-- Version Python312    [grün]

Summary Stage:
  +-- Matrix-Ergebnis      [grün]
```

Im Log von "Test Linux_Node20":

```
=== Matrix-Konfiguration ===
OS:           Linux
Node Version: 20.x
VM Image:     ubuntu-latest
```

Im Log von "Test Windows_Node18":

```
=== Matrix-Konfiguration ===
OS:           Windows
Node Version: 18.x
VM Image:     windows-latest
```

## Aufräumen

Kein Aufräumen nötig. Die Matrix-Pipeline erzeugt keine externen Ressourcen.

## Tipps und Troubleshooting

- **`maxParallel`**: Begrenzt die Anzahl gleichzeitig laufender Matrix-Jobs.
  Setze diesen Wert auf die Anzahl deiner verfügbaren parallelen Agents, um
  Wartezeiten zu minimieren, ohne die Agent-Kapazität zu überlasten.
- **Matrix-Kombinationen**: Die Gesamtanzahl Jobs entspricht der Anzahl der
  Matrix-Einträge. Bei einer vollständigen 3×3-Matrix (z. B. 3 OS × 3 Versionen)
  wären das 9 Jobs. Halte die Matrix überschaubar - in der Praxis testest du
  selten alle Kombinationen, sondern wählst die wichtigsten aus.
- **Windows vs. Linux in Skripten**: Beachte, dass auf Windows `\` als
  Pfadtrenner verwendet wird. Der `script`-Step verwendet auf Windows
  automatisch `cmd.exe` statt Bash. Wenn du Bash-Skripte auf allen Plattformen
  verwenden willst, nutze `bash`-Steps statt `script`-Steps. Alternativ kannst
  du `task: CmdLine@2` für Windows und `task: Bash@3` für Linux verwenden.
- **macOS-Agents**: `macos-latest` ist ebenfalls als VM-Image verfügbar,
  verbraucht aber 10× so viele Pipeline-Minuten wie Linux. Verwende es nur, wenn
  du tatsächlich macOS-spezifisches Verhalten testen musst (z. B. iOS-Builds
  oder macOS-native Anwendungen).
- **Fehlgeschlagener Matrix-Job**: Wenn ein einzelner Matrix-Job fehlschlägt,
  werden die anderen Jobs trotzdem ausgeführt - die Stage gilt aber insgesamt
  als fehlgeschlagen. Wenn du willst, dass die restlichen Jobs bei einem Fehler
  abgebrochen werden, setze `cancelTimeoutInMinutes: 0` auf der Strategy.
- **Dynamische Matrix**: Für komplexere Szenarien kannst du die
  Matrix-Definition mit Template-Ausdrücken oder aus einer Variable generieren.
  Beispiel: Eine Template-Datei definiert die Matrix, und mehrere Pipelines
  binden sie per `extends` ein.
- **`exclude`-Filter**: Du kannst einzelne Kombinationen aus einer Matrix
  ausschließen, indem du sie nicht auflistest. Azure Pipelines bietet kein
  natives `exclude`-Keyword für die Matrix - du musst die gewünschten
  Kombinationen explizit auflisten.
