# Lab 17: Bicep-Deployments

## Hintergrund

In Lab 16 haben wir Terraform als Infrastructure-as-Code-Tool kennengelernt.
Terraform ist Cloud-agnostisch und hat ein riesiges Ökosystem, bringt aber auch
Komplexität mit: einen separaten State, einen externen Provider und ein eigenes
Tool, das installiert und versioniert werden muss.

**Bicep** ist Microsofts eigene IaC-Sprache für Azure. Sie ist eine direkte
Abstraktion über **ARM-Templates** (Azure Resource Manager) und kompiliert
intern zu ARM-JSON. Der entscheidende Unterschied zu Terraform: Bicep braucht
**keinen separaten State**. Azure selbst ist die "Source of Truth" — Bicep
vergleicht bei jedem Deployment den gewünschten Zustand mit dem tatsächlichen
Zustand der Azure-Ressourcen und berechnet die nötigen Änderungen. Das
vereinfacht das Setup erheblich: kein Storage Account für den State, keine
Locks, keine State-Migration.

Vorteile gegenüber ARM-Templates:

- **Kürzere, lesbarere Syntax**: ARM-Templates sind verbose JSON-Dateien mit
  tief verschachtelten Strukturen. Bicep reduziert den Code typischerweise um
  50-70%.
- **Automatische Abhängigkeitserkennung**: Wenn eine Ressource eine andere
  referenziert (z. B. `appServicePlan.id`), erkennt Bicep die Abhängigkeit
  automatisch und erstellt die Ressourcen in der richtigen Reihenfolge. In
  ARM-Templates müsste man `dependsOn` manuell pflegen.
- **Modulare Struktur**: Bicep unterstützt Module, mit denen du Templates
  wiederverwendbar und organisiert halten kannst.
- **Direkte Integration in die Azure CLI**: `az deployment group create`
  akzeptiert `.bicep`-Dateien direkt — Bicep wird im Hintergrund zu ARM-JSON
  kompiliert. Kein separates Tool nötig.
- **What-If-Unterstützung**: `az deployment group what-if` zeigt vor dem
  Deployment eine Vorschau der Änderungen — ähnlich wie `terraform plan`.

Bicep vs. Terraform — wann was?

| Kriterium               | Bicep                          | Terraform                     |
|:-------------------------|:-------------------------------|:------------------------------|
| Cloud-Support            | Nur Azure                      | Multi-Cloud                   |
| State-Management         | Nicht nötig (Azure ist State)  | State-Datei erforderlich      |
| Tooling                  | In Azure CLI integriert        | Separates Tool                |
| Lernkurve                | Gering (Azure-nah)             | Mittel (eigene HCL-Sprache)   |
| Ökosystem                | Azure-Module                   | Riesiges Provider-Ökosystem   |

In diesem Lab erstellen wir ein Bicep-Template für einen App Service und
deployen es über eine Pipeline mit Validate-, What-If- und Deploy-Stages.

## Voraussetzungen

- Die Service Connection `azure-training-connection` aus Lab 05.
- Das Environment `dev` aus Lab 11.

## Aufgabenstellung

### Schritt 1: Bicep-Template erstellen

Erstelle ein `bicep/`-Verzeichnis im Repository:

```bash
mkdir -p bicep
```

Erstelle die Datei **bicep/main.bicep** — das Haupt-Template, das einen App
Service Plan und eine Web App definiert. Bicep-Dateien verwenden eine
deklarative Syntax, die deutlich kompakter ist als das JSON-Äquivalent in
ARM-Templates:

```bicep
// Parameter
@description('Name des Projekts')
param projectName string = 'training-app'

@description('Umgebung')
@allowed(['dev', 'staging', 'production'])
param environment string = 'dev'

@description('Azure-Region')
param location string = resourceGroup().location

@description('Eindeutiger Suffix')
param uniqueSuffix string

@description('App-Version')
param appVersion string = '1.0.0'

// Variablen
var appServicePlanName = 'plan-${projectName}-${environment}'
var webAppName = '${projectName}-${environment}-${uniqueSuffix}'
var tags = {
  Environment: environment
  Project: projectName
  ManagedBy: 'bicep'
}

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: 'F1'
    tier: 'Free'
  }
  kind: 'linux'
  properties: {
    reserved: true  // Für Linux erforderlich
  }
}

// Web App
resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: webAppName
  location: location
  tags: tags
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: 'NODE|20-lts'
      appSettings: [
        {
          name: 'ENVIRONMENT'
          value: environment
        }
        {
          name: 'APP_VERSION'
          value: appVersion
        }
      ]
    }
  }
}

// Outputs
output webAppName string = webApp.name
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'
output appServicePlanName string = appServicePlan.name
```

Gehe das Template Abschnitt für Abschnitt durch:

- **Parameter** (`param`): Definieren die Eingabewerte des Templates. Der
  Decorator `@description` fügt eine Beschreibung hinzu, `@allowed` schränkt
  die erlaubten Werte ein. Parameter mit Default-Wert (z. B.
  `projectName string = 'training-app'`) sind optional, Parameter ohne Default
  (z. B. `uniqueSuffix string`) müssen beim Deployment übergeben werden.
- **Variablen** (`var`): Berechnete Werte, die aus Parametern zusammengesetzt
  werden. String-Interpolation funktioniert mit `${...}` — ähnlich wie in
  JavaScript Template Literals. Die `tags`-Variable definiert ein Objekt, das
  allen Ressourcen zugewiesen wird, um sie als Bicep-verwaltet zu markieren.
- **App Service Plan** (`resource`): Definiert den Hosting-Plan. Beachte die
  Syntax: `resource <symbolischer-Name> '<Typ>@<API-Version>'`. Der
  symbolische Name (`appServicePlan`) wird nur innerhalb der Bicep-Datei
  verwendet, um auf die Ressource zu verweisen. `reserved: true` ist für
  Linux-Pläne erforderlich.
- **Web App**: Referenziert den App Service Plan über `appServicePlan.id`.
  Bicep erkennt diese Referenz automatisch und erstellt den Plan vor der
  Web App — ohne explizites `dependsOn`. Die `appSettings` konfigurieren
  Umgebungsvariablen, die die Anwendung zur Laufzeit lesen kann.
- **Outputs** (`output`): Werte, die nach dem Deployment angezeigt werden. Die
  URL wird aus der automatisch generierten Property `defaultHostName`
  zusammengesetzt.

Erstelle die Datei **bicep/dev.parameters.json** — die Parameter-Datei für die
Dev-Umgebung. Parameter-Dateien verwenden das ARM-Template-Format (JSON) und
erlauben es, Werte pro Umgebung zu definieren, ohne das Bicep-Template selbst
zu ändern:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "projectName": {
      "value": "training-app"
    },
    "environment": {
      "value": "dev"
    },
    "uniqueSuffix": {
      "value": "REPLACE_WITH_YOUR_SUFFIX"
    }
  }
}
```

Der Parameter `uniqueSuffix` muss vor dem Deployment mit deinem persönlichen
Kürzel ersetzt werden. In der Pipeline überschreiben wir ihn per
CLI-Parameter, sodass die Datei primär für lokale Tests dient.

### Schritt 2: Bicep lokal validieren (optional)

Bevor wir die Pipeline erstellen, kannst du das Bicep-Template lokal prüfen.
`az bicep build` kompiliert die `.bicep`-Datei zu ARM-JSON und meldet dabei
Syntaxfehler. `az deployment group what-if` zeigt eine Vorschau der
Änderungen, ohne sie tatsächlich durchzuführen:

```bash
# Bicep-Syntax prüfen (kompiliert zu ARM-JSON)
az bicep build --file bicep/main.bicep

# What-If Deployment (Vorschau der Änderungen)
az deployment group what-if \
  --resource-group rg-pipeline-training \
  --template-file bicep/main.bicep \
  --parameters bicep/dev.parameters.json \
  --parameters uniqueSuffix="<dein-kürzel>"
```

Die Ausgabe von `what-if` zeigt farbcodiert an, welche Ressourcen erstellt
(`+`), geändert (`~`) oder gelöscht (`-`) werden. Bei einem frischen
Deployment siehst du zwei `Create`-Einträge: einen App Service Plan und eine
Web App.

### Schritt 3: Pipeline mit Bicep Deployment

Jetzt erstellen wir eine Pipeline mit vier Stages, die den typischen
IaC-Workflow abbilden:

1. **Validate**: Prüft die Bicep-Syntax und führt eine Preflight-Validierung
   gegen Azure durch (ohne Ressourcen zu erstellen).
2. **What-If**: Zeigt an, welche Änderungen das Deployment durchführen würde.
3. **Deploy**: Führt das eigentliche Deployment durch.
4. **Verify**: Prüft, ob die Ressourcen tatsächlich erstellt wurden.

Ersetze den Inhalt von `azure-pipelines.yml`. **Wichtig**: Ersetze den
Platzhalter `<dein-kürzel>` mit deinem persönlichen Kürzel:

```yaml
trigger:
  branches:
    include:
      - main
  paths:
    include:
      - bicep/*

variables:
  azureSubscription: 'azure-training-connection'
  resourceGroup: 'rg-pipeline-training'
  uniqueSuffix: '<dein-kürzel>'

stages:
  # ===== Validate =====
  - stage: Validate
    displayName: 'Bicep Validate'
    jobs:
      - job: ValidateBicep
        displayName: 'Validieren'
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - script: |
              echo "=== Bicep Version ==="
              az bicep version
              echo ""
              echo "=== Bicep Build (Syntax-Check) ==="
              az bicep build --file bicep/main.bicep
              echo "Syntax OK!"
            displayName: 'Bicep Syntax prüfen'

          - task: AzureCLI@2
            displayName: 'Deployment validieren (Preflight)'
            inputs:
              azureSubscription: '$(azureSubscription)'
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              inlineScript: |
                echo "=== Preflight Validation ==="
                az deployment group validate \
                  --resource-group $(resourceGroup) \
                  --template-file bicep/main.bicep \
                  --parameters bicep/dev.parameters.json \
                  --parameters uniqueSuffix=$(uniqueSuffix) \
                  --parameters appVersion=1.0.$(Build.BuildId)

                echo "Validation erfolgreich!"

  # ===== What-If =====
  - stage: WhatIf
    displayName: 'What-If Analyse'
    dependsOn: Validate
    jobs:
      - job: WhatIfAnalysis
        displayName: 'What-If'
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - task: AzureCLI@2
            displayName: 'What-If Deployment'
            inputs:
              azureSubscription: '$(azureSubscription)'
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              inlineScript: |
                echo "=== What-If Analyse ==="
                echo "Zeigt an, welche Änderungen durchgeführt werden:"
                echo ""
                az deployment group what-if \
                  --resource-group $(resourceGroup) \
                  --template-file bicep/main.bicep \
                  --parameters bicep/dev.parameters.json \
                  --parameters uniqueSuffix=$(uniqueSuffix) \
                  --parameters appVersion=1.0.$(Build.BuildId) \
                  --no-pretty-print

  # ===== Deploy =====
  - stage: Deploy
    displayName: 'Bicep Deploy'
    dependsOn: WhatIf
    jobs:
      - deployment: DeployBicep
        displayName: 'Deploy Infrastruktur'
        pool:
          vmImage: 'ubuntu-latest'
        environment: 'dev'
        strategy:
          runOnce:
            deploy:
              steps:
                - checkout: self

                - task: AzureCLI@2
                  displayName: 'Bicep Deployment'
                  inputs:
                    azureSubscription: '$(azureSubscription)'
                    scriptType: 'bash'
                    scriptLocation: 'inlineScript'
                    inlineScript: |
                      echo "=== Bicep Deployment ==="
                      RESULT=$(az deployment group create \
                        --resource-group $(resourceGroup) \
                        --template-file bicep/main.bicep \
                        --parameters bicep/dev.parameters.json \
                        --parameters uniqueSuffix=$(uniqueSuffix) \
                        --parameters appVersion=1.0.$(Build.BuildId) \
                        --output json)

                      echo ""
                      echo "=== Deployment Outputs ==="
                      echo $RESULT | jq '.properties.outputs'

                      echo ""
                      WEB_APP_URL=$(echo $RESULT | jq -r '.properties.outputs.webAppUrl.value')
                      echo "Web App URL: $WEB_APP_URL"

  # ===== Verify =====
  - stage: Verify
    displayName: 'Verifizieren'
    dependsOn: Deploy
    jobs:
      - job: VerifyDeployment
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - task: AzureCLI@2
            displayName: 'Ressourcen prüfen'
            inputs:
              azureSubscription: '$(azureSubscription)'
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              inlineScript: |
                echo "=== Erstellte Ressourcen ==="
                az resource list \
                  --resource-group $(resourceGroup) \
                  --query "[?tags.ManagedBy=='bicep']" \
                  --output table

                echo ""
                echo "=== Deployment-Historie ==="
                az deployment group list \
                  --resource-group $(resourceGroup) \
                  --output table
```

Gehe die Pipeline Abschnitt für Abschnitt durch:

- **Trigger mit Path-Filter**: Die Pipeline wird nur ausgelöst, wenn sich
  Dateien unter `bicep/*` ändern. Änderungen an der Anwendung (z. B.
  `src/app.js`) lösen kein Infrastructure-Deployment aus.
- **Validate-Stage**: Führt zwei Prüfungen durch. `az bicep build` kompiliert
  das Template zu ARM-JSON und meldet Syntaxfehler — das funktioniert ohne
  Azure-Verbindung. `az deployment group validate` prüft zusätzlich gegen die
  Azure-API: existiert die Resource Group? Sind die Parameter gültig? Ist die
  SKU in der Region verfügbar? Diese Preflight-Validierung fängt Fehler ab,
  bevor Ressourcen erstellt werden.
- **What-If-Stage**: Zeigt eine Vorschau der Änderungen — welche Ressourcen
  werden erstellt, geändert oder gelöscht? Das ist das Bicep-Äquivalent zu
  `terraform plan`. In der Praxis würde man hier ein Approval Gate einbauen,
  damit ein Mensch die geplanten Änderungen prüfen kann. `--no-pretty-print`
  sorgt für eine kompaktere Ausgabe, die in Pipeline-Logs besser lesbar ist.
- **Deploy-Stage**: Führt das eigentliche Deployment durch. Als Deployment Job
  mit `environment: 'dev'` kann ein Approval Gate konfiguriert werden (Lab 12).
  `checkout: self` ist nötig, weil Deployment Jobs standardmäßig keinen
  Checkout des Repositorys durchführen. Die Outputs des Deployments (Web-App-
  Name, URL) werden per `jq` aus der JSON-Antwort extrahiert und im Log
  angezeigt.
- **Verify-Stage**: Prüft per Azure CLI, ob die Ressourcen mit dem Tag
  `ManagedBy=bicep` tatsächlich erstellt wurden, und zeigt die
  Deployment-Historie an. In der Praxis könnte man hier auch einen Health Check
  gegen die Web App ausführen.

### Schritt 4: Platzhalter ersetzen, committen und starten

Ersetze den Platzhalter in der Pipeline-Datei und in der Parameter-Datei mit
deinem persönlichen Kürzel:

```bash
# Platzhalter in Pipeline und Parameter-Datei ersetzen
SUFFIX=$(whoami | head -c 3)
sed -i "s/<dein-kürzel>/$SUFFIX/g" azure-pipelines.yml
sed -i "s/REPLACE_WITH_YOUR_SUFFIX/$SUFFIX/g" bicep/dev.parameters.json

git add bicep/main.bicep bicep/dev.parameters.json azure-pipelines.yml
git commit -m "Add Bicep IaC pipeline"
git push origin main
```

Beobachte den Pipeline-Run im Browser. Die vier Stages laufen nacheinander:

1. **Validate** prüft Syntax und Preflight — sollte in wenigen Sekunden
   durchlaufen.
2. **What-If** zeigt die geplanten Änderungen: `2 to create` (App Service Plan
   und Web App).
3. **Deploy** erstellt die Ressourcen und gibt die Outputs aus.
4. **Verify** listet die erstellten Ressourcen.

## Validierung

Prüfe per CLI, ob die Ressourcen korrekt erstellt wurden:

```bash
# Deployment-Liste prüfen
az deployment group list --resource-group rg-pipeline-training --output table

# Von Bicep erstellte Ressourcen anzeigen
az resource list \
  --resource-group rg-pipeline-training \
  --query "[?tags.ManagedBy=='bicep']" \
  --output table
```

Öffne im Browser das Build-Log und prüfe:

- Die **Validate-Stage** zeigt `Syntax OK!` und `Validation erfolgreich!`.
- Die **What-If-Stage** zeigt die geplanten Änderungen mit `Create`-Markierung.
- Die **Deploy-Stage** zeigt die Outputs mit Web-App-Name und URL.
- Die **Verify-Stage** listet die erstellten Ressourcen mit dem Tag
  `ManagedBy=bicep`.

## Erwartetes Ergebnis

**What-If Output:**

```
Resource changes: 2 to create
  + Microsoft.Web/serverfarms  plan-training-app-dev
  + Microsoft.Web/sites        training-app-dev-mmu
```

**Deployment Output:**

```
{
  "webAppName": { "value": "training-app-dev-mmu" },
  "webAppUrl": { "value": "https://training-app-dev-mmu.azurewebsites.net" },
  "appServicePlanName": { "value": "plan-training-app-dev" }
}
```

## Aufräumen

```bash
# Alle mit Bicep erstellten Ressourcen löschen
az resource list \
  --resource-group rg-pipeline-training \
  --query "[?tags.ManagedBy=='bicep'].id" -o tsv | \
  xargs -I {} az resource delete --ids {}

# Oder die gesamte Ressourcengruppe, wenn sie nur Bicep-Ressourcen enthält
# az group delete --name rg-training-app-dev --yes
```

## Tipps und Troubleshooting

- **"Bicep not found"**: Bicep ist seit Azure CLI 2.20 integriert. Update mit
  `az upgrade`. Auf Microsoft-hosted Agents ist Bicep immer verfügbar.
- **What-If zeigt "NoChange"**: Die Ressourcen existieren bereits im
  gewünschten Zustand. Das ist das erwartete Verhalten bei einem
  erneuten Lauf ohne Code-Änderungen.
- **Parameter-Reihenfolge**: CLI-Parameter (`--parameters uniqueSuffix=...`)
  überschreiben Werte aus der Parameter-Datei. So kannst du die Build-Nummer
  dynamisch setzen, ohne die Datei zu ändern.
- **Bicep vs. Terraform**: Bicep ist Azure-nativ und braucht kein
  State-Management — Azure selbst ist der State. Terraform ist
  Cloud-agnostisch und hat ein größeres Ökosystem. Für reine Azure-Projekte
  ist Bicep oft die einfachere Wahl.
- **Modulare Bicep**: Für größere Projekte kannst du Bicep-Module verwenden
  (`module` Keyword), um Templates wiederverwendbar zu machen. Ein Modul ist
  eine separate `.bicep`-Datei, die wie eine Funktion aufgerufen wird.
- **Deployment Scopes**: Bicep unterstützt Deployments auf verschiedenen
  Ebenen: Resource Group, Subscription, Management Group und Tenant. In diesem
  Lab deployen wir auf Resource-Group-Ebene (`az deployment group create`).
  Für übergreifende Ressourcen (z. B. Resource Groups selbst) verwendet man
  `az deployment sub create`.
