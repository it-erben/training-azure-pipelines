# Lab 13: Deployment nach Azure App Service

## Hintergrund

In den bisherigen Labs haben wir Deployments nur simuliert — die Deploy-Stages
gaben Meldungen wie "Deployment erfolgreich!" aus, ohne tatsächlich eine
Anwendung irgendwo zu deployen. In diesem Lab führen wir erstmals ein **echtes
Deployment** durch: Wir deployen unsere Node.js-Anwendung auf einen **Azure App
Service**.

Azure App Service ist ein PaaS-Dienst (Platform as a Service) zum Hosten von
Webanwendungen. Im Gegensatz zu einer VM oder einem Container musst du dich
nicht um das Betriebssystem, Webserver-Konfiguration oder Patches kümmern — du
lieferst nur den Anwendungscode, und App Service kümmert sich um den Rest. Der
Dienst unterstützt diverse Sprachen (Node.js, Python, .NET, Java, PHP) und
bietet Features wie Auto-Scaling, Deployment Slots (für Blue/Green Deployments
in Lab 14), integriertes Monitoring und benutzerdefinierte Domains mit
SSL-Zertifikaten.

Für das Deployment verwenden wir den `AzureWebApp@1`-Task, der die Anwendung als
ZIP-Paket auf den App Service hochlädt. Der Task authentifiziert sich über die
Service Connection `azure-training-connection` aus Lab 05. Das Deployment-Paket
wird mit dem `ArchiveFiles@2`-Task erstellt, der das gesamte
Arbeitsverzeichnis (Quellcode + installierte Abhängigkeiten) in eine ZIP-Datei
packt.

Ein wichtiges Konzept bei App Service ist der **App Service Plan**: Er definiert
die zugrunde liegenden Compute-Ressourcen (CPU, RAM, Betriebssystem) und den
Tarif. Mehrere Web Apps können sich einen Plan teilen. Für dieses Training
wurde bereits ein **Standard (S1)**-Plan per Terraform bereitgestellt, der auch
Deployment Slots unterstützt (siehe Lab 14).

## Voraussetzungen

- Die Service Connection `azure-training-connection` aus Lab 05.
- Die Environments `dev` und `production` aus Lab 11 (falls du die
  Deployment-Historie nutzen möchtest).

## Aufgabenstellung

### Schritt 1: Deine Web App kennenlernen

Für jeden Teilnehmer wurde bereits eine Web App per Terraform bereitgestellt.
Der App-Name folgt dem Muster `app-training-teilnehmerNN` (z. B.
`app-training-teilnehmer01`). Alle Apps teilen sich einen gemeinsamen
**Standard (S1)**-Plan namens `plan-training-standard` in der Resource Group
`rg-pipeline-training`.

```bash
# Setze deinen App-Namen (ersetze NN mit deiner Teilnehmernummer)
APP_NAME="app-training-teilnehmerNN"

# Prüfe, ob die App existiert und erreichbar ist
az webapp show --name $APP_NAME --resource-group rg-pipeline-training --query "state" -o tsv
echo "App URL: https://$APP_NAME.azurewebsites.net"
```

Unter `https://<app-name>.azurewebsites.net` siehst du eine
Standard-Willkommensseite von Azure. Diese wird nach dem ersten Deployment
durch unsere Anwendung ersetzt.

### Schritt 2: Anwendung für App Service vorbereiten

Bisher bestand unsere Anwendung nur aus statischen Dateien (`app.js`,
`index.html`), die wir mit `npm run build` in ein `dist/`-Verzeichnis kopiert
haben. Für App Service brauchen wir einen HTTP-Server, der die Dateien
ausliefert. App Service startet die Anwendung mit `npm start` und erwartet, dass
sie auf dem Port lauscht, der über die Umgebungsvariable `PORT` definiert wird.

Erstelle die Datei **src/server.js** — ein einfacher Node.js-HTTP-Server mit
einem Health-Endpoint:

```javascript
const http = require('http');
const fs = require('fs');
const path = require('path');

const port = process.env.PORT || 8080;

const server = http.createServer((req, res) => {
    if (req.url === '/health') {
        res.writeHead(200, {'Content-Type': 'application/json'});
        res.end(JSON.stringify({
            status: 'healthy',
            version: process.env.APP_VERSION || 'unknown',
            timestamp: new Date().toISOString()
        }));
        return;
    }

    // index.html ausliefern
    const indexPath = path.join(__dirname, '..', 'index.html');
    if (fs.existsSync(indexPath)) {
        res.writeHead(200, {'Content-Type': 'text/html'});
        res.end(fs.readFileSync(indexPath));
    } else {
        res.writeHead(200, {'Content-Type': 'text/html'});
        res.end('<h1>Hello from Azure App Service!</h1>');
    }
});

server.listen(port, () => {
    console.log(`Server running on port ${port}`);
});
```

Der Server hat zwei Endpunkte:

- **`/health`**: Gibt JSON mit Status, Version und Zeitstempel zurück. Diesen
  Endpoint nutzt die Pipeline für den Health Check nach dem Deployment. In der
  Praxis verwenden auch Load Balancer und Monitoring-Tools solche
  Health-Endpoints.
- **`/` (und alle anderen Pfade)**: Liefert die `index.html` aus dem
  übergeordneten Verzeichnis. Falls die Datei nicht existiert, wird eine
  Fallback-Seite angezeigt.

Wichtig ist `process.env.PORT || 8080`: App Service setzt die `PORT`-Variable
auf den internen Port, auf dem die App lauschen muss. Lokal (ohne die Variable)
verwendet der Server Port 8080.

Ersetze den Inhalt von **package.json**, um den `start`-Befehl und die
Engine-Anforderung hinzuzufügen:

```json
{
  "name": "hello-pipeline",
  "version": "1.0.0",
  "description": "Demo-App für App Service Deployment",
  "main": "src/server.js",
  "scripts": {
    "start": "node src/server.js",
    "build": "echo 'Build complete'",
    "test": "node test/test.js"
  },
  "engines": {
    "node": ">=18.0.0"
  }
}
```

Das `start`-Skript ist entscheidend: App Service führt `npm start` aus, um die
Anwendung zu starten. Das `engines`-Feld dokumentiert die benötigte
Node.js-Version — App Service beachtet dieses Feld und gibt eine Warnung aus,
falls die konfigurierte Runtime-Version nicht passt.

Erstelle außerdem eine **web.config**-Datei für den Fall, dass die App auf einem
Windows-basierten App Service läuft. Auf Linux wird diese Datei ignoriert,
schadet aber nicht:

```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
    <system.webServer>
        <handlers>
            <add name="iisnode" path="src/server.js" verb="*"
                 modules="iisnode"/>
        </handlers>
        <rewrite>
            <rules>
                <rule name="NodeInspector" patternSyntax="ECMAScript"
                      stopProcessing="true">
                    <match url="^src/server.js\/debug[\/]?"/>
                </rule>
                <rule name="StaticContent">
                    <action type="Rewrite" url="public{REQUEST_URI}"/>
                </rule>
                <rule name="DynamicContent">
                    <conditions>
                        <add input="{REQUEST_FILENAME}" matchType="IsFile"
                             negate="True"/>
                    </conditions>
                    <action type="Rewrite" url="src/server.js"/>
                </rule>
            </rules>
        </rewrite>
    </system.webServer>
</configuration>
```

Die `web.config` konfiguriert IIS (den Windows-Webserver) so, dass alle Anfragen
an `src/server.js` weitergeleitet werden. Auf Linux-App-Services wird
stattdessen PM2 oder der direkte Node.js-Prozess verwendet.

### Schritt 3: Pipeline mit App Service Deployment

Jetzt erstellen wir eine Pipeline mit zwei Stages: Build und Deploy. Die
Build-Stage installiert die Abhängigkeiten, packt alles in eine ZIP-Datei und
publiziert sie als Artefakt. Die Deploy-Stage deployt das ZIP-Paket auf den App
Service und führt einen Health Check durch.

Ersetze den Inhalt von `azure-pipelines.yml`. **Wichtig**: Ersetze den
Platzhalter `<dein-app-name>` mit deinem tatsächlichen App-Namen aus Schritt 1:

```yaml
trigger:
  branches:
    include:
      - main

variables:
  azureSubscription: 'azure-training-connection'
  # Ersetze mit deinem App-Namen:
  appName: '<dein-app-name>'

stages:
  - stage: Build
    displayName: 'Build'
    jobs:
      - job: BuildApp
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - task: NodeTool@0
            inputs:
              versionSpec: '20.x'
            displayName: 'Node.js installieren'

          - script: npm install --production
            displayName: 'Abhängigkeiten installieren'

          # Deployment-Paket erstellen
          - task: ArchiveFiles@2
            displayName: 'Deployment-Paket erstellen'
            inputs:
              rootFolderOrFile: '$(System.DefaultWorkingDirectory)'
              includeRootFolder: false
              archiveType: 'zip'
              archiveFile: '$(Build.ArtifactStagingDirectory)/app.zip'
              replaceExistingArchive: true

          - publish: '$(Build.ArtifactStagingDirectory)/app.zip'
            artifact: 'web-app'
            displayName: 'Artefakt publizieren'

  - stage: DeployDev
    displayName: 'Deploy to Dev'
    dependsOn: Build
    jobs:
      - deployment: DeployWebApp
        displayName: 'Deploy Azure Web App'
        pool:
          vmImage: 'ubuntu-latest'
        environment: 'dev'
        strategy:
          runOnce:
            deploy:
              steps:
                - task: AzureWebApp@1
                  displayName: 'Deploy to App Service'
                  inputs:
                    azureSubscription: '$(azureSubscription)'
                    appType: 'webAppLinux'
                    appName: '$(appName)'
                    package: '$(Pipeline.Workspace)/web-app/app.zip'
                    runtimeStack: 'NODE|20-lts'

                - task: AzureCLI@2
                  displayName: 'Health Check'
                  inputs:
                    azureSubscription: '$(azureSubscription)'
                    scriptType: 'bash'
                    scriptLocation: 'inlineScript'
                    inlineScript: |
                      echo "Warte 30 Sekunden auf App-Start..."
                      sleep 30

                      echo "=== Health Check ==="
                      HEALTH_URL="https://$(appName).azurewebsites.net/health"
                      echo "URL: $HEALTH_URL"

                      HTTP_CODE=$(curl -s -o /tmp/health-response.txt -w "%{http_code}" $HEALTH_URL)
                      echo "HTTP Status: $HTTP_CODE"
                      echo "Response:"
                      cat /tmp/health-response.txt
                      echo ""

                      if [ "$HTTP_CODE" = "200" ]; then
                        echo "Health Check bestanden!"
                      else
                        echo "WARNUNG: Health Check nicht bestanden (HTTP $HTTP_CODE)"
                        echo "Die App braucht möglicherweise mehr Zeit zum Starten."
                      fi
```

Gehe die Pipeline Abschnitt für Abschnitt durch:

- **Build-Stage**: Installiert die npm-Abhängigkeiten mit `--production` (nur
  reguläre Dependencies, keine devDependencies). Der `ArchiveFiles@2`-Task packt
  das gesamte Arbeitsverzeichnis (Quellcode + `node_modules`) in eine ZIP-Datei.
  `includeRootFolder: false` sorgt dafür, dass die Dateien direkt im ZIP-Root
  liegen (nicht in einem Unterordner). Das ZIP wird als Artefakt
  `web-app` publiziert.
- **DeployDev-Stage**: Ein Deployment Job, der das Artefakt automatisch
  herunterlädt und auf den App Service deployt. Der `AzureWebApp@1`-Task
  übernimmt das eigentliche Deployment:
    - `appType: 'webAppLinux'`: Gibt an, dass es sich um eine Linux-App handelt.
    - `package`: Pfad zum ZIP-Artefakt. Der Deployment Job lädt Artefakte
      automatisch nach `$(Pipeline.Workspace)/<artefakt-name>/` herunter.
    - `runtimeStack: 'NODE|20-lts'`: Konfiguriert die Node.js-Version auf dem
      App Service.
- **Health Check**: Nach dem Deployment wartet der `AzureCLI@2`-Task 30
  Sekunden (Cold-Start-Zeit) und prüft dann den `/health`-Endpoint. Falls der
  HTTP-Status 200 ist, gilt der Health Check als bestanden. Bei einem anderen
  Status wird eine Warnung ausgegeben, aber die Pipeline nicht abgebrochen — der
  App-Start kann bei Free-Tier-Apps manchmal länger dauern.

### Schritt 4: Pipeline konfigurieren und starten

Ersetze den Platzhalter in der Pipeline-Datei und committe alle Dateien:

```bash
git add src/server.js package.json web.config azure-pipelines.yml
git commit -m "Add App Service deployment pipeline"
git push origin main
```

Beim ersten Lauf kann es sein, dass die Pipeline die Nutzung der Service
Connection und/oder des Environments genehmigen lassen muss. Öffne den
Pipeline-Run im Browser und klicke gegebenenfalls auf **"Permit"**.

### Schritt 5: App im Browser prüfen

Nach erfolgreichem Deployment sollte die App unter der Azure-URL erreichbar
sein. Prüfe sowohl die Hauptseite als auch den Health-Endpoint:

```bash
# Health Endpoint prüfen
curl https://$APP_NAME.azurewebsites.net/health

# Hauptseite prüfen (sollte index.html oder Fallback anzeigen)
curl https://$APP_NAME.azurewebsites.net
```

Öffne die URL `https://<dein-app-name>.azurewebsites.net` auch im Browser, um
die Seite visuell zu prüfen. Falls die App beim ersten Aufruf langsam reagiert,
ist das normal — der Free Tier fährt Instanzen nach Inaktivität herunter
(Cold Start).

## Aufräumen

Die Web App und der App Service Plan werden zentral per Terraform verwaltet.
**Lösche diese Ressourcen nicht manuell** — sie werden für Lab 14 (Blue/Green
Deployment) weiterverwendet und am Ende des Trainings automatisch
aufgeräumt.
