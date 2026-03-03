# Lab 14: Blue/Green Deployment

## Hintergrund

In Lab 13 haben wir eine Anwendung direkt auf den App Service deployt. Das
funktioniert, hat aber einen Nachteil: Während des Deployments kann es zu kurzen
Ausfallzeiten kommen, und wenn die neue Version fehlerhaft ist, muss man ein
erneutes Deployment der alten Version durchführen - was Zeit kostet und während
der Fehlerbehebung die Anwendung in einem defekten Zustand belässt.

**Blue/Green Deployment** löst dieses Problem: Die neue Version (Green) wird
**neben** der aktuellen Version (Blue) deployt, ohne den laufenden Betrieb zu
beeinträchtigen. Erst nach erfolgreichen Tests wird der Traffic von Blue auf
Green umgeleitet. Bei Problemen kann sofort zurück auf Blue geschaltet werden -
ohne erneutes Deployment, ohne Ausfallzeit.

Azure App Service bietet **Deployment Slots** als Mechanismus für Blue/Green
Deployments. Ein Deployment Slot ist eine eigenständige Instanz der Anwendung
mit eigener URL, eigenen Umgebungsvariablen und eigener Konfiguration - aber sie
teilt sich den App Service Plan (also die Compute-Ressourcen) mit dem
Haupt-Slot. Der Ablauf ist:

1. Die aktuelle Produktion läuft im **Haupt-Slot** (Production = Blue).
2. Die neue Version wird in den **Staging-Slot** deployt (Green).
3. Tests laufen gegen die Staging-URL (`<app>-staging.azurewebsites.net`).
4. Die Slots werden **getauscht (Swap)**: Der Traffic geht jetzt auf die neue
   Version. Der Swap ist ein DNS/Routing-Wechsel, kein erneutes Deployment.
5. Bei Problemen nach dem Swap: erneut swappen - die alte Version ist noch im
   Staging-Slot und sofort wieder live.

### Slot-Erkennung zur Laufzeit

Node.js liest Umgebungsvariablen beim Prozessstart.
Beim Slot-Swap werden Apps nicht in jedem Fall so neu gestartet, dass eine
geänderte Slot-Variable sofort im Prozess sichtbar wird. Für die Anzeige des
aktuellen Slots ermitteln wir ihn daher **zur Laufzeit aus dem Hostnamen** der
eingehenden Anfrage (`<app>.azurewebsites.net` vs.
`<app>-staging.azurewebsites.net`).

**Hinweis**: Deployment Slots erfordern mindestens den **Standard (S1)**-Tarif.
Der für das Training bereitgestellte S1-Plan unterstützt Deployment Slots und
wird am Ende des Trainings automatisch per Terraform aufgeräumt.

## Voraussetzungen

- Die Service Connection `azure-training-connection` aus Lab 05.
- Die Environments `staging` und `production` aus Lab 11.
- Deine Web App aus Lab 13 (`app-training-teilnehmerNN`) - diese läuft
  bereits auf einem S1-Plan und unterstützt Deployment Slots.

## Aufgabenstellung

### Schritt 1: Staging-Slot erstellen

Deine Web App (`app-training-teilnehmerNN`) läuft bereits auf einem S1-Plan,
der Deployment Slots unterstützt. In diesem Schritt erstellst du den
Staging-Slot.

Falls noch nicht geschehen in der letzten Übungsaufgabe, setze
den APP_NAME als Variable:
**Bash:**

```bash
# Setze deinen App-Namen (ersetze NN mit deiner Teilnehmernummer)
APP_NAME="app-training-teilnehmerNN"
```

**PowerShell:**

```powershell
# Setze deinen App-Namen (ersetze NN mit deiner Teilnehmernummer)
$APP_NAME = "app-training-teilnehmerNN"
```

Erzeuge danach einen Staging-Slot für das Deployment.

**Bash:**

```bash
# Staging Slot erstellen
az webapp deployment slot create \
  --name $APP_NAME \
  --resource-group rg-pipeline-training \
  --slot staging \
  --output table

echo "Production URL: https://$APP_NAME.azurewebsites.net"
echo "Staging URL:    https://$APP_NAME-staging.azurewebsites.net"
```

**PowerShell:**

```powershell
# Staging Slot erstellen
az webapp deployment slot create `
  --name $APP_NAME `
  --resource-group rg-pipeline-training `
  --slot staging `
  --output table

echo "Production URL: https://$APP_NAME.azurewebsites.net"
echo "Staging URL:    https://$APP_NAME-staging.azurewebsites.net"
```

Hier wird nur der **Staging-Slot** explizit erstellt. Der **Production-Slot**
ist die Web App selbst - er existiert automatisch seit `az webapp create` in
Lab 13. Befehle ohne `--slot` wirken immer auf diesen Production-Slot.

Nach der Erstellung hast du zwei erreichbare URLs: Die **Production-URL**
(`<app>.azurewebsites.net`) und die **Staging-URL**
(`<app>-staging.azurewebsites.net`). Beide sind unabhängige Instanzen - ein
Deployment in den Staging-Slot hat keine Auswirkung auf die Production-URL.

### Schritt 2: App mit Versionsanzeige vorbereiten (v1)

Um den Blue/Green-Wechsel visuell nachvollziehen zu können, erstellen wir einen
Server mit Versionsanzeige und farblicher Unterscheidung der Slots. Diese erste
Version wird unsere "Blue"-Version - die stabile Version in Production.

Erstelle die Datei **src/server.js**:

```javascript
const http = require('http');
const port = process.env.PORT || 8080;

// Version aus Umgebungsvariable oder Build-Info
const APP_VERSION = process.env.APP_VERSION || '1.0.0';

function getSlotName(req) {
    // Slot aus Hostname ableiten, damit kein App-Restart notwendig ist
    const host = (req.headers.host || '').toLowerCase();
    return host.includes('-staging.azurewebsites.net') ? 'staging' : 'production';
}

const server = http.createServer((req, res) => {
    const SLOT_NAME = getSlotName(req);

    if (req.url === '/health') {
        res.writeHead(200, {'Content-Type': 'application/json'});
        res.end(JSON.stringify({
            status: 'healthy',
            version: APP_VERSION,
            slot: SLOT_NAME,
            timestamp: new Date().toISOString()
        }));
        return;
    }

    res.writeHead(200, {'Content-Type': 'text/html'});
    res.end(`
    <!DOCTYPE html>
    <html>
    <head><title>Hello Pipeline - v${APP_VERSION}</title></head>
    <body style="font-family: Arial; padding: 40px; background: ${SLOT_NAME === 'staging' ? '#d4edda' : '#cce5ff'};">
      <h1>Hello from Azure Pipelines!</h1>
      <p><strong>Version:</strong> ${APP_VERSION}</p>
      <p><strong>Slot:</strong> ${SLOT_NAME}</p>
      <p><strong>Time:</strong> ${new Date().toISOString()}</p>
    </body>
    </html>
  `);
});

server.listen(port, () => {
    console.log(`Server v${APP_VERSION} running on port ${port}`);
});
```

Die Hauptseite zeigt je nach Slot eine unterschiedliche Hintergrundfarbe:
**Grün für Staging (Green)**, **Blau für Production (Blue)**. So siehst du im
Browser auf einen Blick, welcher Slot gerade aktiv ist.

### Schritt 3: Version 1 nach Production deployen

Bevor wir die Pipeline erstellen, deployen wir Version 1 direkt nach
Production. So haben wir eine laufende "Blue"-Version, gegen die wir später
den Blue/Green-Wechsel demonstrieren können.

```bash
az webapp up --name $APP_NAME --resource-group rg-pipeline-training --runtime "NODE:20-lts"
```

Prüfe, ob die App läuft:

**Bash:**

```bash
curl https://$APP_NAME.azurewebsites.net/health
```

**PowerShell:**

```powershell
Invoke-RestMethod https://$APP_NAME.azurewebsites.net/health
```

Du solltest diese Antwort sehen:

```json
{"status":"healthy","version":"1.0.0","slot":"production","timestamp":"..."}
```

Öffne auch `https://<app-name>.azurewebsites.net` im Browser: Du siehst die
Seite mit **blauem Hintergrund**, dem Titel "Hello from Azure Pipelines!" und
`Slot: production`. Das ist deine stabile Blue-Version.

### Schritt 4: Code für Version 2 ändern

Jetzt ändern wir den Code, um eine sichtbar andere Version zu erstellen. Ändere
in **src/server.js** den Titel von:

```javascript
<h1>Hello from Azure Pipelines!</h1>
```

zu:

```javascript
<h1>Hello from Azure Pipelines v2!</h1>
```

So ist der Unterschied zwischen v1 (Production) und v2 (Staging) im Browser
sofort erkennbar.

### Schritt 5: Pipeline mit Blue/Green Deployment

Jetzt erstellen wir die Pipeline mit vier Stages, die den Blue/Green-Ablauf
abbilden: Build, Deploy in den Staging-Slot (Green), Testen des Staging-Slots,
und Swap der Slots.

Ersetze den Inhalt von `azure-pipelines.yml`. **Wichtig**: Ersetze den
Platzhalter `<dein-app-name>` mit deinem tatsächlichen App-Namen:

```yaml
trigger:
  branches:
    include:
      - master

variables:
  azureSubscription: 'azure-training-connection'
  appName: '<dein-app-name>'
  appVersion: '1.0.$(Build.BuildId)'

stages:
  # ===== Build =====
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

          - script: npm install --production
            displayName: 'Dependencies installieren'

          - task: ArchiveFiles@2
            inputs:
              rootFolderOrFile: '$(System.DefaultWorkingDirectory)'
              includeRootFolder: false
              archiveType: 'zip'
              archiveFile: '$(Build.ArtifactStagingDirectory)/app.zip'

          - publish: '$(Build.ArtifactStagingDirectory)/app.zip'
            artifact: 'web-app'

  # ===== Deploy to Staging Slot (Green) =====
  - stage: DeployGreen
    displayName: 'Deploy Green (Staging Slot)'
    dependsOn: Build
    jobs:
      - deployment: DeployToSlot
        displayName: 'Deploy to Staging Slot'
        pool:
          vmImage: 'ubuntu-latest'
        environment: 'staging'
        strategy:
          runOnce:
            deploy:
              steps:
                # Deploy in den Staging-Slot
                - task: AzureWebApp@1
                  displayName: 'Deploy to Staging Slot'
                  inputs:
                    azureSubscription: '$(azureSubscription)'
                    appType: 'webAppLinux'
                    appName: '$(appName)'
                    package: '$(Pipeline.Workspace)/web-app/app.zip'
                    deployToSlotOrASE: true
                    slotName: 'staging'
                    runtimeStack: 'NODE|20-lts'

                # App-Version für den Staging-Slot setzen
                - task: AzureCLI@2
                  displayName: 'Staging-Slot konfigurieren'
                  inputs:
                    azureSubscription: '$(azureSubscription)'
                    scriptType: 'bash'
                    scriptLocation: 'inlineScript'
                    inlineScript: |
                      az webapp config appsettings set \
                        --name $(appName) \
                        --resource-group rg-pipeline-training \
                        --slot staging \
                        --settings APP_VERSION=$(appVersion)

  # ===== Test Green =====
  - stage: TestGreen
    displayName: 'Test Green'
    dependsOn: DeployGreen
    jobs:
      - job: SmokeTest
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - script: |
              echo "=== Smoke Test gegen Staging Slot ==="
              STAGING_URL="https://$(appName)-staging.azurewebsites.net"

              echo "Warte auf App-Start..."
              sleep 30

              echo "Test 1: Health Check"
              RESPONSE=$(curl -s "$STAGING_URL/health")
              echo "Response: $RESPONSE"

              echo ""
              echo "Test 2: Homepage erreichbar"
              HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$STAGING_URL")
              echo "HTTP Status: $HTTP_CODE"

              if [ "$HTTP_CODE" = "200" ]; then
                echo ""
                echo "Alle Smoke Tests bestanden!"
              else
                echo "FEHLER: Smoke Tests fehlgeschlagen!"
                exit 1
              fi
            displayName: 'Smoke Tests'

  # ===== Swap Slots (Blue/Green Switch) =====
  - stage: SwapSlots
    displayName: 'Swap Blue/Green'
    dependsOn: TestGreen
    jobs:
      - deployment: SwapToProduction
        displayName: 'Swap Staging to Production'
        pool:
          vmImage: 'ubuntu-latest'
        environment: 'production'
        strategy:
          runOnce:
            deploy:
              steps:
                - task: AzureCLI@2
                  displayName: 'Slots tauschen'
                  inputs:
                    azureSubscription: '$(azureSubscription)'
                    scriptType: 'bash'
                    scriptLocation: 'inlineScript'
                    inlineScript: |
                      echo "=== Slot Swap ==="
                      echo "Tausche Staging <-> Production..."
                      echo ""

                      az webapp deployment slot swap \
                        --name $(appName) \
                        --resource-group rg-pipeline-training \
                        --slot staging \
                        --target-slot production

                      echo "Swap abgeschlossen!"
                      echo ""
                      echo "Production URL: https://$(appName).azurewebsites.net"

                - script: |
                    echo "=== Post-Swap Validierung ==="
                    sleep 10
                    PROD_URL="https://$(appName).azurewebsites.net/health"
                    RESPONSE=$(curl -s "$PROD_URL")
                    echo "Production Health: $RESPONSE"
                  displayName: 'Post-Swap Check'
```

Gehe die Pipeline Abschnitt für Abschnitt durch:

- **Build-Stage**: Identisch zu Lab 13 - installiert Abhängigkeiten, packt alles
  in ein ZIP und publiziert es als Artefakt.
- **DeployGreen-Stage**: Deployt die neue Version in den **Staging-Slot**
  (Green), nicht in den Haupt-Slot. Der entscheidende Unterschied zu Lab 13 sind
  die Parameter `deployToSlotOrASE: true` und `slotName: 'staging'` im
  `AzureWebApp@1`-Task. Anschließend setzt ein `AzureCLI@2`-Task das
  App-Setting `APP_VERSION` für den Staging-Slot.
- **TestGreen-Stage**: Führt Smoke Tests gegen die **Staging-URL** aus
  (`<app>-staging.azurewebsites.net`). Beachte, dass dieser Stage ein normaler
  Job (kein Deployment Job) ist - er führt nur Tests aus, deployt nichts. Die
  Tests prüfen den Health-Endpoint und die Erreichbarkeit der Homepage. Nur wenn
  beide Tests bestehen, geht die Pipeline weiter.
- **SwapSlots-Stage**: Der eigentliche Blue/Green-Switch. Ein Deployment Job,
  der auf das `production`-Environment verweist (und damit den in Lab 12
  konfigurierten Approval Gate auslöst, falls vorhanden). Der
  `az webapp deployment slot swap`-Befehl tauscht Staging und Production atomar:
  Der Traffic geht sofort auf die neue Version, und die alte Version landet im
  Staging-Slot (als Rollback-Option). Nach dem Swap prüft ein Post-Swap-Check
  den Health-Endpoint der Production-URL.

### Schritt 6: Committen und Pipeline starten

Committe und pushe alle Dateien:

```bash
git add src/server.js azure-pipelines.yml
git commit -m "Add blue/green deployment with slot swap"
git push origin master
```

Falls auf dem Production-Environment ein Approval Gate konfiguriert ist
(Lab 12), wird die Pipeline vor der SwapSlots-Stage pausieren. Klicke im Browser
auf **"Review"** > **"Approve"**, um den Swap freizugeben.

### Schritt 7: Beide Slots vergleichen

Nachdem die Pipeline v2 in den Staging-Slot deployt hat (aber **vor** dem Swap),
laufen zwei verschiedene Versionen nebeneinander. Das ist der Sinn von
Blue/Green-Deployments:

**Bash:**

```bash
# Production: v1 (Blue) - die alte, stabile Version
curl https://$APP_NAME.azurewebsites.net/health

# Staging: v2 (Green) - die neue Version
curl https://$APP_NAME-staging.azurewebsites.net/health
```

**PowerShell:**

```powershell
# Production: v1 (Blue) - die alte, stabile Version
Invoke-RestMethod https://$APP_NAME.azurewebsites.net/health

# Staging: v2 (Green) - die neue Version
Invoke-RestMethod https://$APP_NAME-staging.azurewebsites.net/health
```

Öffne beide URLs auch im Browser, am besten in einer **privaten Sitzung**,
damit kein Caching greift:

- **Production** (`<app>.azurewebsites.net`): Blauer Hintergrund, Titel "Hello
  from Azure Pipelines!", `version: 1.0.0`, `slot: production`.
- **Staging** (`<app>-staging.azurewebsites.net`): Grüner Hintergrund, Titel
  "Hello from Azure Pipelines v2!", `version: 1.0.XX`, `slot: staging`.

Du siehst zwei verschiedene Versionen gleichzeitig - die alte und die neue. Die
Produktion ist zu keinem Zeitpunkt gestört. Erst wenn du den Swap freigibst,
wechselt der Traffic.

### Schritt 8: Swap und Post-Swap-Validierung

Nachdem du den Swap freigegeben hast (oder falls kein Approval Gate konfiguriert
ist: automatisch), tauschen die Slots. Prüfe danach beide URLs erneut:

**Bash:**

```bash
# Production: jetzt v2 (neue Version)
curl https://$APP_NAME.azurewebsites.net/health

# Staging: jetzt v1 (alte Version - bereit für Rollback)
curl https://$APP_NAME-staging.azurewebsites.net/health
```

**PowerShell:**

```powershell
# Production: jetzt v2 (neue Version)
Invoke-RestMethod https://$APP_NAME.azurewebsites.net/health

# Staging: jetzt v1 (alte Version - bereit für Rollback)
Invoke-RestMethod https://$APP_NAME-staging.azurewebsites.net/health
```

Erwartete Ergebnisse:

- **Production**: `version: 1.0.XX`, `slot: production` - die neue Version
  läuft jetzt in Production.
- **Staging**: `version: 1.0.0`, `slot: staging` - die alte Version ist im
  Staging-Slot gelandet, bereit für einen sofortigen Rollback.

Im Browser siehst du: Production hat weiterhin einen **blauen** Hintergrund und
Staging einen **grünen** - obwohl der Code getauscht wurde. Die Farbe folgt dem
Slot, nicht dem Code, weil `slot` pro Request aus der URL ermittelt wird.

### Schritt 9: Rollback testen

Ein großer Vorteil von Blue/Green Deployments: Der Rollback ist ein erneuter
Swap. Es ist keine erneute Build/Deploy-Kette nötig. Teste das manuell:

**Bash:**

```bash
# Erneuter Swap: Production und Staging werden wieder getauscht
az webapp deployment slot swap \
  --name $APP_NAME \
  --resource-group rg-pipeline-training \
  --slot staging \
  --target-slot production

# Prüfe, ob die alte Version wieder in Production ist
curl https://$APP_NAME.azurewebsites.net/health
```

**PowerShell:**

```powershell
# Erneuter Swap: Production und Staging werden wieder getauscht
az webapp deployment slot swap `
  --name $APP_NAME `
  --resource-group rg-pipeline-training `
  --slot staging `
  --target-slot production

# Prüfe, ob die alte Version wieder in Production ist
Invoke-RestMethod https://$APP_NAME.azurewebsites.net/health
```

## Aufräumen

Die Web App und der App Service Plan werden zentral per Terraform verwaltet.
**Lösche diese Ressourcen nicht manuell** - sie werden am Ende des Trainings
automatisch aufgeräumt.

Lösche nur den **Staging-Slot**, den du in diesem Lab manuell erstellt hast:

```bash
az webapp deployment slot delete --name $APP_NAME --resource-group rg-pipeline-training --slot staging
```
