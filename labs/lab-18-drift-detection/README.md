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
  oder einen Tag, ohne den IaC-Code anzupassen. Beim nächsten Bicep-Deployment
  wird die manuelle Änderung überschrieben.
- **Änderungen durch andere Pipelines oder Skripte**: Verschiedene Teams
  arbeiten an derselben Infrastruktur, aber nicht alle Änderungen fließen in
  den IaC-Code zurück.
- **Automatische Updates durch Azure**: Manche Azure-Dienste aktualisieren
  intern Konfigurationswerte (z.B. TLS-Versionen, Runtime-Patches), die
  dann vom definierten Zustand abweichen.

Drift ist gefährlich, weil er zu **unerwartetem Verhalten** führt: Der
IaC-Code beschreibt nicht mehr die Realität. Ein Deployment könnte
unbeabsichtigt manuelle Änderungen rückgängig machen, oder es schlägt fehl,
weil sich Vorbedingungen geändert haben. Je länger Drift unentdeckt bleibt,
desto schwieriger ist die Korrektur.

### Bicep What-If als Drift-Detection

In Lab 17 haben wir `az deployment group what-if` als Vorschau vor einem
Deployment genutzt. Derselbe Befehl eignet sich hervorragend zur
**Drift-Detection**: Wenn What-If Änderungen anzeigt, obwohl sich der
Bicep-Code nicht geändert hat, muss sich die Infrastruktur verändert haben —
das ist Drift.

| What-If-Ergebnis | Bedeutung                                         |
|:-----------------|:--------------------------------------------------|
| `NoChange`       | Kein Drift — alles in Ordnung                     |
| `Modify`         | Einstellung wurde manuell geändert (Drift!)       |
| `Create`         | Ressource fehlt — wurde manuell gelöscht          |
| `Delete`         | Ressource existiert, ist aber nicht im Bicep-Code |

In diesem Lab erstellen wir eine Pipeline, die per **Schedule** täglich den
Bicep-What-If-Check gegen die in Lab 17 erstellten Ressourcen ausführt und
Drift meldet.

## Voraussetzungen

- Die Service Connection `azure-training-connection` aus Lab 05.
- Die **Bicep-Ressourcen aus Lab 17** (Storage Account und File Share). Falls
  diese nicht mehr existieren, führe Lab 17 erneut aus.

## Aufgabenstellung

### Schritt 1: Drift-Detection-Pipeline erstellen

Wir erstellen eine Pipeline, die nicht bei Code-Änderungen, sondern per
**Schedule** (täglich) läuft. Sie führt einen Bicep-What-If-Check gegen die
bestehende Infrastruktur durch und meldet Abweichungen.

Ersetze den Inhalt von `azure-pipelines.yml`. **Wichtig**: Ersetze den
Platzhalter `<dein-kürzel>` mit demselben Kürzel, das du in Lab 17 verwendet
hast:

```yaml
# Drift Detection Pipeline
# Wird täglich per Schedule und bei manuellen Starts ausgeführt

trigger: none  # Kein CI-Trigger

schedules:
  - cron: '0 7 * * Mon-Fri'
    displayName: 'Täglicher Drift Check (07:00 UTC)'
    branches:
      include:
        - master
    always: true  # Auch ohne Code-Änderungen ausführen

variables:
  azureSubscription: 'azure-training-connection'
  resourceGroup: 'rg-pipeline-training'
  uniqueSuffix: '<dein-kürzel>'

stages:
  # ===== What-If Drift Check =====
  - stage: DriftCheck
    displayName: 'Bicep Drift Detection'
    jobs:
      - job: WhatIf
        displayName: 'What-If Drift Check'
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

                RESULT=$(az deployment group what-if \
                  --resource-group $(resourceGroup) \
                  --template-file bicep/main.bicep \
                  --parameters bicep/dev.parameters.json \
                  --parameters uniqueSuffix=$(uniqueSuffix) 2>&1)

                echo "$RESULT"
                echo ""

                # Prüfe die Zusammenfassungszeile auf echte Änderungen
                if echo "$RESULT" | grep -qE "to (create|modify|delete)"; then
                  echo "============================================"
                  echo "  DRIFT ERKANNT!"
                  echo "============================================"
                  echo ""
                  echo "  Mögliche Aktionen:"
                  echo "  1. IaC-Code aktualisieren (wenn die Änderung gewünscht war)"
                  echo "  2. Bicep erneut deployen (wenn die Änderung unerwünscht war)"
                  exit 1
                else
                  echo "============================================"
                  echo "  Kein Drift erkannt"
                  echo "  Infrastruktur und Code sind synchron."
                  echo "============================================"
                fi
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
- **What-If-Check**: Führt `az deployment group what-if` mit denselben
  Parametern aus wie das Deployment in Lab 17. Die Ausgabe zeigt, welche
  Ressourcen abweichen. Das Script prüft die Zusammenfassungszeile per `grep`
  auf `to create`, `to modify` oder `to delete` — wenn ja, liegt Drift vor
  und das Script endet mit Exit Code 1 (Pipeline wird rot).

### Schritt 2: Committen und starten

```bash
git add azure-pipelines.yml
git commit -m "Add drift detection pipeline"
git push origin master
```

Da `trigger: none` gesetzt ist, wird die Pipeline **nicht** automatisch
gestartet. Starte sie manuell im Browser unter **Pipelines > hello-pipeline**
(Button "Run pipeline").

Die Pipeline sollte **grün** durchlaufen und "Kein Drift erkannt" melden — die
Ressourcen aus Lab 17 sind noch im erwarteten Zustand.

### Schritt 3: Drift simulieren

Um zu sehen, wie die Pipeline Drift erkennt, ändern wir eine Ressource manuell
per CLI:

**Bash:**

```bash
# Tag des Storage Accounts ändern (simuliert eine manuelle Portal-Änderung)
az storage account update \
  --name sttrainingdev<dein-kürzel> \
  --resource-group rg-pipeline-training \
  --tags Environment=production Project=training ManagedBy=bicep
```

**PowerShell:**

```powershell
az storage account update `
  --name sttrainingdev<dein-kürzel> `
  --resource-group rg-pipeline-training `
  --tags Environment=production Project=training ManagedBy=bicep
```

Wir haben den Tag `Environment` von `dev` auf `production` geändert. Starte
die Pipeline erneut manuell — sie sollte jetzt **rot** werden und Drift melden:

```
Modify  Microsoft.Storage/storageAccounts/sttrainingdev...
  tags.Environment:  "production" => "dev"
```

Die What-If-Ausgabe zeigt genau, welche Eigenschaft abweicht und was das
Deployment ändern würde, um den gewünschten Zustand wiederherzustellen.

### Schritt 4: Drift beheben

Um den Drift zu beheben, führe einfach das Bicep-Deployment aus Lab 17 erneut
aus. Bicep setzt den Tag zurück auf den im Code definierten Wert:

**Bash:**

```bash
az deployment group create \
  --resource-group rg-pipeline-training \
  --template-file bicep/main.bicep \
  --parameters bicep/dev.parameters.json \
  --parameters uniqueSuffix=<dein-kürzel>
```

**PowerShell:**

```powershell
az deployment group create `
  --resource-group rg-pipeline-training `
  --template-file bicep/main.bicep `
  --parameters bicep/dev.parameters.json `
  --parameters uniqueSuffix=<dein-kürzel>
```

Starte die Drift-Detection-Pipeline ein letztes Mal — sie sollte wieder
**grün** sein.

## Validierung

Öffne im Browser das Build-Log und prüfe:

- **Vor der manuellen Änderung**: Die Pipeline ist grün und zeigt "Kein Drift
  erkannt".
- **Nach der manuellen Änderung**: Die Pipeline ist rot und zeigt "DRIFT
  ERKANNT!" mit der What-If-Ausgabe, die den geänderten Tag anzeigt.
- **Nach dem erneuten Deployment**: Die Pipeline ist wieder grün.

## Erwartetes Ergebnis

**Kein Drift:**

```
  = Microsoft.Storage/storageAccounts/sttrainingdevmmu [2023-01-01]
  = Microsoft.Storage/storageAccounts/sttrainingdevmmu/fileServices/default [2023-01-01]
  = Microsoft.Storage/storageAccounts/sttrainingdevmmu/.../shares/share-training-dev [2023-01-01]

Resource changes: 3 no change.
============================================
  Kein Drift erkannt
  Infrastruktur und Code sind synchron.
============================================
```

**Drift erkannt (nach manueller Tag-Änderung):**

```
  ~ Microsoft.Storage/storageAccounts/sttrainingdevmmu [2023-01-01]
    ~ tags.Environment:  "production" => "dev"

Resource changes: 1 to modify, 2 no change.
============================================
  DRIFT ERKANNT!
============================================
```

## Aufräumen

Kein Aufräumen nötig. Die Pipeline hat keine Ressourcen erstellt — sie prüft
nur den Zustand bestehender Ressourcen. Falls der Drift aus Schritt 3 noch
nicht behoben wurde, führe Schritt 4 aus.

## Tipps und Troubleshooting

- **Falsch-positive Drift-Meldungen**: Manche Azure-Ressourcen ändern intern
  Werte (z. B. Timestamps, interne IDs). What-If meldet diese als `Modify`.
  In der Praxis filtert man solche Änderungen heraus, indem man die
  What-If-Ausgabe gezielter auswertet.
- **Scheduled Pipelines**: Drift-Checks sollten regelmäßig (mindestens
  täglich) laufen. Konfiguriere Benachrichtigungen bei Drift — z. B. per
  Teams-Webhook oder Azure DevOps Notifications (unter **Project Settings >
  Notifications**).
- **Drift verhindern statt erkennen**: **Azure Policy** kann verhindern, dass
  bestimmte Änderungen außerhalb von IaC durchgeführt werden. Beispiel: Eine
  Policy mit Effect `Deny` kann das Ändern von Tags im Portal blockieren. Das
  ist effektiver als nachträgliche Drift-Detection, erfordert aber sorgfältige
  Policy-Planung.
- **Terraform-Alternative**: Terraform erkennt Drift mit
  `terraform plan -detailed-exitcode`. Exit Code 0 = kein Drift, Exit Code 2 =
  Drift erkannt. Das Prinzip ist identisch zu Bicep What-If, nur dass
  Terraform seinen eigenen State als Referenz nutzt statt Azure direkt.
- **`continueOnError`**: In der aktuellen Pipeline bricht der Build bei Drift
  ab (rot). Wenn du stattdessen eine Warnung bevorzugst, füge
  `continueOnError: true` zum Task hinzu — der Step wird dann orange statt rot.
