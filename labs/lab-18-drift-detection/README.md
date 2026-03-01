# Lab 18: Infrastructure Drift Detection

## Hintergrund

**Infrastructure Drift** entsteht, wenn der tatsächliche Zustand der
Infrastruktur vom definierten Zustand (IaC-Code) abweicht. Im Idealfall ist
der IaC-Code die einzige "Source of Truth" — alle Änderungen an der
Infrastruktur werden über Code und Pipelines durchgeführt. In der Praxis
passiert es jedoch häufig, dass jemand eine Einstellung direkt im Azure Portal
ändert, ein Skript eine Ressource modifiziert oder Azure selbst automatische
Updates durchführt.

Typische Ursachen für Drift:

- **Manuelle Änderungen im Portal**: Ein Entwickler ändert schnell eine SKU
  oder einen Tag, ohne den IaC-Code anzupassen. Beim nächsten `terraform apply`
  oder Bicep-Deployment wird die manuelle Änderung überschrieben.
- **Änderungen durch andere Pipelines oder Skripte**: Verschiedene Teams
  arbeiten an derselben Infrastruktur, aber nicht alle Änderungen fließen in
  den IaC-Code zurück.
- **Automatische Updates durch Azure**: Manche Azure-Dienste aktualisieren
  intern Konfigurationswerte (z. B. TLS-Versionen, Runtime-Patches), die
  dann vom definierten Zustand abweichen.
- **Unvollständiger IaC-Code**: Nicht alle Ressourcen sind im IaC-Code
  erfasst. Manuell erstellte Ressourcen in einer Resource Group sind
  "unsichtbar" für Terraform oder Bicep.

Drift ist gefährlich, weil er zu **unerwartetem Verhalten** führt: Der
IaC-Code beschreibt nicht mehr die Realität. Ein `terraform apply` könnte
unbeabsichtigt manuelle Änderungen rückgängig machen, oder ein Deployment
schlägt fehl, weil sich Vorbedingungen geändert haben. Je länger Drift
unentdeckt bleibt, desto schwieriger ist die Korrektur.

### Drift-Detection-Strategien

Es gibt mehrere Ansätze, Drift zu erkennen:

| Strategie                       | Werkzeug                       | Funktionsweise                                                |
|:--------------------------------|:-------------------------------|:--------------------------------------------------------------|
| **Terraform Plan**              | `terraform plan`               | Vergleicht State mit Realität. Exit Code 2 = Drift erkannt.   |
| **Bicep What-If**               | `az deployment group what-if`  | Zeigt Unterschiede zwischen Template und aktuellem Zustand.    |
| **Custom Scripts**              | Azure CLI + Shell              | Prüft gezielt einzelne Eigenschaften (SKU, Tags, Settings).   |
| **Azure Policy**                | Azure Policy                   | Verhindert Drift proaktiv durch Regeln (Deny/Audit).          |

In diesem Lab kombinieren wir alle drei reaktiven Ansätze in einer Pipeline,
die per Schedule täglich läuft. Azure Policy (der proaktive Ansatz) ist ein
eigenes Thema und wird hier nur erwähnt.

## Voraussetzungen

- Die Service Connection `azure-training-connection` aus Lab 05.
- Idealerweise existierende Bicep-Ressourcen aus Lab 17 (für den
  Bicep-What-If-Check). Das Lab funktioniert aber auch ohne — die
  entsprechende Stage zeigt dann "Keine Bicep-Dateien gefunden".

## Aufgabenstellung

### Schritt 1: Drift-Detection-Script erstellen

Wir erstellen ein Shell-Script, das gezielt einzelne Eigenschaften von
Azure-Ressourcen prüft und mit den erwarteten Werten vergleicht. Dieser Ansatz
ergänzt Terraform und Bicep: Er prüft Dinge, die nicht unbedingt im IaC-Code
stehen (z. B. ob unerwartete Ressourcen in einer Resource Group aufgetaucht
sind).

Erstelle das Verzeichnis und die Script-Datei:

**Bash:**
```bash
mkdir -p scripts
```

**PowerShell:**
```powershell
New-Item -ItemType Directory -Force -Path scripts | Out-Null
```

Erstelle die Datei **scripts/detect-drift.sh** — das Drift-Detection-Script.
Es prüft mehrere Aspekte der Infrastruktur und gibt am Ende eine
Zusammenfassung mit Ergebnis aus:

```bash
#!/bin/bash
set -e

echo "============================================"
echo "  Infrastructure Drift Detection"
echo "============================================"
echo ""

DRIFT_FOUND=0
CHECKS_PASSED=0
CHECKS_FAILED=0

# Funktion für Drift-Check
check_drift() {
  local resource_type="$1"
  local expected="$2"
  local actual="$3"
  local description="$4"

  if [ "$expected" = "$actual" ]; then
    echo "  OK: $description"
    echo "      Erwartet: $expected | Aktuell: $expected"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
  else
    echo "  DRIFT: $description"
    echo "      Erwartet: $expected | Aktuell: $actual"
    DRIFT_FOUND=1
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
  fi
}

# Prüfe Resource Group Tags
echo "=== Resource Group Tags ==="
RG_NAME="${1:-rg-pipeline-training}"
MANAGED_BY=$(az group show --name "$RG_NAME" --query "tags.ManagedBy" -o tsv 2>/dev/null || echo "NOT_FOUND")

if [ "$MANAGED_BY" = "NOT_FOUND" ]; then
  echo "  INFO: Kein ManagedBy-Tag gefunden (möglicherweise nicht per IaC erstellt)"
else
  check_drift "ResourceGroup" "bicep" "$MANAGED_BY" "ManagedBy-Tag der Resource Group"
fi

# Prüfe App Service Plan SKU
echo ""
echo "=== App Service Plan ==="
PLAN_NAME="${2:-plan-training-app-dev}"
if az appservice plan show --name "$PLAN_NAME" --resource-group "$RG_NAME" &>/dev/null; then
  ACTUAL_SKU=$(az appservice plan show --name "$PLAN_NAME" --resource-group "$RG_NAME" --query "sku.name" -o tsv)
  check_drift "AppServicePlan" "F1" "$ACTUAL_SKU" "SKU des App Service Plans"
else
  echo "  SKIP: App Service Plan '$PLAN_NAME' nicht gefunden"
fi

# Prüfe Web App Settings
echo ""
echo "=== Web App Settings ==="
APP_NAME="${3:-}"
if [ -n "$APP_NAME" ] && az webapp show --name "$APP_NAME" --resource-group "$RG_NAME" &>/dev/null; then
  ACTUAL_NODE=$(az webapp config show --name "$APP_NAME" --resource-group "$RG_NAME" --query "linuxFxVersion" -o tsv)
  check_drift "WebApp" "NODE|20-lts" "$ACTUAL_NODE" "Node.js-Version der Web App"

  HTTPS_ONLY=$(az webapp show --name "$APP_NAME" --resource-group "$RG_NAME" --query "httpsOnly" -o tsv)
  check_drift "WebApp" "true" "$HTTPS_ONLY" "HTTPS-Only Einstellung"
else
  echo "  SKIP: Web App nicht angegeben oder nicht gefunden"
fi

# Prüfe, ob unerwartete Ressourcen existieren
echo ""
echo "=== Unerwartete Ressourcen ==="
RESOURCE_COUNT=$(az resource list --resource-group "$RG_NAME" --query "length([?tags.ManagedBy==null])" -o tsv 2>/dev/null || echo "0")
if [ "$RESOURCE_COUNT" -gt 0 ]; then
  echo "  WARNUNG: $RESOURCE_COUNT Ressourcen ohne ManagedBy-Tag gefunden:"
  az resource list --resource-group "$RG_NAME" --query "[?tags.ManagedBy==null].{Name:name, Type:type}" -o table
  DRIFT_FOUND=1
  CHECKS_FAILED=$((CHECKS_FAILED + 1))
else
  echo "  OK: Keine unerwarteten Ressourcen"
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
fi

# Zusammenfassung
echo ""
echo "============================================"
echo "  Ergebnis"
echo "============================================"
echo "  Checks bestanden: $CHECKS_PASSED"
echo "  Checks fehlgeschlagen: $CHECKS_FAILED"
echo ""

if [ "$DRIFT_FOUND" -eq 1 ]; then
  echo "  STATUS: DRIFT ERKANNT!"
  echo "  Aktion erforderlich: Prüfe die Abweichungen und"
  echo "  aktualisiere entweder den IaC-Code oder setze"
  echo "  die Infrastruktur zurück."
  exit 1
else
  echo "  STATUS: Kein Drift erkannt"
  echo "  Infrastruktur und Code sind synchron."
  exit 0
fi
```

Gehe das Script Abschnitt für Abschnitt durch:

- **`check_drift`-Funktion**: Die zentrale Prüflogik. Vergleicht einen
  erwarteten Wert mit dem tatsächlichen Wert und gibt `OK` oder `DRIFT` aus.
  Die Zähler `CHECKS_PASSED` und `CHECKS_FAILED` ermöglichen eine
  Zusammenfassung am Ende.
- **Resource Group Tags**: Prüft, ob der Tag `ManagedBy` den Wert `bicep`
  hat. Wenn der Tag fehlt, wurde die Resource Group vermutlich manuell
  erstellt — das ist kein Drift, sondern eine Information.
- **App Service Plan SKU**: Prüft, ob die SKU noch `F1` (Free Tier) ist. Eine
  häufige manuelle Änderung ist das Hochskalieren der SKU im Portal, z. B.
  auf `S1`. Das Script erkennt diese Abweichung.
- **Web App Settings**: Prüft die Node.js-Version und die HTTPS-Only-
  Einstellung. Wenn jemand im Portal die Runtime ändert oder HTTPS deaktiviert,
  wird das als Drift erkannt.
- **Unerwartete Ressourcen**: Prüft, ob in der Resource Group Ressourcen ohne
  `ManagedBy`-Tag existieren. Solche Ressourcen wurden vermutlich manuell
  erstellt und sind nicht im IaC-Code erfasst.
- **Exit Code**: Das Script endet mit Exit Code `0` (kein Drift) oder `1`
  (Drift erkannt). Die Pipeline kann diesen Exit Code nutzen, um den Build
  als "failed" zu markieren.

Mache das Script ausführbar:

**Bash:**
```bash
chmod +x scripts/detect-drift.sh
```

**PowerShell:**
```powershell
git add scripts/detect-drift.sh
git update-index --chmod=+x scripts/detect-drift.sh
```

### Schritt 2: Pipeline mit Drift Detection

Jetzt erstellen wir eine Pipeline, die drei verschiedene Drift-Detection-
Ansätze parallel ausführt: eine Erklärung des Terraform-Ansatzes, das Custom
Script und einen Bicep-What-If-Check. Die Pipeline hat keinen CI-Trigger,
sondern wird per **Schedule** (täglich) und bei Bedarf manuell gestartet.

Ersetze den Inhalt von `azure-pipelines.yml`:

```yaml
# Drift Detection Pipeline
# Wird täglich per Schedule und bei manuellen Starts ausgeführt

trigger: none  # Kein CI-Trigger

schedules:
  - cron: '0 7 * * Mon-Fri'
    displayName: 'Täglicher Drift Check (07:00 UTC)'
    branches:
      include:
        - main
    always: true  # Auch ohne Code-Änderungen ausführen

variables:
  azureSubscription: 'azure-training-connection'
  resourceGroup: 'rg-pipeline-training'

stages:
  # ===== Terraform Drift Check =====
  - stage: TerraformDrift
    displayName: 'Terraform Drift Check'
    jobs:
      - job: TerraformPlan
        displayName: 'Terraform Plan (Drift)'
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - script: |
              echo "=== Terraform Drift Detection ==="
              echo ""
              echo "Terraform erkennt Drift automatisch bei 'terraform plan':"
              echo "- Wenn der Plan Änderungen zeigt, obwohl der Code"
              echo "  nicht geändert wurde, liegt Drift vor."
              echo ""
              echo "In einer realen Pipeline würde hier:"
              echo "1. terraform init"
              echo "2. terraform plan -detailed-exitcode"
              echo "   Exit Code 0 = Kein Drift"
              echo "   Exit Code 1 = Fehler"
              echo "   Exit Code 2 = Drift erkannt"
              echo ""
              echo "Für dieses Lab verwenden wir das Custom-Script im nächsten Stage."
            displayName: 'Terraform Drift Erklärung'

  # ===== Custom Drift Check =====
  - stage: CustomDrift
    displayName: 'Custom Drift Check'
    dependsOn: []  # Parallel zu Terraform
    jobs:
      - job: DriftDetection
        displayName: 'Drift Detection'
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - task: AzureCLI@2
            displayName: 'Drift Detection Script'
            inputs:
              azureSubscription: '$(azureSubscription)'
              scriptType: 'bash'
              scriptLocation: 'scriptPath'
              scriptPath: 'scripts/detect-drift.sh'
              arguments: '$(resourceGroup)'
            continueOnError: true  # Pipeline nicht abbrechen bei Drift

          - script: |
              echo "=== Drift-Report ==="
              echo ""
              echo "Mögliche Aktionen bei erkanntem Drift:"
              echo ""
              echo "1. IaC-Code aktualisieren:"
              echo "   Wenn die manuelle Änderung gewünscht war,"
              echo "   aktualisiere den Terraform/Bicep-Code."
              echo ""
              echo "2. Infrastruktur zurücksetzen:"
              echo "   Wenn die Änderung unerwünscht war,"
              echo "   führe terraform apply / bicep deploy aus."
              echo ""
              echo "3. Ignorieren (nicht empfohlen):"
              echo "   Drift sollte nie dauerhaft ignoriert werden."
            displayName: 'Drift-Aktionen dokumentieren'

  # ===== Bicep What-If als Drift Check =====
  - stage: BicepDrift
    displayName: 'Bicep What-If Drift'
    dependsOn: []  # Parallel zu anderen
    jobs:
      - job: BicepWhatIf
        displayName: 'Bicep What-If'
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - task: AzureCLI@2
            displayName: 'Bicep What-If (Drift Check)'
            inputs:
              azureSubscription: '$(azureSubscription)'
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              inlineScript: |
                echo "=== Bicep What-If Drift Detection ==="
                echo ""
                echo "Bicep What-If zeigt Unterschiede zwischen dem"
                echo "aktuellen Zustand und dem gewünschten Zustand."
                echo ""

                if [ -f bicep/main.bicep ]; then
                  echo "Führe What-If aus..."
                  az deployment group what-if \
                    --resource-group $(resourceGroup) \
                    --template-file bicep/main.bicep \
                    --parameters bicep/dev.parameters.json \
                    --parameters appVersion="drift-check" \
                    --no-pretty-print 2>&1 || true

                  echo ""
                  echo "Interpretation:"
                  echo "  'Create'  = Ressource fehlt (wurde manuell gelöscht)"
                  echo "  'Modify'  = Einstellungen geändert (Drift!)"
                  echo "  'Delete'  = Ressource existiert, ist aber nicht im Code"
                  echo "  'NoChange' = Alles in Ordnung"
                else
                  echo "Keine Bicep-Dateien gefunden. Überspringe."
                fi
            continueOnError: true
```

Gehe die Pipeline Abschnitt für Abschnitt durch:

- **`trigger: none`**: Im Gegensatz zu den bisherigen Pipelines hat diese
  keinen CI-Trigger. Drift Detection soll nicht bei Code-Änderungen laufen,
  sondern regelmäßig nach einem Zeitplan. Ein manueller Start ist weiterhin
  jederzeit möglich.
- **`schedules`**: Der Cron-Ausdruck `0 7 * * Mon-Fri` startet die Pipeline
  jeden Werktag um 07:00 UTC. `always: true` ist entscheidend: Ohne dieses
  Flag würde Azure Pipelines den Scheduled Run überspringen, wenn sich seit
  dem letzten Lauf kein Code geändert hat. Da wir aber nicht Code-Änderungen,
  sondern Infrastruktur-Drift prüfen wollen, muss die Pipeline **immer**
  laufen.
- **Drei parallele Stages**: Alle drei Stages haben `dependsOn: []` (die
  TerraformDrift-Stage implizit, da sie die erste ist). Dadurch laufen sie
  parallel und nicht nacheinander. Jede Stage prüft Drift mit einem anderen
  Ansatz:
  - **TerraformDrift**: Erklärt den Terraform-Ansatz mit
    `terraform plan -detailed-exitcode`. In einer realen Pipeline würde hier
    tatsächlich `terraform plan` laufen. Exit Code 2 bedeutet "Änderungen
    nötig" — wenn sich der Code nicht geändert hat, bedeutet das Drift.
  - **CustomDrift**: Führt das Shell-Script aus Schritt 1 aus. Der Parameter
    `continueOnError: true` stellt sicher, dass die Pipeline nicht abbricht,
    wenn Drift erkannt wird — stattdessen wird der Step als "partially
    succeeded" (orange) markiert. So kann der folgende Step den Drift-Report
    ausgeben.
  - **BicepDrift**: Nutzt `az deployment group what-if`, um den aktuellen
    Zustand der Azure-Ressourcen mit dem Bicep-Template zu vergleichen. Die
    Ausgabe zeigt farbcodiert, welche Ressourcen abweichen. Falls keine
    Bicep-Dateien vorhanden sind (weil Lab 17 nicht durchgeführt wurde), wird
    die Stage übersprungen.

### Schritt 3: Committen und starten

```bash
git add scripts/detect-drift.sh azure-pipelines.yml
git commit -m "Add infrastructure drift detection pipeline"
git push origin main
```

Da `trigger: none` gesetzt ist, wird die Pipeline **nicht** automatisch
gestartet. Starte sie manuell:

```bash
# Pipeline manuell starten
az pipelines run --name "hello-pipeline" --branch main --output table
```

Alternativ kannst du die Pipeline im Browser unter **Pipelines > hello-pipeline**
manuell starten (Button "Run pipeline").

### Schritt 4: Drift simulieren (optional)

Um zu sehen, wie das Script Drift erkennt, kannst du eine Ressource manuell
im Azure Portal ändern und die Pipeline erneut starten:

1. Öffne die Resource Group `rg-pipeline-training` im Portal.
2. Finde eine der erstellten Ressourcen (z. B. den App Service Plan aus
   Lab 17).
3. Ändere eine Einstellung manuell — zum Beispiel:
   - Ändere die SKU des App Service Plans von `F1` auf `B1`.
   - Füge einen neuen Tag hinzu oder ändere den `ManagedBy`-Tag.
   - Erstelle eine zusätzliche Ressource (z. B. einen leeren Storage Account)
     ohne `ManagedBy`-Tag.
4. Starte die Drift-Detection-Pipeline erneut manuell.

Das Custom-Script sollte jetzt den Drift erkennen und melden. Mache die
manuelle Änderung anschließend wieder rückgängig, um den sauberen Zustand
wiederherzustellen.

## Validierung

```bash
# Letzten Pipeline-Run prüfen
az pipelines runs list --top 1 --output table
```

Öffne im Browser das Build-Log und prüfe:

- **TerraformDrift-Stage**: Zeigt die Erklärung des Terraform-Ansatzes mit
  den drei Exit Codes.
- **CustomDrift-Stage**: Der Step "Drift Detection Script" zeigt für jeden
  Check `OK` oder `DRIFT`. Am Ende erscheint die Zusammenfassung mit der
  Anzahl bestandener und fehlgeschlagener Checks.
- **BicepDrift-Stage**: Zeigt die What-If-Ausgabe mit `Create`, `Modify`,
  `Delete` oder `NoChange` für jede Ressource (bzw. "Keine Bicep-Dateien
  gefunden", falls Lab 17 nicht durchgeführt wurde).

## Erwartetes Ergebnis

**Kein Drift (Custom Script):**

```
============================================
  Ergebnis
============================================
  Checks bestanden: 4
  Checks fehlgeschlagen: 0

  STATUS: Kein Drift erkannt
  Infrastruktur und Code sind synchron.
```

**Drift erkannt (z. B. nach manueller SKU-Änderung):**

```
  DRIFT: SKU des App Service Plans
      Erwartet: F1 | Aktuell: S1

============================================
  Ergebnis
============================================
  Checks bestanden: 3
  Checks fehlgeschlagen: 1

  STATUS: DRIFT ERKANNT!
```

**Bicep What-If (kein Drift):**

```
Resource changes: 0
No changes detected.
```

## Aufräumen

Kein Aufräumen nötig. Die Pipeline hat keine Ressourcen erstellt — sie prüft
nur den Zustand bestehender Ressourcen. Falls du in Schritt 4 manuell
Ressourcen erstellt oder geändert hast, mache diese Änderungen rückgängig.

## Tipps und Troubleshooting

- **`terraform plan -detailed-exitcode`**: Der zuverlässigste Weg, Drift mit
  Terraform zu erkennen. Exit Code 0 = kein Drift, Exit Code 1 = Fehler,
  Exit Code 2 = Drift (Änderungen nötig). In einer realen Pipeline kannst du
  den Exit Code auswerten und Benachrichtigungen auslösen.
- **Falsch-positive Drift-Meldungen**: Manche Azure-Ressourcen ändern intern
  Werte (z. B. Timestamps, interne IDs). Filtere diese in deinem Drift-Script
  heraus, indem du nur die für dich relevanten Properties prüfst.
- **Scheduled Pipelines**: Drift-Checks sollten regelmäßig (mindestens
  täglich) laufen. Konfiguriere Benachrichtigungen bei Drift — z. B. per
  Teams-Webhook, Slack-Integration oder Azure DevOps Notifications (unter
  **Project Settings > Notifications**).
- **Drift verhindern statt erkennen**: **Azure Policy** kann verhindern, dass
  bestimmte Änderungen außerhalb von IaC durchgeführt werden. Beispiel: Eine
  Policy mit Effect `Deny` kann das Hochskalieren einer SKU im Portal
  blockieren. Das ist effektiver als nachträgliche Drift-Detection, erfordert
  aber sorgfältige Policy-Planung.
- **`continueOnError: true`**: Ohne dieses Flag würde die Pipeline bei
  erkanntem Drift komplett als "failed" markiert. Mit dem Flag wird der
  Step als "partially succeeded" (orange) angezeigt, und nachfolgende Steps
  können noch den Drift-Report ausgeben. In der Praxis ist es Geschmackssache,
  ob Drift einen Build-Failure auslösen soll.
- **Mehrere Resource Groups**: Das Script akzeptiert den Resource-Group-Namen
  als Parameter (`$1`). Um mehrere Resource Groups zu prüfen, kannst du das
  Script mehrfach aufrufen oder eine Schleife einbauen.
