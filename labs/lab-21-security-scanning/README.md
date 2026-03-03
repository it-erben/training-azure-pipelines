# Lab 21: Security Scanning (SAST, Dependency Checks)

## Hintergrund

Traditionell wird Security erst am Ende des Entwicklungsprozesses geprüft -
kurz vor dem Release führt ein Security-Team einen Penetrationstest durch.
Das Ergebnis: teure Nacharbeit, verzögerte Releases und frustrierte
Entwickler. **Shift Left Security** dreht diesen Ansatz um: Security-Prüfungen
werden so früh wie möglich in den Entwicklungsprozess integriert - idealerweise
in jede Pipeline und jeden Pull Request.

Die wichtigsten Scanning-Typen in CI/CD-Pipelines:

- **SAST (Static Application Security Testing)**: Analysiert den **Quellcode**
  auf Sicherheitslücken, ohne die Anwendung auszuführen. Findet Muster wie
  SQL Injection, Cross-Site Scripting (XSS), Command Injection und unsichere
  Kryptografie. Tools: SonarQube, Checkmarx, Semgrep.
- **Dependency Scanning**: Prüft **Abhängigkeiten** (npm-Pakete,
  Python-Bibliotheken, NuGet-Packages) auf bekannte Schwachstellen (CVEs).
  Viele Sicherheitslücken stammen nicht aus eigenem Code, sondern aus
  transitiven Abhängigkeiten. Tools: npm audit, Snyk, OWASP Dependency-Check.
- **Secret Scanning**: Erkennt versehentlich eingecheckte **Credentials** wie
  API-Keys, Passwörter, Private Keys oder Connection Strings. Ein einziger
  eingecheckter AWS-Key kann innerhalb von Minuten von Bots entdeckt und
  missbraucht werden. Tools: GitLeaks, TruffleHog, GitHub Secret Scanning.
- **Container Scanning**: Prüft **Docker-Images** auf Schwachstellen in
  Basis-Images und installierten Paketen. Tools: Trivy, Aqua Security.

In diesem Lab implementieren wir die ersten drei Typen als parallele Jobs
in einer Pipeline. Wir verwenden bewusst einfache Bash-basierte Scanner
(statt Enterprise-Tools wie SonarQube), um die **Konzepte** zu demonstrieren.
In der Praxis würdest du professionelle Tools einsetzen, die weniger False
Positives produzieren und bessere Reporting-Funktionen bieten.

### Security als Quality Gate

Ein entscheidender Aspekt ist die Frage: **Soll ein Security-Finding den
Build blockieren?** Die Antwort hängt vom Schweregrad ab:

| Schweregrad    | Aktion                                     |
|:---------------|:-------------------------------------------|
| **Critical**   | Build blockieren (`exit 1`)                |
| **High**       | Build blockieren oder Warnung + Ticket     |
| **Medium**     | Warnung im Build-Log, Ticket erstellen     |
| **Low**        | Informativ, keine Aktion                   |

In diesem Lab verwenden wir `continueOnError: true`, damit die Pipeline
trotz Findings weiterläuft. In der Praxis konfigurierst du das abhängig vom
Schweregrad.

## Aufgabenstellung

### Schritt 1: Absichtlich verwundbaren Code erstellen

Damit die Security-Scanner etwas finden, erstellen wir eine Datei mit
typischen Sicherheitslücken. **Dieser Code dient ausschließlich der
Demonstration** - in einem echten Projekt gehören solche Muster natürlich
nicht in den Code.

Erstelle die Datei **src/vulnerable-demo.js** - eine Sammlung der häufigsten
Sicherheitslücken aus den OWASP Top 10:

```javascript
// WARNUNG: Dieser Code enthält absichtliche Sicherheitslücken!
// NUR für Demonstrationszwecke im Security-Scanning-Lab.

const http = require('http');
const url = require('url');
const { execSync } = require('child_process');

// Problem 1: Hardcoded Credentials
const DB_PASSWORD = "SuperSecret123!";
const API_KEY = "sk-1234567890abcdef";

// Problem 2: Command Injection
function runCommand(userInput) {
  // UNSICHER: Benutzereingabe wird direkt ausgeführt
  return execSync('echo ' + userInput).toString();
}

// Problem 3: SQL Injection (simuliert)
function getUser(userId) {
  // UNSICHER: String-Konkatenation statt parametrisierte Query
  const query = "SELECT * FROM users WHERE id = '" + userId + "'";
  console.log("Query:", query);
  return query;
}

// Problem 4: XSS (Cross-Site Scripting)
function renderPage(userInput) {
  // UNSICHER: Benutzereingabe wird nicht escaped
  return `<html><body><h1>Willkommen, ${userInput}</h1></body></html>`;
}

// Problem 5: Path Traversal
function readFile(filename) {
  const fs = require('fs');
  // UNSICHER: Pfad wird nicht validiert
  return fs.readFileSync('/data/' + filename, 'utf8');
}

module.exports = { runCommand, getUser, renderPage, readFile };
```

Gehe die fünf Sicherheitslücken durch:

- **Hardcoded Credentials** (Problem 1): Passwörter und API-Keys stehen
  direkt im Quellcode. Jeder mit Zugriff auf das Repository kann sie lesen.
  In der Praxis gehören Credentials in Key Vault, Umgebungsvariablen oder
  Secret-Manager (vgl. Lab 05).
- **Command Injection** (Problem 2): Die Funktion `runCommand` fügt
  Benutzereingabe direkt in einen Shell-Befehl ein. Ein Angreifer könnte
  `"; rm -rf /"` eingeben und damit beliebige Befehle ausführen.
- **SQL Injection** (Problem 3): Die Funktion `getUser` baut die SQL-Query
  per String-Konkatenation. Ein Angreifer könnte `' OR '1'='1` eingeben und
  damit alle Benutzer abfragen.
- **XSS** (Problem 4): Die Funktion `renderPage` fügt Benutzereingabe
  unescaped in HTML ein. Ein Angreifer könnte
  `<script>alert('XSS')</script>` eingeben.
- **Path Traversal** (Problem 5): Die Funktion `readFile` validiert den
  Dateipfad nicht. Ein Angreifer könnte `../../../etc/passwd` eingeben und
  damit beliebige Dateien lesen.

Ersetze außerdem den Inhalt von **package.json** - mit einer absichtlich
verwundbaren Abhängigkeit (`lodash 4.17.20` hat bekannte CVEs):

```json
{
  "name": "hello-pipeline",
  "version": "1.0.0",
  "description": "Demo-App für Security Scanning",
  "main": "src/server.js",
  "scripts": {
    "start": "node src/server.js",
    "test": "node test/test.js",
    "build": "echo 'Build complete'",
    "audit": "npm audit --json",
    "audit:fix": "npm audit fix"
  },
  "dependencies": {
    "express": "^4.18.2",
    "lodash": "4.17.20"
  },
  "devDependencies": {
    "jest": "^29.7.0"
  }
}
```

Die Version `lodash@4.17.20` ist bewusst gewählt: Sie enthält eine bekannte
Prototype Pollution-Schwachstelle (CVE-2021-23337), die `npm audit` finden
wird. Die aktuelle Version `4.17.21` behebt diese Schwachstelle.

### Schritt 2: Pipeline mit Security Scanning

Jetzt erstellen wir eine Pipeline mit drei parallelen Security-Scans.
Die Scans laufen parallel, um Zeit zu sparen - jeder prüft einen 
anderen Aspekt der Sicherheit.

Ersetze den Inhalt von `azure-pipelines.yml`:

```yaml
trigger:
  branches:
    include:
      - master

variables:
  nodeVersion: '20.x'

stages:
  # ===== Stage 1: Security Scans =====
  - stage: SecurityScan
    displayName: 'Security Scanning'
    jobs:

      # --- Job 1: Dependency Check ---
      - job: DependencyCheck
        displayName: 'Dependency Scanning'
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - task: NodeTool@0
            inputs:
              versionSpec: '$(nodeVersion)'
            displayName: 'Node.js installieren'

          - script: npm install
            displayName: 'Abhängigkeiten installieren'

          # npm audit
          - script: |
              echo "=== npm audit ==="
              echo "Prüfe Abhängigkeiten auf bekannte Schwachstellen..."
              echo ""
              npm audit --audit-level=moderate 2>&1 || true
              echo ""
              echo "=== Zusammenfassung ==="
              npm audit --json 2>/dev/null | python3 -c "
              import json, sys
              try:
                data = json.load(sys.stdin)
                vuln = data.get('metadata', {}).get('vulnerabilities', {})
                total = sum(vuln.values()) if isinstance(vuln, dict) else 0
                print(f'Gefundene Schwachstellen:')
                if isinstance(vuln, dict):
                  for severity, count in vuln.items():
                    if count > 0:
                      print(f'  {severity}: {count}')
                print(f'Gesamt: {total}')
              except:
                print('Audit-Ergebnis konnte nicht geparst werden.')
              " || true
            displayName: 'npm Audit'
            continueOnError: true

      # --- Job 2: Secret Scanning ---
      - job: SecretScan
        displayName: 'Secret Scanning'
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - script: |
              echo "=== Secret Scanning ==="
              echo "Suche nach versehentlich eingecheckten Credentials..."
              echo ""

              FOUND=0

              # Pattern für häufige Secrets
              PATTERNS=(
                'password\s*=\s*["\x27][^"\x27]+'
                'api[_-]?key\s*=\s*["\x27][^"\x27]+'
                'secret\s*=\s*["\x27][^"\x27]+'
                'token\s*=\s*["\x27][^"\x27]+'
                'sk-[a-zA-Z0-9]{20,}'
                'AKIA[0-9A-Z]{16}'
              )

              for pattern in "${PATTERNS[@]}"; do
                MATCHES=$(grep -rn -i -E "$pattern" src/ --include="*.js" --include="*.ts" --include="*.json" 2>/dev/null || true)
                if [ -n "$MATCHES" ]; then
                  echo "WARNUNG: Mögliches Secret gefunden:"
                  echo "$MATCHES" | head -5
                  echo ""
                  FOUND=1
                fi
              done

              if [ "$FOUND" -eq 1 ]; then
                echo "==============================="
                echo "  SECRETS GEFUNDEN!"
                echo "==============================="
                echo "Bitte entferne alle hardcoded Secrets"
                echo "und verwende stattdessen:"
                echo "  - Azure Key Vault"
                echo "  - Pipeline-Variablen (secret)"
                echo "  - .env Dateien (in .gitignore)"
                # In einer realen Pipeline: exit 1
              else
                echo "Keine Secrets gefunden."
              fi
            displayName: 'Secret Scan'
            continueOnError: true

      # --- Job 3: SAST (Static Analysis) ---
      - job: SASTScan
        displayName: 'SAST Scanning'
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - script: |
              echo "=== SAST: Static Application Security Testing ==="
              echo "Analysiere Quellcode auf Sicherheitslücken..."
              echo ""

              ISSUES=0

              echo "--- Check 1: Command Injection ---"
              if grep -rn "execSync\|exec\|spawn" src/ --include="*.js" | grep -v "node_modules" | grep -v "//.*safe"; then
                echo "WARNUNG: Mögliche Command Injection gefunden!"
                echo "Empfehlung: Validiere alle Benutzereingaben und verwende"
                echo "parameterisierte Befehle."
                echo ""
                ISSUES=$((ISSUES + 1))
              fi

              echo "--- Check 2: SQL Injection ---"
              if grep -rn "SELECT.*+\|INSERT.*+\|UPDATE.*+\|DELETE.*+" src/ --include="*.js" | grep -v "node_modules"; then
                echo "WARNUNG: Mögliche SQL Injection gefunden!"
                echo "Empfehlung: Verwende parameterisierte Queries."
                echo ""
                ISSUES=$((ISSUES + 1))
              fi

              echo "--- Check 3: XSS (Cross-Site Scripting) ---"
              if grep -rn 'innerHTML\|document.write\|`.*\${.*}`.*html' src/ --include="*.js" | grep -v "node_modules"; then
                echo "WARNUNG: Mögliche XSS-Schwachstelle gefunden!"
                echo "Empfehlung: Escape alle Benutzereingaben vor der Ausgabe."
                echo ""
                ISSUES=$((ISSUES + 1))
              fi

              echo "--- Check 4: Path Traversal ---"
              if grep -rn "readFileSync\|readFile" src/ --include="*.js" | grep "+\|concat\|\`" | grep -v "node_modules"; then
                echo "WARNUNG: Mögliche Path Traversal gefunden!"
                echo "Empfehlung: Validiere und normalisiere Dateipfade."
                echo ""
                ISSUES=$((ISSUES + 1))
              fi

              echo ""
              echo "==============================="
              echo "  SAST-Ergebnis"
              echo "==============================="
              echo "  Gefundene Probleme: $ISSUES"
              if [ "$ISSUES" -gt 0 ]; then
                echo "  STATUS: Sicherheitsprobleme gefunden!"
                echo ""
                echo "  Nächste Schritte:"
                echo "  1. Probleme priorisieren (kritisch/hoch/mittel/niedrig)"
                echo "  2. Tickets erstellen"
                echo "  3. Fixes implementieren und erneut scannen"
              else
                echo "  STATUS: Keine Probleme gefunden"
              fi
            displayName: 'SAST Analyse'
            continueOnError: true

  # ===== Stage 3: Build =====
  - stage: Build
    displayName: 'Build'
    dependsOn: SecurityScan
    # In der Praxis: condition: succeeded()
    # Für das Lab: immer bauen, auch wenn Scans Fehler finden
    condition: always()
    jobs:
      - job: BuildApp
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - task: NodeTool@0
            inputs:
              versionSpec: '$(nodeVersion)'
          - script: npm install && npm run build
            displayName: 'Build'
```

Gehe die Pipeline Abschnitt für Abschnitt durch:

- **SecurityScan-Stage mit drei parallelen Jobs**: Die drei Scan-Jobs
  (`DependencyCheck`, `SecretScan`, `SASTScan`) laufen parallel, da sie keine
  `dependsOn`-Beziehung zueinander haben. Jeder Job prüft einen anderen
  Sicherheitsaspekt unabhängig voneinander. Alle Jobs haben
  `continueOnError: true`, damit die Pipeline trotz Findings weiterläuft.
- **Dependency Scanning**: Führt `npm audit` aus, das die installierten
  Pakete gegen die npm Advisory Database prüft. Die JSON-Ausgabe wird per
  Python-Script geparst, um eine übersichtliche Zusammenfassung nach
  Schweregrad zu erstellen. `--audit-level=moderate` filtert Low-Severity-
  Findings heraus.
- **Secret Scanning**: Durchsucht den `src/`-Ordner mit regulären Ausdrücken
  nach typischen Secret-Mustern: Passwort-Zuweisungen, API-Key-Muster,
  AWS-Access-Keys (`AKIA...`), OpenAI-Keys (`sk-...`). In der Praxis
  verwendet man spezialisierte Tools wie GitLeaks, die deutlich mehr Muster
  erkennen und weniger False Positives produzieren.
- **SAST Scanning**: Prüft den Quellcode auf vier häufige Schwachstellen-
  Muster aus den OWASP Top 10. Die grep-basierte Analyse ist bewusst
  einfach gehalten - professionelle SAST-Tools analysieren den Abstract
  Syntax Tree (AST) und erkennen Schwachstellen kontextbezogen.

### Schritt 3: Committen und Pipeline starten

```bash
git add src/vulnerable-demo.js package.json azure-pipelines.yml
git commit -m "Add security scanning pipeline"
git push
```

### Schritt 4: Security-Findings analysieren

Öffne den Pipeline-Run im Browser und prüfe die drei parallelen
Security-Jobs:

1. **Dependency Scanning**: Zeigt die `npm audit`-Ergebnisse. Du solltest
   mindestens eine Schwachstelle für `lodash@4.17.20` sehen (Prototype
   Pollution, Severity: High).
2. **Secret Scanning**: Findet die hardcoded Credentials in
   `vulnerable-demo.js` - das Datenbankpasswort und den API-Key.
3. **SAST Scanning**: Findet bis zu vier Schwachstellen: Command Injection,
   SQL Injection, XSS und Path Traversal.
