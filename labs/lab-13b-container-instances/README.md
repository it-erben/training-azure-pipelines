# Lab 13b: Docker-Container auf Azure Container Instances deployen

## Hintergrund

In Lab 13 haben wir eine Anwendung per ZIP-Paket auf einen App Service deployt.
Aber was, wenn wir unsere Anwendung als Docker-Container betreiben wollen? In
diesem Lab bauen wir ein Docker-Image, pushen es in eine **Azure Container
Registry (ACR)** und deployen es auf **Azure Container Instances (ACI)** - den
einfachsten Weg, einen Container in Azure zu starten.

**Azure Container Instances (ACI)** ist ein serverloser Container-Dienst: Kein
Cluster, kein App Service Plan, keine VM - du gibst ein Image an und Azure
startet es. Die Abrechnung erfolgt pro Sekunde nach tatsächlich genutzter CPU
und RAM. Das macht ACI ideal für:

- **Dev/Test**: Schnell einen Container starten und wieder löschen
- **Batch-Jobs**: Einmalige Verarbeitungsaufgaben, die nach Abschluss gestoppt
  werden
- **Einfache Microservices**: Einzelne Container mit wenig Orchestrierungsbedarf

Der Unterschied zu den anderen Deployment-Optionen:

- **App Service** (Lab 13): PaaS für Webanwendungen, ZIP- oder
  Container-Deployment, mit Scaling, Slots, Custom Domains
- **ACI** (dieses Lab): Einzelne Container, schnell gestartet, Pay-per-Second
- **AKS** (Azure Kubernetes Service): Container-Orchestrierung für komplexe
  Microservice-Architekturen

## Voraussetzungen

- Die **Service Connection** `azure-training-connection` (Lab 05).
- Das **Environment** `dev` aus Lab 11.

## Aufgabenstellung

### Schritt 1: Neues Repository erstellen

Erstelle in deinem Azure DevOps Projekt ein neues Git-Repository für dieses Lab:

1. Gehe zu **Repos**, dann oben den **Dropdown** öffnen mit dem aktuellen
   Repo-Namen.
2. Klicke auf **"New Repository"**.
3. Repository-Name: `aci-demo`.
4. Klicke auf **"Create"**.
5. Klicke auf **"Clone"**, kopiere die URL und klone das neue Repository lokal:

```bash
git clone <url-des-neuen-repos>
cd aci-demo
```

### Schritt 2: Azure Container Registry erstellen

ACR-Namen müssen global eindeutig sein und dürfen nur Kleinbuchstaben und
Zahlen enthalten (keine Bindestriche oder Unterstriche). Wir generieren einen
eindeutigen Namen mit deinen Initialien:

**Bash:**

```bash
# Eindeutigen ACR-Namen generieren
INITIALS="deine_initialien_kleingeschrieben"
ACR_NAME="acraci$INITIALS$RANDOM"
echo "ACR Name: $ACR_NAME"

# ACR erstellen (Basic SKU: günstigste Option)
az acr create \
  --name $ACR_NAME \
  --resource-group rg-pipeline-training \
  --location westeurope \
  --sku Basic \
  --admin-enabled true \
  --output table
```

**PowerShell:**

```powershell
# Eindeutigen ACR-Namen generieren
$INITIALS = "deine_initialien_kleingeschrieben"
$ACR_NAME = "acraci$INITIALS$(Get-Random -Maximum 32768)"
echo "ACR Name: $ACR_NAME"

# ACR erstellen (Basic SKU: günstigste Option)
az acr create `
  --name $ACR_NAME `
  --resource-group rg-pipeline-training `
  --location westeurope `
  --sku Basic `
  --admin-enabled true `
  --output table
```

### Schritt 3: Anwendung und Dockerfile erstellen

Erstelle die Datei **index.html** im Repository-Wurzelverzeichnis:

```html
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="UTF-8">
  <title>ACI Demo</title>
</head>
<body>
  <h1>Hello from Azure Container Instances!</h1>
  <p>Dieses Image wurde per Azure Pipeline gebaut und auf ACI deployt.</p>
</body>
</html>
```

Erstelle die Datei **Dockerfile**:

```dockerfile
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s \
  CMD wget -q --spider http://localhost/ || exit 1
```

Erstelle außerdem eine **.dockerignore**-Datei, um unnötige Dateien vom
Docker-Build-Kontext auszuschließen:

```
.git
*.md
azure-pipelines.yml
```

### Schritt 4: Service Connection für ACR erstellen

Damit die Pipeline Images in die ACR pushen kann, braucht sie eine
authentifizierte Verbindung. Wir erstellen eine **Docker Registry Service
Connection** in Azure DevOps:

1. Gehe zu **Project Settings > Service connections**.
2. Klicke auf **"New service connection"**.
3. Wähle **"Docker Registry"**.
4. Registry type: **"Azure Container Registry"**.
5. Authentication Type: **"Service Principal"**.
6. Subscription: Wähle die Trainings-Subscription.
7. Azure Container Registry: Wähle deine soeben erstellte ACR aus der
   Dropdown-Liste.
8. Service Connection Name: `acr-aci-connection`.
9. Setze den Haken bei **"Grant access permission to all pipelines"**.
10. Klicke auf **"Save"**.

### Schritt 5: Pipeline mit Build und ACI-Deployment

Wir erstellen eine Pipeline mit drei Stages: **Build** baut das Docker-Image und
pusht es in die ACR, **Deploy** erstellt eine Container Instance mit dem Image,
und **Verify** prüft, ob der Container läuft und erreichbar ist.

Erstelle die Datei `azure-pipelines.yml`. **Wichtig**: Ersetze dabei den
Platzhalter `<dein-acr-name>` an beiden Stellen mit deinem tatsächlichen
ACR-Namen (den du in Schritt 2 generiert hast):

```yaml
trigger:
  branches:
    include:
      - main
      - master

variables:
  azureSubscription: 'azure-training-connection'
  # Ersetze mit deinem ACR-Namen aus Schritt 2
  acrName: '<dein-acr-name>'
  acrLoginServer: '<dein-acr-name>.azurecr.io'
  imageName: 'aci-demo'
  imageTag: '$(Build.BuildNumber)'
  containerPrefix: 'aci-demo'

stages:
  # ===== Build =====
  - stage: Build
    displayName: 'Build Docker Image'
    jobs:
      - job: DockerBuild
        displayName: 'Build and Push'
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          # ACR-Login für den Cache-Pull
          - task: Docker@2
            displayName: 'ACR Login'
            inputs:
              containerRegistry: 'acr-aci-connection'
              command: 'login'

          # Vorheriges Image als Cache-Quelle pullen
          - script: |
              docker pull $(acrLoginServer)/$(imageName):latest || true
            displayName: 'Cache: Vorheriges Image pullen'

          - script: |
              docker build \
                --cache-from=$(acrLoginServer)/$(imageName):latest \
                -t $(acrLoginServer)/$(imageName):$(imageTag) \
                -t $(acrLoginServer)/$(imageName):latest \
                .
            displayName: 'Docker Build (mit Layer Cache)'

          - script: |
              docker push $(acrLoginServer)/$(imageName):$(imageTag)
              docker push $(acrLoginServer)/$(imageName):latest
            displayName: 'Docker Push'

  # ===== Deploy to ACI =====
  - stage: Deploy
    displayName: 'Deploy to ACI'
    dependsOn: Build
    jobs:
      - deployment: DeployACI
        displayName: 'Deploy Container'
        pool:
          vmImage: 'ubuntu-latest'
        environment: 'dev'
        strategy:
          runOnce:
            deploy:
              steps:
                - task: AzureCLI@2
                  displayName: 'Container auf ACI deployen'
                  inputs:
                    azureSubscription: '$(azureSubscription)'
                    scriptType: 'bash'
                    scriptLocation: 'inlineScript'
                    inlineScript: |
                      # Projektname in ACI-konformen Slug umwandeln
                      RAW_PROJECT="$(System.TeamProject)"
                      PROJECT_SLUG=$(echo "$RAW_PROJECT" \
                        | tr '[:upper:]' '[:lower:]' \
                        | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
                      PROJECT_SLUG="${PROJECT_SLUG:0:20}"

                      CONTAINER_NAME="$(containerPrefix)-${PROJECT_SLUG}"
                      DNS_LABEL="${CONTAINER_NAME}-$(Build.BuildId)"
                      echo "Container-Name: $CONTAINER_NAME"
                      echo "DNS-Label:      $DNS_LABEL"

                      # ACR-Credentials holen
                      ACR_PASSWORD=$(az acr credential show \
                        --name $(acrName) \
                        --query "passwords[0].value" -o tsv)

                      # Bestehenden Container löschen (falls vorhanden)
                      az container delete \
                        --name "$CONTAINER_NAME" \
                        --resource-group rg-pipeline-training \
                        --yes 2>/dev/null || true

                      # Auf asynchrone Löschung warten, damit create nicht kollidiert
                      for i in {1..24}; do
                        if ! az container show \
                          --name "$CONTAINER_NAME" \
                          --resource-group rg-pipeline-training \
                          --output none 2>/dev/null; then
                          echo "Vorheriger Container ist gelöscht."
                          break
                        fi
                        echo "Container wird noch gelöscht... warte 5s"
                        sleep 5
                      done

                      # Container erstellen
                      az container create \
                        --name "$CONTAINER_NAME" \
                        --resource-group rg-pipeline-training \
                        --image $(acrLoginServer)/$(imageName):$(imageTag) \
                        --registry-login-server $(acrLoginServer) \
                        --registry-username $(acrName) \
                        --registry-password "$ACR_PASSWORD" \
                        --dns-name-label "$DNS_LABEL" \
                        --ports 80 \
                        --os-type Linux \
                        --cpu 1 \
                        --memory 0.5 \
                        --output table

                      echo ""
                      echo "Container erstellt. FQDN:"
                      az container show \
                        --name "$CONTAINER_NAME" \
                        --resource-group rg-pipeline-training \
                        --query "ipAddress.fqdn" -o tsv

  # ===== Verify =====
  - stage: Verify
    displayName: 'Container prüfen'
    dependsOn: Deploy
    jobs:
      - job: VerifyContainer
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - task: AzureCLI@2
            displayName: 'Container-Status und Health Check'
            inputs:
              azureSubscription: '$(azureSubscription)'
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              inlineScript: |
                RAW_PROJECT="$(System.TeamProject)"
                PROJECT_SLUG=$(echo "$RAW_PROJECT" \
                  | tr '[:upper:]' '[:lower:]' \
                  | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
                PROJECT_SLUG="${PROJECT_SLUG:0:20}"
                CONTAINER_NAME="$(containerPrefix)-${PROJECT_SLUG}"

                echo "=== Container Status ==="
                az container show \
                  --name "$CONTAINER_NAME" \
                  --resource-group rg-pipeline-training \
                  --query "{name:name, state:instanceView.state, image:containers[0].image, fqdn:ipAddress.fqdn}" \
                  --output table

                FQDN=$(az container show \
                  --name "$CONTAINER_NAME" \
                  --resource-group rg-pipeline-training \
                  --query "ipAddress.fqdn" -o tsv)

                echo ""
                echo "=== Health Check ==="
                echo "Warte 15 Sekunden auf Container-Start..."
                sleep 15
                HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://$FQDN")
                if [ "$HTTP_STATUS" = "200" ]; then
                  echo "HTTP $HTTP_STATUS - Container ist erreichbar unter http://$FQDN"
                else
                  echo "WARNUNG: HTTP $HTTP_STATUS - Container antwortet nicht wie erwartet"
                fi
```

### Schritt 6: Committen und Pipeline starten

Committe alle Dateien und pushe:

```bash
git add index.html Dockerfile .dockerignore azure-pipelines.yml
git commit -m "Add ACI deployment pipeline"
git push
```

Erstelle anschließend die Pipeline in Azure DevOps:

1. Gehe zu **Pipelines > New pipeline**.
2. Wähle **"Azure Repos Git"**.
3. Wähle das Repository **"aci-demo"**.
4. Wähle **"Existing Azure Pipelines YAML file"** und wähle
   `/azure-pipelines.yml`.
5. Klicke auf **"Run"**.

Beim ersten Lauf mit den Service Connections und dem Environment muss die Nutzung
möglicherweise einmalig genehmigt werden. Öffne den Pipeline-Run im Browser -
du siehst eine Meldung wie *"This pipeline needs permission to access a resource
before this run can continue"*. Klicke auf **"View"** und dann auf
**"Permit"**.

### Schritt 7: Container im Browser prüfen

Nach erfolgreichem Deployment findest du den FQDN (Fully Qualified Domain Name)
des Containers im Log der Deploy- oder Verify-Stage.

Öffne `http://<fqdn>` im Browser - du solltest die HTML-Seite mit "Hello from
Azure Container Instances!" sehen.

Im **Azure Portal** kannst du unter **Container Instances** deinen Container
inspizieren:

- **Containers > Logs**: Stdout/Stderr des laufenden Containers
- **Containers > Events**: Start- und Pull-Events
- **Monitoring > Metrics**: CPU- und Speicherverbrauch
