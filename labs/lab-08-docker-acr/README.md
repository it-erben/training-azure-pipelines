# Lab 08: Docker-Images bauen und in ACR pushen

## Hintergrund

Azure Container Registry (ACR) ist ein verwalteter Docker-Registry-Dienst auf
Basis der Open-Source Docker Registry. In CI/CD-Pipelines ist es üblich,
Docker-Images als Build-Artefakte zu erzeugen und in eine Registry zu pushen,
von wo aus sie in verschiedene Umgebungen deployt werden können. Im Gegensatz zu
den Pipeline Artifacts aus Lab 07, die nur innerhalb von Azure Pipelines
verfügbar sind, können Docker-Images aus einer ACR von jedem Dienst gezogen
werden, der Docker unterstützt - z.B. Azure App Service, Azure Kubernetes
Service (AKS) oder Azure Container Instances (ACI).

Azure Pipelines bietet den `Docker@2`-Task, der das Bauen und Pushen von Images
in einem Schritt vereinfacht. Er übernimmt die Authentifizierung gegenüber der
Registry über eine Service Connection, sodass keine Credentials im
Pipeline-Code auftauchen. Alternativ kannst du auch direkt `docker build` und
`docker push` Befehle verwenden, musst dann aber die Authentifizierung selbst
handhaben.

In diesem Lab erstellen wir eine ACR, schreiben ein Multi-Stage Dockerfile und
bauen eine Pipeline, die das Image automatisch baut, in die ACR pusht und
anschließend verifiziert.

## Aufgabenstellung

### Schritt 1: Azure Container Registry erstellen

ACR-Namen müssen global eindeutig sein und dürfen nur Kleinbuchstaben und
Zahlen enthalten (keine Bindestriche oder Unterstriche). Wir generieren einen
eindeutigen Namen mit deinen Initialien:

**Bash:**

```bash
# Eindeutigen ACR-Namen generieren
INITIALS="deine_initialien_kleingeschrieben"
ACR_NAME="acrtraining$INITIALS$RANDOM"
echo "ACR Name: $ACR_NAME"
```

**PowerShell:**

```powershell
# Eindeutigen ACR-Namen generieren
$INITIALS = "deine_initialien_kleingeschrieben"
$ACR_NAME = "acrtraining$INITIALS$(Get-Random -Maximum 32768)"
echo "ACR Name: $ACR_NAME"
```

**Bash:**

```bash
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
# ACR erstellen (Basic SKU: günstigste Option)
az acr create `
  --name $ACR_NAME `
  --resource-group rg-pipeline-training `
  --location westeurope `
  --sku Basic `
  --admin-enabled true `
  --output table
```

Die **Basic SKU** reicht für Trainings- und Entwicklungszwecke aus (ca. 5
EUR/Monat, 10 GB Speicher). `--admin-enabled true` aktiviert einen einfachen
Zugriff per Benutzername/Passwort, was für Tests praktisch ist. In Produktion
sollte man stattdessen Service Principals mit RBAC verwenden.

### Schritt 2: Dockerfile erstellen

Wir verwenden einen **Multi-Stage Build**, um die Image-Größe zu minimieren. Im
ersten Stage wird die Anwendung mit Node.js gebaut, im zweiten Stage werden nur
die fertigen Dateien in ein schlankes nginx-Image kopiert. Das Ergebnis ist ein
Production-Image, das nur wenige MB groß ist und keinen Node.js-Overhead
enthält.

Erstelle die Datei **Dockerfile** im Wurzelverzeichnis deines
`hello-pipeline`-Repositorys:

```dockerfile
# Multi-Stage Build
FROM node:20-alpine AS build
WORKDIR /app
COPY package.json ./
COPY src/ ./src/
COPY index.html ./
RUN mkdir -p dist && cp src/*.js dist/ && cp index.html dist/

# Production Image
FROM nginx:alpine
COPY --from=build /app/dist/ /usr/share/nginx/html/
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s \
  CMD wget -q --spider http://localhost/ || exit 1
```

Das Dockerfile besteht aus zwei Stages:

- **Build-Stage** (`FROM node:20-alpine AS build`): Verwendet ein schlankes
  Node.js-Alpine-Image, kopiert die Quelldateien und baut die Anwendung. Dieses
  Zwischen-Image wird nur während des Builds verwendet und ist im fertigen
  Image nicht enthalten.
- **Production-Stage** (`FROM nginx:alpine`): Startet von einem reinen
  nginx-Alpine-Image und kopiert mit `COPY --from=build` nur die fertigen
  Dateien aus dem Build-Stage. `EXPOSE 80` dokumentiert den Port (ist aber nur
  informativ). Der `HEALTHCHECK` prüft alle 30 Sekunden, ob der nginx-Server
  antwortet - das wird von Orchestrierungs-Tools wie Kubernetes oder App Service
  genutzt, um unhealthy Container automatisch neu zu starten.

Erstelle außerdem eine **.dockerignore**-Datei, um unnötige Dateien vom
Docker-Build-Kontext auszuschließen. Das beschleunigt den Build, da Docker
weniger Daten an den Build-Daemon senden muss:

```
node_modules
test
test-results
.git
*.md
azure-pipelines.yml
```

### Schritt 3: Service Connection für ACR erstellen

Damit die Pipeline Images in die ACR pushen kann, braucht sie eine
authentifizierte Verbindung. Wir erstellen eine **Docker Registry Service
Connection** in Azure DevOps:

1. Gehe zu **Project Settings > Service connections**.
2. Klicke auf **"New service connection"**.
3. Wähle **"Docker Registry"**.
4. Registry type: **"Azure Container Registry"**.
5. Authentication Type: **"Service Principal"**.
6. Subscription: Wähle die Trainings-Subscription.
7. Azure Container Registry: Wähle deine ACR aus der Dropdown-Liste.
8. Service Connection Name: `acr-training-connection`.
9. Setze den Haken bei **"Grant access permission to all pipelines"**.
10. Klicke auf **"Save"**.

Azure DevOps erstellt dabei automatisch einen Service Principal in Azure AD und
weist ihm die Rolle **AcrPush** auf der ACR zu. Diese Rolle erlaubt das Pushen
und Pullen von Images, aber keine administrativen Änderungen an der Registry.

### Schritt 4: Pipeline mit Docker-Build

Jetzt erstellen wir eine Pipeline mit zwei Stages: eine zum Bauen und Pushen
des Docker-Images und eine zum Verifizieren, dass das Image in der ACR
angekommen ist.

Ersetze den Inhalt von `azure-pipelines.yml`. **Wichtig**: Ersetze dabei den
Platzhalter `<dein-acr-name>` an beiden Stellen mit deinem tatsächlichen
ACR-Namen (den du in Schritt 1 generiert hast):

```yaml
trigger:
  branches:
    include:
      - master

variables:
  # Ersetze mit deinem ACR-Namen
  acrName: '<dein-acr-name>'
  acrLoginServer: '<dein-acr-name>.azurecr.io'
  imageName: 'hello-pipeline'
  # Tag mit Build-Nummer und 'latest'
  imageTag: '$(Build.BuildNumber)'

stages:
  - stage: Build
    displayName: 'Build Docker Image'
    jobs:
      - job: DockerBuild
        displayName: 'Build and Push'
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - script: |
              echo "=== Docker Build Info ==="
              echo "Registry: $(acrLoginServer)"
              echo "Image:    $(imageName)"
              echo "Tag:      $(imageTag)"
              docker version
            displayName: 'Build-Info anzeigen'

          # Docker@2 Task (empfohlen)
          - task: Docker@2
            displayName: 'Docker Build and Push'
            inputs:
              containerRegistry: 'acr-training-connection'
              repository: '$(imageName)'
              command: 'buildAndPush'
              Dockerfile: '**/Dockerfile'
              tags: |
                $(imageTag)
                latest

          # Image-Größe und Details anzeigen
          - script: |
              echo "=== Gepushte Images ==="
              echo "$(acrLoginServer)/$(imageName):$(imageTag)"
              echo "$(acrLoginServer)/$(imageName):latest"
            displayName: 'Push-Ergebnis anzeigen'

  - stage: Verify
    displayName: 'Verify Image'
    dependsOn: Build
    jobs:
      - job: VerifyImage
        displayName: 'Image verifizieren'
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          # Bei ACR anmelden und Image prüfen
          - task: AzureCLI@2
            displayName: 'Image in ACR prüfen'
            inputs:
              azureSubscription: 'azure-training-connection'
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              inlineScript: |
                echo "=== ACR Repository Tags ==="
                az acr repository show-tags \
                  --name $(acrName) \
                  --repository $(imageName) \
                  --output table

                echo ""
                echo "=== Image Manifest ==="
                az acr manifest list-metadata \
                  --registry $(acrName) \
                  --name $(imageName) \
                  --output table
```

Gehe die Pipeline Abschnitt für Abschnitt durch:

- **Variablen**: `acrName` und `acrLoginServer` definieren die Registry-
  Koordinaten. `imageName` ist der Repository-Name innerhalb der ACR (eine ACR
  kann mehrere Repositories enthalten). `imageTag` verwendet die Build-Nummer
  als eindeutigen Tag - so kann jeder Build eindeutig identifiziert werden.
- **Build-Stage**: Der `Docker@2`-Task mit dem Command `buildAndPush` führt
  `docker build` und `docker push` in einem Schritt aus. Er authentifiziert
  sich über die Service Connection `acr-training-connection` und tagged das
  Image sowohl mit der Build-Nummer als auch mit `latest`. Die Option
  `Dockerfile: '**/Dockerfile'` sucht das Dockerfile automatisch im
  Repository - der Glob-Pattern `**/` durchsucht alle Unterverzeichnisse.
- **Verify-Stage**: Verwendet den `AzureCLI@2`-Task mit der Azure Resource
  Manager Service Connection, um per `az acr` CLI die Tags und Manifeste in
  der ACR abzufragen. So wird geprüft, ob das Image tatsächlich angekommen ist.
  Beachte, dass hier `azure-training-connection` (ARM) statt
  `acr-training-connection` (Docker) verwendet wird, da der `AzureCLI@2`-Task
  eine ARM-Verbindung erwartet.

### Schritt 5: Committen und pushen

Nachdem du den ACR-Namen gesetzt hast, kannst du committen und pushen:

```bash
git add Dockerfile .dockerignore azure-pipelines.yml
git commit -m "Add Docker build pipeline with ACR"
git push origin master
```

Beim ersten Lauf der Pipeline mit der neuen Service Connection muss die Nutzung möglicherweise
einmalig genehmigt werden. Öffne den Pipeline-Run im Browser - du siehst eine
Meldung wie *"This pipeline needs permission to access a resource before this
run can continue"*. Klicke auf **"View"** und dann auf **"Permit"**.

### Schritt 6: Image lokal testen (optional)

Lade dir das neue Image aus ACR
herunter und teste:

**Bash:**

```bash
# ACR-Credentials holen
ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --query "passwords[0].value" -o tsv)

# Einloggen
docker login $ACR_NAME.azurecr.io -u $ACR_NAME -p $ACR_PASSWORD

# Image pullen und starten
docker pull $ACR_NAME.azurecr.io/hello-pipeline:latest
docker run -d -p 8080:80 --name hello-test $ACR_NAME.azurecr.io/hello-pipeline:latest

# Warten, bis der Container gestartet wurde
sleep 20

# Testen
curl http://localhost:8080

# Container stoppen und entfernen
docker stop hello-test && docker rm hello-test
```

**PowerShell:**

```powershell
# ACR-Credentials holen
$ACR_PASSWORD = (az acr credential show --name $ACR_NAME --query "passwords[0].value" -o tsv)

# Einloggen
docker login $ACR_NAME.azurecr.io -u $ACR_NAME -p $ACR_PASSWORD

# Image pullen und starten
docker pull $ACR_NAME.azurecr.io/hello-pipeline:latest
docker run -d -p 8080:80 --name hello-test $ACR_NAME.azurecr.io/hello-pipeline:latest

# Warten, bis der Container gestartet wurde
Start-Sleep -Seconds 20
# Testen
Invoke-RestMethod http://localhost:8080

# Container stoppen und entfernen
docker stop hello-test
docker rm hello-test
```

Du solltest die `index.html` aus dem Repository sehen,
ausgeliefert von nginx im Docker-Container.

## Aufräumen

Die ACR verursacht laufende Kosten (Basic SKU ca. 5 EUR/Monat). Lösche sie nach
dem Lab, wenn du sie nicht mehr benötigst:

```bash
# ACR löschen
az acr delete --name $ACR_NAME --resource-group rg-pipeline-training --yes
```

Die Service Connection `acr-training-connection` kannst du ebenfalls löschen.
