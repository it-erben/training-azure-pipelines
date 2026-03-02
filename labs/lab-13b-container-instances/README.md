# Lab 13b: Docker-Container auf Azure Container Instances deployen

## Hintergrund

In Lab 08 haben wir ein Docker-Image gebaut und in eine Azure Container Registry
(ACR) gepusht. In Lab 13 haben wir eine Anwendung per ZIP-Paket auf einen App
Service deployt. Aber wo laufen die Docker-Images eigentlich? In diesem Lab
schließen wir die Lücke: Wir deployen das Docker-Image aus Lab 08 auf **Azure
Container Instances (ACI)** - den einfachsten Weg, einen Container in Azure zu
starten.

ACI ist ein serverloser Container-Dienst: Kein Cluster, kein App Service Plan,
keine VM - du gibst ein Image an und Azure startet es. Die Abrechnung erfolgt
pro Sekunde nach tatsächlich genutzter CPU und RAM. Das macht ACI ideal für:

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

ACI kann Images aus ACR, Docker Hub oder privaten Registries ziehen. Wir nutzen
die ACR aus Lab 08 und authentifizieren uns mit den Admin-Credentials, die wir
dort aktiviert haben (`--admin-enabled true`).

## Voraussetzungen

- Die **ACR aus Lab 08** mit dem Image `hello-pipeline`. Falls du die ACR nach
  Lab 08 gelöscht hast, erstelle sie neu (siehe Lab 08, Schritt 1-3) und führe
  die Pipeline einmal aus, damit das Image in der Registry liegt.
- Die **Service Connections** `acr-training-connection` (Lab 08) und
  `azure-training-connection` (Lab 05).
- Das **Environment** `dev` aus Lab 11.

## Aufgabenstellung

### Schritt 1: Pipeline mit Build und ACI-Deployment

Wir erstellen eine Pipeline mit drei Stages: **Build** baut das Docker-Image und
pusht es in die ACR, **Deploy** erstellt eine Container Instance mit dem Image,
und **Verify** prüft, ob der Container läuft und erreichbar ist.

Ersetze den Inhalt von `azure-pipelines.yml`. **Wichtig**: Ersetze dabei den
Platzhalter `<dein-acr-name>` an beiden Stellen mit deinem tatsächlichen
ACR-Namen (den du in Lab 08 generiert hast):

```yaml
trigger:
  branches:
    include:
      - master

variables:
  azureSubscription: 'azure-training-connection'
  # Ersetze mit deinem ACR-Namen
  acrName: '<dein-acr-name>'
  acrLoginServer: '<dein-acr-name>.azurecr.io'
  imageName: 'hello-pipeline'
  imageTag: '$(Build.BuildNumber)'
  containerName: 'hello-pipeline-aci'
  dnsLabel: 'hello-pipeline-$(Build.BuildId)'

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
                      # ACR-Credentials holen
                      ACR_PASSWORD=$(az acr credential show \
                        --name $(acrName) \
                        --query "passwords[0].value" -o tsv)

                      # Bestehenden Container löschen (falls vorhanden)
                      az container delete \
                        --name $(containerName) \
                        --resource-group rg-pipeline-training \
                        --yes 2>/dev/null || true

                      # Container erstellen
                      az container create \
                        --name $(containerName) \
                        --resource-group rg-pipeline-training \
                        --image $(acrLoginServer)/$(imageName):$(imageTag) \
                        --registry-login-server $(acrLoginServer) \
                        --registry-username $(acrName) \
                        --registry-password "$ACR_PASSWORD" \
                        --dns-name-label $(dnsLabel) \
                        --ports 80 \
                        --os-type Linux \
                        --cpu 1 \
                        --memory 0.5 \
                        --output table

                      echo ""
                      echo "Container erstellt. FQDN:"
                      az container show \
                        --name $(containerName) \
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
                echo "=== Container Status ==="
                az container show \
                  --name $(containerName) \
                  --resource-group rg-pipeline-training \
                  --query "{name:name, state:instanceView.state, image:containers[0].image, fqdn:ipAddress.fqdn}" \
                  --output table

                FQDN=$(az container show \
                  --name $(containerName) \
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

Gehe die Pipeline Abschnitt für Abschnitt durch:

- **Variablen**: `acrName` und `acrLoginServer` verweisen auf die ACR aus
  Lab 08. `containerName` ist der Name der Container Instance in Azure.
  `dnsLabel` erzeugt mit `$(Build.BuildId)` bei jedem Run einen eindeutigen
  DNS-Namen - das ist nötig, weil ACI bestehende Container nicht in-place
  updaten kann und der alte Container vor dem Erstellen eines neuen gelöscht
  wird.
- **Build-Stage**: Identisch mit Lab 08 - der `Docker@2`-Task baut das Image
  aus dem Dockerfile und pusht es mit der Build-Nummer und `latest` als Tags in
  die ACR.
- **Deploy-Stage**: Ein Deployment Job (wie Lab 13) mit `environment: 'dev'`,
  damit die Deployment-Historie in Azure DevOps sichtbar ist. Der
  `AzureCLI@2`-Task führt drei Schritte aus:
    1. **ACR-Credentials holen**: `az acr credential show` liest das
       Admin-Passwort der ACR aus. Das funktioniert, weil wir in Lab 08
       `--admin-enabled true` gesetzt haben.
    2. **Alten Container löschen**: `az container delete ... || true` entfernt
       einen eventuell vorhandenen Container gleichen Namens. Das `|| true`
       verhindert einen Fehler, falls kein Container existiert.
    3. **Container erstellen**: `az container create` startet eine neue Container
       Instance mit dem Image aus der ACR. `--dns-name-label` weist einen
       öffentlichen DNS-Namen zu, `--ports 80` öffnet den HTTP-Port, und
       `--cpu 1 --memory 0.5` begrenzt die Ressourcen (1 vCPU, 0,5 GB RAM).
- **Verify-Stage**: Ein normaler Job (kein Deployment Job), der den
  Container-Status abfragt und einen HTTP Health Check durchführt. Nach 15
  Sekunden Wartezeit wird per `curl` geprüft, ob der Container auf HTTP 200
  antwortet.

> **Warum `AzureCLI@2` statt eines speziellen Tasks?** Es gibt keinen
> eingebauten ACI-Task in Azure Pipelines. `az container create` über den
> `AzureCLI@2`-Task ist der empfohlene Weg und zeigt, wie CLI-basierte
> Deployments in Pipelines funktionieren.

### Schritt 2: Committen und Pipeline starten

Nachdem du den ACR-Namen in der Pipeline-Datei eingesetzt hast, committe und
pushe:

```bash
git add azure-pipelines.yml
git commit -m "Add ACI deployment pipeline"
git push origin master
```

Beim ersten Lauf mit der Service Connection und dem Environment muss die Nutzung
möglicherweise einmalig genehmigt werden. Öffne den Pipeline-Run im Browser -
du siehst eine Meldung wie *"This pipeline needs permission to access a resource
before this run can continue"*. Klicke auf **"View"** und dann auf
**"Permit"**.

### Schritt 3: Container im Browser prüfen

Nach erfolgreichem Deployment findest du den FQDN (Fully Qualified Domain Name)
des Containers im Log der Deploy- oder Verify-Stage. Du kannst ihn auch
manuell abfragen:

**Bash:**

```bash
az container show \
  --name hello-pipeline-aci \
  --resource-group rg-pipeline-training \
  --query "ipAddress.fqdn" -o tsv
```

**PowerShell:**

```powershell
az container show `
  --name hello-pipeline-aci `
  --resource-group rg-pipeline-training `
  --query "ipAddress.fqdn" -o tsv
```

Öffne `http://<fqdn>` im Browser - du solltest die nginx-Willkommensseite aus
dem Docker-Image sehen.

Im **Azure Portal** kannst du unter **Container Instances** deinen Container
inspizieren:

- **Containers > Logs**: Stdout/Stderr des laufenden Containers
- **Containers > Events**: Start- und Pull-Events
- **Monitoring > Metrics**: CPU- und Speicherverbrauch

## Aufräumen

Der ACI-Container verursacht laufende Kosten, solange er läuft. Lösche ihn nach
dem Lab:

**Bash:**

```bash
az container delete \
  --name hello-pipeline-aci \
  --resource-group rg-pipeline-training \
  --yes
```

**PowerShell:**

```powershell
az container delete `
  --name hello-pipeline-aci `
  --resource-group rg-pipeline-training `
  --yes
```

Die ACR kann bestehen bleiben, falls du weitere Labs mit Docker-Images planst.
Falls du sie nicht mehr benötigst, kannst du sie löschen (siehe Lab 08,
Aufräumen).
