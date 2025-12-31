# Lab 15: Rollback-Strategien

## Hintergrund

Trotz sorgfältiger Tests, Code-Reviews und Approval Gates kann ein Deployment
in Production fehlschlagen. Der Health Check zeigt Fehler, die Anwendung
antwortet nicht, oder ein bisher unentdeckter Bug tritt unter realer Last auf.
In solchen Fällen muss schnell auf eine funktionierende Version
zurückgekehrt werden können — idealerweise innerhalb von Minuten, nicht
Stunden.

Es gibt verschiedene Rollback-Strategien, die je nach Infrastruktur und
Deployment-Methode zum Einsatz kommen:

1. **Slot Swap Rollback** (Lab 14): Bei Blue/Green Deployments ist ein
   erneuter Swap der schnellste Rollback — die alte Version ist noch im
   Staging-Slot und sofort wieder live. Dauer: wenige Sekunden.
2. **Re-Deploy der vorherigen Version**: Man startet einen älteren
   erfolgreichen Pipeline-Run erneut. Azure DevOps speichert die Artefakte
   aller Runs für die konfigurierte Aufbewahrungsdauer (Standard: 30 Tage),
   sodass man jederzeit auf eine ältere Version zurückgreifen kann.
3. **Automatischer Rollback**: Die Pipeline erkennt Fehler über einen Health
   Check und führt im `on:failure`-Hook automatisch Rollback-Schritte aus —
   z. B. ein Re-Deploy der letzten funktionierenden Version, einen Slot Swap
   zurück oder eine Benachrichtigung an das Team.
4. **Manueller Rollback per Parameter**: Die Pipeline bietet einen Parameter
   an, über den man gezielt eine bestimmte Build-Nummer für ein Rollback
   angeben kann. Die Pipeline lädt dann die Artefakte dieses Builds und
   deployt sie.

In diesem Lab implementieren wir die Strategien 2, 3 und 4 in einer Pipeline.
Wir verwenden Pipeline-Parameter (aus Lab 04), um Fehler zu simulieren und
Rollbacks manuell auszulösen, sowie die `on:failure`- und `on:success`-
Lifecycle-Hooks (aus Lab 11), um automatisch auf Deployment-Fehler zu
reagieren.

## Voraussetzungen

- Die Environments `dev` aus Lab 11.
- Die Anwendungsdateien (`src/app.js`, `index.html`, `package.json`) aus den
  vorherigen Labs.

## Aufgabenstellung

### Schritt 1: Pipeline mit Rollback-Logik

Wir erstellen eine Pipeline mit drei Stages: Build, Deploy (mit Health Check
und automatischem Rollback) und ein optionaler manueller Rollback, der über
Pipeline-Parameter gesteuert wird.

Ersetze den Inhalt von `azure-pipelines.yml`:

```yaml
trigger:
  branches:
    include:
      - main

parameters:
  - name: simulateFailure
    displayName: 'Deployment-Fehler simulieren?'
    type: boolean
    default: false

  - name: rollbackToBuild
    displayName: 'Rollback auf Build-Nummer (leer = kein Rollback)'
    type: string
    default: ''

variables:
  azureSubscription: 'azure-training-connection'
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
          - script: |
              mkdir -p dist
              cp src/*.js dist/
              cp index.html dist/
              cp package.json dist/
              echo '{"version": "$(appVersion)", "buildId": "$(Build.BuildId)"}' > dist/version.json
            displayName: 'Build'

          - publish: dist
            artifact: app-package

  # ===== Deploy mit Health Check =====
  - stage: Deploy
    displayName: 'Deploy mit Health Check'
    dependsOn: Build
    jobs:
      - deployment: DeployWithHealthCheck
        displayName: 'Deploy und validieren'
        pool:
          vmImage: 'ubuntu-latest'
        environment: 'dev'
        strategy:
          runOnce:
            deploy:
              steps:
                - script: |
                    echo "=== Deployment Version $(appVersion) ==="
                    echo "Artefakte:"
                    ls -la $(Pipeline.Workspace)/app-package/
                    echo ""
                    cat $(Pipeline.Workspace)/app-package/version.json
                    echo ""
                    echo "Deployment durchgeführt."
                  displayName: 'Deploy'

                # Health Check
                - script: |
                    echo "=== Health Check ==="

                    # Fehler simulieren, wenn Parameter gesetzt
                    if [ "${{ parameters.simulateFailure }}" = "True" ]; then
                      echo "FEHLER: Health Check fehlgeschlagen (simuliert)!"
                      echo "Die Anwendung antwortet nicht auf dem Health-Endpoint."
                      exit 1
                    fi

                    echo "HTTP 200 OK"
                    echo "App-Version: $(appVersion)"
                    echo "Health Check bestanden."
                  displayName: 'Health Check'

            on:
              failure:
                steps:
                  - script: |
                      echo "======================================="
                      echo "  DEPLOYMENT FEHLGESCHLAGEN"
                      echo "======================================="
                      echo ""
                      echo "Version $(appVersion) konnte nicht deployt werden."
                      echo "Automatischer Rollback wird eingeleitet..."
                      echo ""
                      echo "Rollback-Strategie:"
                      echo "1. Letzte erfolgreiche Version aus Artefakt-Speicher laden"
                      echo "2. Re-Deploy der letzten Version"
                      echo "3. Health Check der Rollback-Version"
                      echo ""
                      echo "In einer realen Umgebung würde jetzt:"
                      echo "  - Die vorherige Version re-deployt"
                      echo "  - Oder ein Slot-Swap zurück auf Blue durchgeführt"
                      echo "  - Eine Benachrichtigung an das Team gesendet"
                    displayName: 'Automatischer Rollback'

                  - script: |
                      echo "=== Rollback-Benachrichtigung ==="
                      echo "An: dev-team@example.com"
                      echo "Betreff: Deployment $(appVersion) fehlgeschlagen - Rollback durchgeführt"
                      echo "Build-URL: $(System.CollectionUri)$(System.TeamProject)/_build/results?buildId=$(Build.BuildId)"
                    displayName: 'Team benachrichtigen'

              success:
                steps:
                  - script: |
                      echo "Version $(appVersion) erfolgreich deployt!"
                      echo "Keine Rollback-Aktion nötig."
                    displayName: 'Deployment bestätigt'

  # ===== Manueller Rollback =====
  - stage: ManualRollback
    displayName: 'Manueller Rollback'
    dependsOn: []  # Unabhängig von anderen Stages
    condition: ne('${{ parameters.rollbackToBuild }}', '')
    jobs:
      - deployment: RollbackDeployment
        displayName: 'Rollback durchführen'
        pool:
          vmImage: 'ubuntu-latest'
        environment: 'dev'
        strategy:
          runOnce:
            deploy:
              steps:
                - script: |
                    echo "======================================="
                    echo "  MANUELLER ROLLBACK"
                    echo "======================================="
                    echo ""
                    echo "Rollback auf Build: ${{ parameters.rollbackToBuild }}"
                    echo ""
                    echo "In einer realen Umgebung würde:"
                    echo "1. Das Artefakt von Build ${{ parameters.rollbackToBuild }} geladen"
                    echo "2. Dieses Artefakt deployt"
                    echo "3. Health Check durchgeführt"
                    echo ""
                    echo "Tipp: Du kannst auch unter 'Pipelines > Runs' einen"
                    echo "älteren erfolgreichen Run finden und diesen re-deployen:"
                    echo "  Run öffnen > drei Punkte (...) > 'Rerun failed jobs'"
                    echo "  oder einen komplett neuen Run starten."
                  displayName: 'Rollback durchführen'
```

Gehe die Pipeline Abschnitt für Abschnitt durch:

- **Parameter**: Zwei Parameter steuern das Verhalten der Pipeline.
  `simulateFailure` ist ein Boolean, der beim manuellen Start gesetzt werden
  kann — er lässt den Health Check absichtlich fehlschlagen, um den
  `on:failure`-Hook zu demonstrieren. `rollbackToBuild` ist ein String, der
  eine Build-Nummer enthält, auf die zurückgerollt werden soll. Ist er leer
  (der Default), wird die ManualRollback-Stage übersprungen.
- **Build-Stage**: Baut die Anwendung und erzeugt eine `version.json` mit der
  aktuellen Version und Build-ID. Diese Datei dient in späteren Stages zur
  Identifikation der deployten Version.
- **Deploy-Stage**: Ein Deployment Job mit zwei Steps im `deploy`-Hook: erst
  das Deployment, dann ein Health Check. Der Health Check prüft den Parameter
  `simulateFailure` — ist er `True`, schlägt der Check mit Exit-Code 1 fehl,
  und der `on:failure`-Hook wird ausgelöst. Bei Erfolg wird der
  `on:success`-Hook ausgeführt.
- **`on:failure`-Hook**: Wird nur ausgeführt, wenn ein Step im `deploy`-Hook
  fehlgeschlagen ist. Hier werden zwei Steps ausgeführt: der eigentliche
  Rollback (in der Praxis würde hier die letzte funktionierende Version
  re-deployt) und eine Benachrichtigung an das Team mit einem Link zum
  fehlgeschlagenen Build. In einer realen Umgebung könnte die Benachrichtigung
  z. B. per Slack-Webhook, Microsoft Teams oder E-Mail erfolgen.
- **ManualRollback-Stage**: Hat `dependsOn: []` — sie ist von keiner anderen
  Stage abhängig und kann parallel zu Build und Deploy laufen. Die `condition`
  prüft, ob der Parameter `rollbackToBuild` nicht leer ist. Ist er leer
  (Default), wird die Stage komplett übersprungen. In einer realen Umgebung
  würde diese Stage die Artefakte des angegebenen Builds laden und deployen.

### Schritt 2: Erfolgreichen Deploy testen

Committe die Pipeline und lass sie einmal mit den Default-Parametern laufen
(kein Fehler, kein Rollback):

```bash
git add azure-pipelines.yml
git commit -m "Add rollback strategies"
git push origin main
```

Warte, bis die Pipeline durchläuft. Die Deploy-Stage sollte erfolgreich sein,
der `on:success`-Hook sollte "Deployment bestätigt" ausgeben, und die
ManualRollback-Stage sollte übersprungen werden (da `rollbackToBuild` leer
ist).

### Schritt 3: Fehler simulieren

Jetzt lösen wir absichtlich einen Deployment-Fehler aus, um den automatischen
Rollback zu demonstrieren:

1. Gehe zu **Pipelines > hello-pipeline**.
2. Klicke auf **"Run pipeline"**.
3. Im Parameter-Dialog siehst du die beiden Parameter:
    - Setze **"Deployment-Fehler simulieren?"** auf **Ja/True**.
    - Lass **"Rollback auf Build-Nummer"** leer.
4. Klicke auf **"Run"**.

Beobachte den Pipeline-Run im Browser:

- Die **Build-Stage** läuft normal durch.
- In der **Deploy-Stage** schlägt der **Health Check**-Step fehl (Exit-Code 1).
  Die Stage wird rot markiert.
- Anschließend werden die **`on:failure`-Hooks** ausgeführt: "Automatischer
  Rollback" und "Team benachrichtigen". Diese Steps laufen trotz des
  Deployment-Fehlers, da sie im `on:failure`-Block definiert sind.
- Die **ManualRollback-Stage** wird übersprungen (Parameter ist leer).

### Schritt 4: Manuellen Rollback testen

Jetzt testen wir den manuellen Rollback, indem wir eine Build-Nummer angeben:

1. Klicke erneut auf **"Run pipeline"**.
2. Setze **"Deployment-Fehler simulieren?"** auf **Nein/False**.
3. Setze **"Rollback auf Build-Nummer"** auf eine vorherige Build-Nummer
   (z. B. `20260222.1` — du findest die Nummern unter **Pipelines > Runs**).
4. Klicke auf **"Run"**.

Beobachte den Pipeline-Run:

- Die **Build-Stage** und **Deploy-Stage** laufen normal durch (kein Fehler
  simuliert).
- Die **ManualRollback-Stage** wird **zusätzlich** ausgeführt, da der Parameter
  nicht leer ist. Sie zeigt die angegebene Build-Nummer und die
  Rollback-Schritte.

Beachte, dass in diesem Lab-Beispiel beide Stages parallel laufen können
(`dependsOn: []`). In einer realen Pipeline würde man den manuellen Rollback
typischerweise als eigenständige Pipeline oder mit einer Condition
implementieren, die den regulären Deploy-Pfad ausschließt.

### Schritt 5: Re-Run eines älteren Builds

Die dritte Rollback-Methode braucht keine besondere Pipeline-Konfiguration —
sie nutzt eine eingebaute Funktion von Azure DevOps:

1. Gehe zu **Pipelines > Runs** (oder **Pipelines > hello-pipeline > Runs**).
2. Finde einen älteren, **erfolgreichen** Run in der Liste.
3. Klicke auf den Run, um die Details zu öffnen.
4. Klicke auf die drei Punkte (**...**) oben rechts.
5. Wähle **"Run new"** — dies startet einen neuen Run mit dem **gleichen
   Commit**. Der Build erzeugt dieselben Artefakte wie der ursprüngliche Run,
   und das Deployment rollt die alte Version aus.

Diese Methode ist in der Praxis oft der einfachste Rollback: Man braucht
keine spezielle Pipeline-Logik, sondern nutzt einfach die Tatsache, dass
Azure DevOps jeden Run mit seinem Commit verknüpft.

## Validierung

Prüfe per CLI, dass alle Runs ausgeführt wurden:

```bash
# Alle letzten Runs anzeigen
az pipelines runs list --top 5 --output table
```

Öffne im Browser die drei Pipeline-Runs und prüfe die folgenden Punkte:

1. **Erfolgreicher Run** (Schritt 2): Der `on:success`-Hook zeigt "Deployment
   bestätigt". Die ManualRollback-Stage ist übersprungen.
2. **Fehlgeschlagener Run** (Schritt 3): Die Deploy-Stage ist rot. Die
   `on:failure`-Hooks "Automatischer Rollback" und "Team benachrichtigen"
   wurden ausgeführt. Die ManualRollback-Stage ist übersprungen.
3. **Manueller Rollback-Run** (Schritt 4): Sowohl die Deploy-Stage als auch
   die ManualRollback-Stage wurden ausgeführt.

## Erwartetes Ergebnis

**Erfolgreicher Deploy:**

```
Health Check bestanden.
Version 1.0.42 erfolgreich deployt!
Keine Rollback-Aktion nötig.
```

**Fehlgeschlagener Deploy:**

```
FEHLER: Health Check fehlgeschlagen (simuliert)!
=======================================
  DEPLOYMENT FEHLGESCHLAGEN
=======================================
Automatischer Rollback wird eingeleitet...
```

**Manueller Rollback:**

```
=======================================
  MANUELLER ROLLBACK
=======================================
Rollback auf Build: 20260222.1
```

## Aufräumen

Kein Aufräumen nötig. Die Pipeline erzeugt keine externen Ressourcen.

## Tipps und Troubleshooting

- **`on:failure` vs. `on:success`**: Diese Lifecycle-Hooks sind nur in
  **Deployment Jobs** verfügbar (nicht in normalen Jobs). Sie werden nach
  Abschluss aller Steps im `deploy`-Hook ausgeführt — je nachdem, ob ein Step
  fehlgeschlagen ist oder alle erfolgreich waren. Sie ersetzen nicht das
  Fehlerhandling innerhalb von Steps (z. B. `continueOnError`).
- **Re-Deploy der vorherigen Version**: Der einfachste Rollback in der Praxis
  ist, einen älteren erfolgreichen Pipeline-Run erneut auszuführen ("Run new").
  Die Artefakte werden neu gebaut, und das Deployment erfolgt mit dem alten
  Code-Stand.
- **Slot Swap Rollback**: Bei Blue/Green Deployments (Lab 14) ist ein erneuter
  Swap der schnellste Rollback — keine Pipeline nötig, dauert Sekunden statt
  Minuten.
- **Datenbank-Rollbacks**: Wenn ein Deployment auch Datenbank-Migrationen
  enthält, ist ein Code-Rollback allein oft nicht ausreichend. Plane
  **Forward-Only Migrationen** (die auch mit der alten Code-Version
  kompatibel sind) oder implementiere einen separaten Rollback-Migrations-
  Schritt. Vermeide destruktive Migrationen (wie `DROP COLUMN`), bis
  sichergestellt ist, dass kein Rollback mehr nötig ist.
- **Rollback-Zeitfenster**: Definiere im Team, wie lange ein Rollback möglich
  sein soll. Nach einem bestimmten Zeitpunkt (z. B. wenn neue Daten mit dem
  neuen Schema geschrieben wurden) kann ein Rollback mehr Schaden anrichten
  als nützen. In solchen Fällen ist ein **Forward-Fix** (schnelles Beheben des
  Bugs in einer neuen Version) oft die bessere Strategie.
- **Automatische Benachrichtigungen**: In der Praxis würde der `on:failure`-
  Hook eine echte Benachrichtigung senden — z. B. über einen Slack-Webhook
  (`curl -X POST -H 'Content-Type: application/json' ...`), eine Microsoft
  Teams Incoming-Webhook-URL oder den Azure DevOps Service Hook für E-Mails.
