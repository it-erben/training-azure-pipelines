# Lab 16: Terraform mit Azure Pipelines

## Hintergrund

In den bisherigen Labs haben wir Azure-Ressourcen (Key Vault, ACR, App Service)
manuell per `az`-CLI erstellt. Das funktioniert für einzelne Ressourcen, wird
aber bei wachsender Infrastruktur schnell unübersichtlich und fehleranfällig:
Welche Ressourcen existieren? In welchem Zustand sind sie? Was passiert, wenn
jemand eine Ressource manuell im Portal ändert?

**Infrastructure as Code (IaC)** löst dieses Problem, indem die gesamte
Infrastruktur in Konfigurationsdateien beschrieben wird. **Terraform** von
HashiCorp ist eines der verbreitetsten IaC-Tools. Es beschreibt Infrastruktur
**deklarativ** in `.tf`-Dateien: Du definierst den gewünschten Zustand
(z. B. "es soll eine Resource Group, ein App Service Plan und eine Web App
geben"), und Terraform berechnet, welche Änderungen nötig sind, um diesen
Zustand zu erreichen.

In CI/CD-Pipelines wird Terraform typischerweise in zwei Schritten verwendet:

1. **Plan**: Terraform vergleicht den gewünschten Zustand (`.tf`-Dateien) mit
   dem aktuellen Zustand (State) und zeigt an, welche Ressourcen erstellt,
   geändert oder gelöscht werden. Der Plan wird als Artefakt gespeichert, damit
   ein Mensch ihn prüfen kann, bevor Änderungen durchgeführt werden.
2. **Apply**: Terraform führt die im Plan berechneten Änderungen durch. Durch
   die Verwendung des gespeicherten Plans (`-out=tfplan` / `tfplan`) ist
   sichergestellt, dass **exakt** die geprüften Änderungen angewendet werden —
   nicht mehr und nicht weniger.

Der **Terraform State** ist eine JSON-Datei, die den aktuellen Zustand aller
von Terraform verwalteten Ressourcen enthält. Bei lokaler Nutzung liegt sie
als `terraform.tfstate` im Arbeitsverzeichnis. In einem Team-Szenario
(und in CI/CD-Pipelines) muss der State zentral gespeichert werden, damit
alle denselben Stand verwenden. Azure bietet dafür einen **Storage Account
als Remote Backend**: Der State wird als Blob in einem Container gespeichert
und automatisch per Lock geschützt, damit nicht zwei Personen gleichzeitig
Änderungen vornehmen.

## Voraussetzungen

- Die Service Connection `azure-training-connection` aus Lab 05.
- Das Environment `dev` aus Lab 11.
- Die **Terraform-Extension** für Azure DevOps (wird in Schritt 4 installiert).

## Aufgabenstellung

### Schritt 1: Storage Account für Terraform State erstellen

Bevor wir Terraform in der Pipeline nutzen können, brauchen wir einen Storage
Account, in dem der Terraform State gespeichert wird. Storage-Account-Namen
müssen global eindeutig sein und dürfen nur Kleinbuchstaben und Zahlen
enthalten.

**Bash:**

```bash
# Eindeutigen Storage Account Namen generieren
STORAGE_NAME="sttraining$(whoami | tr -dc 'a-z0-9' | head -c 4)$(date +%m%d)"
echo "Storage Account: $STORAGE_NAME"
```

**PowerShell:**

```powershell
# Eindeutigen Storage Account Namen generieren
$user = ($env:USERNAME).ToLower() -replace '[^a-z0-9]',''
$STORAGE_NAME = "sttraining$($user.Substring(0,[Math]::Min(4,$user.Length)))$(Get-Date -Format 'MMdd')"
echo "Storage Account: $STORAGE_NAME"
```

**Bash:**

```bash
# Storage Account erstellen
az storage account create \
  --name $STORAGE_NAME \
  --resource-group rg-pipeline-training \
  --location westeurope \
  --sku Standard_LRS \
  --output table

# Container für Terraform State erstellen
az storage container create \
  --name tfstate \
  --account-name $STORAGE_NAME \
  --output table

echo "Storage Account erstellt: $STORAGE_NAME"
echo "Container: tfstate"
```

**PowerShell:**

```powershell
# Storage Account erstellen
az storage account create `
  --name $STORAGE_NAME `
  --resource-group rg-pipeline-training `
  --location westeurope `
  --sku Standard_LRS `
  --output table

# Container für Terraform State erstellen
az storage container create `
  --name tfstate `
  --account-name $STORAGE_NAME `
  --output table

echo "Storage Account erstellt: $STORAGE_NAME"
echo "Container: tfstate"
```

`Standard_LRS` (Locally Redundant Storage) ist die günstigste Redundanz-Option
und reicht für den Terraform State aus. Der Container `tfstate` wird die
State-Datei als Blob enthalten. Der Name des Blobs wird in der Pipeline als
`tfBackendKey` konfiguriert.

### Schritt 2: Terraform-Konfiguration erstellen

Erstelle ein `terraform/`-Verzeichnis im Repository und lege dort die
Konfigurationsdateien an. Terraform-Konfigurationen werden üblicherweise auf
mehrere Dateien aufgeteilt: `main.tf` für die Ressourcen-Definitionen,
`variables.tf` für die Eingabe-Variablen, `outputs.tf` für die Ausgabe-Werte
und `.tfvars`-Dateien für umgebungsspezifische Werte.

```bash
mkdir -p terraform
```

Erstelle die Datei **terraform/main.tf** — die Hauptkonfiguration mit
Provider, Backend und den drei Ressourcen (Resource Group, App Service Plan,
Web App):

```hcl
terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }

  backend "azurerm" {
    # Werte werden über Pipeline-Variablen gesetzt
  }
}

provider "azurerm" {
  features {}
}

# Resource Group
resource "azurerm_resource_group" "app" {
  name     = "rg-${var.project_name}-${var.environment}"
  location = var.location

  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}

# App Service Plan
resource "azurerm_service_plan" "app" {
  name                = "plan-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.app.name
  location            = azurerm_resource_group.app.location
  os_type             = "Linux"
  sku_name            = "F1"

  tags = azurerm_resource_group.app.tags
}

# Web App
resource "azurerm_linux_web_app" "app" {
  name                = "${var.project_name}-${var.environment}-${var.unique_suffix}"
  resource_group_name = azurerm_resource_group.app.name
  location            = azurerm_resource_group.app.location
  service_plan_id     = azurerm_service_plan.app.id

  site_config {
    application_stack {
      node_version = "20-lts"
    }
  }

  app_settings = {
    "ENVIRONMENT" = var.environment
    "APP_VERSION" = var.app_version
  }

  tags = azurerm_resource_group.app.tags
}
```

Gehe die Datei Abschnitt für Abschnitt durch:

- **`terraform`-Block**: Definiert die benötigte Terraform-Version (`>= 1.0`)
  und den Azure-Provider (`hashicorp/azurerm` in Version `~> 3.0`). Der
  `backend "azurerm"`-Block konfiguriert den Remote State — die konkreten
  Werte (Storage Account, Container, Key) werden von der Pipeline beim
  `terraform init` übergeben, damit sie nicht im Code stehen.
- **`provider "azurerm"`**: Konfiguriert den Azure-Provider. `features {}` ist
  ein Pflichtblock, auch wenn keine speziellen Features konfiguriert werden.
- **Resource Group**: Erstellt eine neue Resource Group mit einem Namen, der
  aus Projektname und Umgebung zusammengesetzt ist (z. B.
  `rg-training-app-dev`). Die Tags (`ManagedBy = "terraform"`) helfen dabei,
  Terraform-verwaltete Ressourcen von manuell erstellten zu unterscheiden.
- **App Service Plan**: Erstellt einen Linux-basierten Plan mit Free Tier
  (`F1`). Beachte die Referenzen auf andere Ressourcen:
  `azurerm_resource_group.app.name` verweist auf die oben definierte Resource
  Group. Terraform erkennt diese Abhängigkeiten automatisch und erstellt die
  Ressourcen in der richtigen Reihenfolge.
- **Web App**: Erstellt eine Linux-Web-App mit Node.js 20 und setzt
  App-Settings für Umgebung und Version. Der Name enthält einen
  `unique_suffix`, um die globale Eindeutigkeit sicherzustellen.

Erstelle die Datei **terraform/variables.tf** — die Eingabe-Variablen mit
Typen, Beschreibungen und Default-Werten:

```hcl
variable "project_name" {
  description = "Name des Projekts"
  type        = string
  default     = "training-app"
}

variable "environment" {
  description = "Umgebung (dev, staging, production)"
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure-Region"
  type        = string
  default     = "westeurope"
}

variable "unique_suffix" {
  description = "Eindeutiger Suffix für global eindeutige Namen"
  type        = string
}

variable "app_version" {
  description = "Anwendungsversion"
  type        = string
  default     = "1.0.0"
}
```

Beachte, dass `unique_suffix` keinen Default-Wert hat — diese Variable muss
bei jedem `terraform plan` / `terraform apply` explizit übergeben werden.
Die Pipeline tut das über `-var="unique_suffix=$(uniqueSuffix)"`.

Erstelle die Datei **terraform/outputs.tf** — die Ausgabe-Werte, die nach
einem `terraform apply` angezeigt werden:

```hcl
output "resource_group_name" {
  value = azurerm_resource_group.app.name
}

output "web_app_name" {
  value = azurerm_linux_web_app.app.name
}

output "web_app_url" {
  value = "https://${azurerm_linux_web_app.app.default_hostname}"
}

output "app_service_plan" {
  value = azurerm_service_plan.app.name
}
```

Outputs machen wichtige Informationen (wie die URL der erstellten Web App)
im Pipeline-Log und für andere Terraform-Module sichtbar.

Erstelle schließlich die Datei **terraform/dev.tfvars** — die
umgebungsspezifischen Werte für die Dev-Umgebung:

```hcl
project_name  = "training-app"
environment   = "dev"
location      = "westeurope"
unique_suffix = "REPLACE_ME"
app_version   = "1.0.0"
```

Ersetze `REPLACE_ME` mit deinem persönlichen Kürzel (z. B. `mmu`). Die
Pipeline überschreibt `unique_suffix` und `app_version` per
`-var`-Parameter, sodass die Werte in der `.tfvars`-Datei als Fallback für
lokale Ausführung dienen.

### Schritt 3: Pipeline mit Terraform Plan/Apply

Jetzt erstellen wir eine Pipeline mit drei Stages: Plan, Apply und Verify. Die
Plan-Stage berechnet die Änderungen und speichert den Plan als Artefakt. Die
Apply-Stage führt den Plan aus (idealerweise nach einem Approval Gate). Die
Verify-Stage prüft, ob die Ressourcen tatsächlich erstellt wurden.

Ersetze den Inhalt von `azure-pipelines.yml`. **Wichtig**: Ersetze die
Platzhalter `<dein-storage-account>` und `<dein-kürzel>`:

```yaml
trigger:
  branches:
    include:
      - main
  paths:
    include:
      - terraform/*

variables:
  azureSubscription: 'azure-training-connection'
  # Ersetze diese Werte:
  tfBackendStorageAccount: '<dein-storage-account>'
  tfBackendContainerName: 'tfstate'
  tfBackendKey: 'training.terraform.tfstate'
  # Eindeutiger Suffix für App-Namen
  uniqueSuffix: '<dein-kürzel>'

stages:
  # ===== Terraform Plan =====
  - stage: Plan
    displayName: 'Terraform Plan'
    jobs:
      - job: TerraformPlan
        displayName: 'Plan'
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          # Terraform installieren
          - task: TerraformInstaller@1
            displayName: 'Terraform installieren'
            inputs:
              terraformVersion: 'latest'

          # Terraform Init
          - task: TerraformTaskV4@4
            displayName: 'Terraform Init'
            inputs:
              provider: 'azurerm'
              command: 'init'
              workingDirectory: '$(System.DefaultWorkingDirectory)/terraform'
              backendServiceArm: '$(azureSubscription)'
              backendAzureRmResourceGroupName: 'rg-pipeline-training'
              backendAzureRmStorageAccountName: '$(tfBackendStorageAccount)'
              backendAzureRmContainerName: '$(tfBackendContainerName)'
              backendAzureRmKey: '$(tfBackendKey)'

          # Terraform Validate
          - task: TerraformTaskV4@4
            displayName: 'Terraform Validate'
            inputs:
              provider: 'azurerm'
              command: 'validate'
              workingDirectory: '$(System.DefaultWorkingDirectory)/terraform'

          # Terraform Plan
          - task: TerraformTaskV4@4
            displayName: 'Terraform Plan'
            inputs:
              provider: 'azurerm'
              command: 'plan'
              workingDirectory: '$(System.DefaultWorkingDirectory)/terraform'
              environmentServiceNameAzureRM: '$(azureSubscription)'
              commandOptions: '-var-file=dev.tfvars -var="unique_suffix=$(uniqueSuffix)" -var="app_version=1.0.$(Build.BuildId)" -out=tfplan'

          # Plan als Artefakt speichern
          - publish: '$(System.DefaultWorkingDirectory)/terraform'
            artifact: terraform-plan
            displayName: 'Plan-Artefakt publizieren'

  # ===== Terraform Apply (mit Approval) =====
  - stage: Apply
    displayName: 'Terraform Apply'
    dependsOn: Plan
    jobs:
      - deployment: TerraformApply
        displayName: 'Apply'
        pool:
          vmImage: 'ubuntu-latest'
        environment: 'dev'
        strategy:
          runOnce:
            deploy:
              steps:
                - task: TerraformInstaller@1
                  displayName: 'Terraform installieren'
                  inputs:
                    terraformVersion: 'latest'

                # Terraform Init (muss erneut ausgeführt werden)
                - task: TerraformTaskV4@4
                  displayName: 'Terraform Init'
                  inputs:
                    provider: 'azurerm'
                    command: 'init'
                    workingDirectory: '$(Pipeline.Workspace)/terraform-plan'
                    backendServiceArm: '$(azureSubscription)'
                    backendAzureRmResourceGroupName: 'rg-pipeline-training'
                    backendAzureRmStorageAccountName: '$(tfBackendStorageAccount)'
                    backendAzureRmContainerName: '$(tfBackendContainerName)'
                    backendAzureRmKey: '$(tfBackendKey)'

                # Terraform Apply
                - task: TerraformTaskV4@4
                  displayName: 'Terraform Apply'
                  inputs:
                    provider: 'azurerm'
                    command: 'apply'
                    workingDirectory: '$(Pipeline.Workspace)/terraform-plan'
                    environmentServiceNameAzureRM: '$(azureSubscription)'
                    commandOptions: 'tfplan'

  # ===== Verify =====
  - stage: Verify
    displayName: 'Infrastruktur prüfen'
    dependsOn: Apply
    jobs:
      - job: VerifyInfra
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - task: AzureCLI@2
            displayName: 'Erstellte Ressourcen prüfen'
            inputs:
              azureSubscription: '$(azureSubscription)'
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              inlineScript: |
                echo "=== Erstellte Ressourcen ==="
                az resource list \
                  --resource-group "rg-training-app-dev" \
                  --output table

                echo ""
                echo "=== Web App Status ==="
                az webapp show \
                  --name "training-app-dev-$(uniqueSuffix)" \
                  --resource-group "rg-training-app-dev" \
                  --query "{name:name, state:state, url:defaultHostName}" \
                  --output table
```

Gehe die Pipeline Abschnitt für Abschnitt durch:

- **Trigger mit Path-Filter**: Die Pipeline wird nur ausgelöst, wenn sich
  Dateien unter `terraform/*` ändern. Änderungen an der Anwendung (z. B.
  `src/app.js`) lösen keinen Terraform-Run aus — das ist wichtig, da
  Infrastructure-Änderungen und Code-Deployments typischerweise getrennte
  Pipelines haben.
- **Plan-Stage**: Führt vier Schritte aus:
    - `TerraformInstaller@1` installiert die Terraform-CLI auf dem Agent.
    - `init` initialisiert das Backend (verbindet sich mit dem Storage Account
      und lädt den bestehenden State herunter). Die Backend-Konfiguration wird
      über Task-Parameter übergeben, nicht in der `.tf`-Datei — so können
      verschiedene Umgebungen verschiedene Backends verwenden.
    - `validate` prüft die Syntax der `.tf`-Dateien, ohne auf den
      Provider zuzugreifen.
    - `plan` vergleicht den gewünschten Zustand mit dem aktuellen State und
      berechnet die Änderungen. `-out=tfplan` speichert den Plan als Binärdatei.
      `-var-file=dev.tfvars` lädt die umgebungsspezifischen Variablen, und die
      `-var`-Parameter überschreiben einzelne Werte.
    - Anschließend wird das gesamte `terraform/`-Verzeichnis (inklusive Plan-
      Datei) als Artefakt publiziert.
- **Apply-Stage**: Ein Deployment Job, der das Artefakt aus der Plan-Stage
  herunterlädt. Beachte, dass `terraform init` **erneut** ausgeführt werden
  muss, da die Apply-Stage auf einem **anderen Agent** läuft als die
  Plan-Stage — der `.terraform/`-Ordner (mit Provider-Plugins) existiert dort
  nicht. `terraform apply tfplan` wendet exakt den gespeicherten Plan an — ohne
  erneute Berechnung. Da die Stage einen Deployment Job mit
  `environment: 'dev'` verwendet, kann man hier ein Approval Gate
  konfigurieren (Lab 12), damit jemand den Plan prüft, bevor Apply läuft.
- **Verify-Stage**: Prüft per Azure CLI, ob die Ressourcen tatsächlich
  erstellt wurden. In der Praxis könnte man hier auch funktionale Tests
  gegen die erstellte Infrastruktur ausführen.

### Schritt 4: Terraform-Extension installieren

Die `TerraformInstaller@1`- und `TerraformTaskV4@4`-Tasks sind nicht in Azure
DevOps eingebaut, sondern kommen aus einer **Extension**, die separat
installiert werden muss:

1. Gehe zu **Organization Settings > Extensions** (oben links in Azure
   DevOps auf die Organisation klicken, dann links auf "Extensions").
2. Klicke auf **"Browse marketplace"**.
3. Suche nach **"Terraform"** und wähle die Extension von **Microsoft
   DevLabs**.
4. Klicke auf **"Get it free"** und installiere sie in deiner Organisation.

Die Extension stellt die Tasks `TerraformInstaller@1` und
`TerraformTaskV4@4` bereit. Ohne diese Extension schlägt die Pipeline mit
der Fehlermeldung "TerraformTaskV4 not found" fehl.

### Schritt 5: Platzhalter ersetzen, committen und beobachten

Ersetze die Platzhalter in der Pipeline-Datei und in der `dev.tfvars`-Datei.
Ersetze auch `REPLACE_ME` in der `dev.tfvars` mit deinem Kürzel:

**Bash:**

```bash
# Platzhalter in der Pipeline ersetzen
sed -i "s/<dein-storage-account>/$STORAGE_NAME/g" azure-pipelines.yml
sed -i "s/<dein-kürzel>/$(whoami | head -c 3)/g" azure-pipelines.yml

# Platzhalter in dev.tfvars ersetzen
sed -i "s/REPLACE_ME/$(whoami | head -c 3)/g" terraform/dev.tfvars
```

**PowerShell:**

```powershell
# Platzhalter in der Pipeline ersetzen
$SUFFIX = ($env:USERNAME).Substring(0,3)
(Get-Content azure-pipelines.yml) -replace '<dein-storage-account>',$STORAGE_NAME | Set-Content azure-pipelines.yml
(Get-Content azure-pipelines.yml) -replace '<dein-kürzel>',$SUFFIX | Set-Content azure-pipelines.yml

# Platzhalter in dev.tfvars ersetzen
(Get-Content terraform/dev.tfvars) -replace 'REPLACE_ME',$SUFFIX | Set-Content terraform/dev.tfvars
```

```bash
git add terraform/main.tf terraform/variables.tf terraform/outputs.tf terraform/dev.tfvars azure-pipelines.yml
git commit -m "Add Terraform IaC pipeline"
git push origin main
```

Beobachte den Pipeline-Run im Browser:

- Die **Plan-Stage** zeigt im Log des `terraform plan`-Steps die geplanten
  Änderungen: "3 to add, 0 to change, 0 to destroy" (Resource Group, App
  Service Plan, Web App).
- Die **Apply-Stage** führt die Änderungen durch und zeigt die Outputs
  (Resource-Group-Name, Web-App-Name, URL).
- Die **Verify-Stage** listet die erstellten Ressourcen und zeigt den Status
  der Web App.

## Validierung

Prüfe per CLI, ob State und Ressourcen korrekt erstellt wurden:

**Bash:**

```bash
# Terraform State im Storage Account prüfen (sollte einen Blob zeigen)
az storage blob list \
  --account-name $STORAGE_NAME \
  --container-name tfstate \
  --output table

# Erstellte Ressourcen in der neuen Resource Group prüfen
az resource list --resource-group rg-training-app-dev --output table
```

**PowerShell:**

```powershell
# Terraform State im Storage Account prüfen (sollte einen Blob zeigen)
az storage blob list `
  --account-name $STORAGE_NAME `
  --container-name tfstate `
  --output table

# Erstellte Ressourcen in der neuen Resource Group prüfen
az resource list --resource-group rg-training-app-dev --output table
```

Öffne im Browser das Build-Log und prüfe:

- Die **Plan-Stage** zeigt `Plan: 3 to add, 0 to change, 0 to destroy.`
- Die **Apply-Stage** zeigt `Apply complete! Resources: 3 added, 0 changed, 0 destroyed.`
- Die **Verify-Stage** listet drei Ressourcen in der Resource Group.

## Erwartetes Ergebnis

**Terraform Plan Output:**

```
Plan: 3 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + resource_group_name = "rg-training-app-dev"
  + web_app_name        = "training-app-dev-mmu"
  + web_app_url         = "https://training-app-dev-mmu.azurewebsites.net"
```

**Terraform Apply Output:**

```
Apply complete! Resources: 3 added, 0 changed, 0 destroyed.

Outputs:
resource_group_name = "rg-training-app-dev"
web_app_name = "training-app-dev-mmu"
web_app_url = "https://training-app-dev-mmu.azurewebsites.net"
```

## Aufräumen

Die von Terraform erstellten Ressourcen (Resource Group, App Service Plan, Web
App) und der Storage Account für den State sollten nach dem Lab gelöscht
werden. Verwende `terraform destroy`, um die Ressourcen sauber über Terraform
zu entfernen (statt sie manuell im Portal zu löschen — sonst gerät der State
aus dem Takt):

**Bash:**

```bash
# Terraform Destroy (lokal ausführen)
cd ~/hello-pipeline/terraform
terraform init \
  -backend-config="resource_group_name=rg-pipeline-training" \
  -backend-config="storage_account_name=$STORAGE_NAME" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=training.terraform.tfstate"

terraform destroy -var-file=dev.tfvars -var="unique_suffix=$(whoami | head -c 3)" -auto-approve

# Storage Account für Terraform State löschen
az storage account delete --name $STORAGE_NAME --resource-group rg-pipeline-training --yes
```

**PowerShell:**

```powershell
# Terraform Destroy (lokal ausführen)
cd ~/hello-pipeline/terraform
terraform init `
  -backend-config="resource_group_name=rg-pipeline-training" `
  -backend-config="storage_account_name=$STORAGE_NAME" `
  -backend-config="container_name=tfstate" `
  -backend-config="key=training.terraform.tfstate"

terraform destroy -var-file=dev.tfvars -var="unique_suffix=$($env:USERNAME.Substring(0,3))" -auto-approve

# Storage Account für Terraform State löschen
az storage account delete --name $STORAGE_NAME --resource-group rg-pipeline-training --yes
```

Prüfe im Azure Portal, dass die Resource Group `rg-training-app-dev` und der
Storage Account gelöscht wurden.

## Tipps und Troubleshooting

- **"TerraformTaskV4 not found"**: Die Terraform-Extension von Microsoft
  DevLabs muss in der Azure DevOps Organisation installiert sein (Schritt 4).
  Prüfe unter **Organization Settings > Extensions**, ob die Extension
  aufgelistet ist.
- **State Lock**: Terraform sperrt den State automatisch während `plan` und
  `apply`, um konkurrierende Änderungen zu verhindern. Wenn eine Pipeline
  abbricht, kann der Lock hängenbleiben. Löse ihn mit
  `terraform force-unlock <lock-id>`. Die Lock-ID findest du in der
  Fehlermeldung.
- **`init` in jeder Stage**: Da Plan- und Apply-Stage auf **verschiedenen
  Agents** laufen, muss `terraform init` in beiden Stages ausgeführt werden.
  Das Init in der Apply-Stage lädt die Provider-Plugins erneut herunter und
  verbindet sich mit dem Backend. Der Plan selbst wird als Artefakt zwischen
  den Stages übergeben.
- **Sensitive Outputs**: Markiere Outputs mit sensiblen Daten als
  `sensitive = true`, damit sie im Pipeline-Log maskiert werden. Beispiel:
  `output "db_password" { value = ..., sensitive = true }`.
- **Terraform-Version fixieren**: In der Pipeline verwenden wir
  `terraformVersion: 'latest'`. In der Praxis solltest du eine feste Version
  angeben (z. B. `1.7.0`), um sicherzustellen, dass alle Team-Mitglieder und
  die Pipeline dieselbe Version verwenden. Unterschiedliche Versionen können
  inkompatible State-Formate erzeugen.
- **Approval vor Apply**: Konfiguriere ein Approval Gate auf dem Environment
  (wie in Lab 12), damit jemand den Plan prüft, bevor Apply ausgeführt wird.
  Das ist in der Praxis die häufigste Absicherung: Der Plan zeigt genau, was
  passieren wird, und ein Mensch bestätigt, dass es korrekt ist.
- **Terraform Destroy in der Pipeline**: Für ein kontrolliertes Aufräumen
  kannst du eine separate Pipeline oder eine Stage mit `command: 'destroy'`
  erstellen. Schütze diese mit einem Approval Gate, damit niemand
  versehentlich Infrastruktur löscht.
