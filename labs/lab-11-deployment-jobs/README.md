# Lab 11: Deployment Jobs und Environments

## Hintergrund

In den bisherigen Labs haben wir Deployments mit normalen Jobs (`job:`)
simuliert. Das funktioniert, hat aber Nachteile: Azure DevOps weiß nicht, dass
es sich um ein Deployment handelt, es gibt keine Deployment-Historie, und
Mechanismen wie Approval Gates oder Deployment-Strategien stehen nicht zur
Verfügung.

Ein **Deployment Job** (`deployment:`) ist ein spezieller Job-Typ, der genau
für diesen Zweck konzipiert ist. Im Gegensatz zu normalen Jobs bietet er:

- **Deployment-Strategien**: Steuern, wie ein Deployment ausgerollt wird.
  `runOnce` führt das Deployment einmalig aus (der einfachste Fall). `rolling`
  und `canary` ermöglichen schrittweise Rollouts, bei denen nur ein Teil der
  Zielinfrastruktur gleichzeitig aktualisiert wird.
- **Lifecycle-Hooks**: Strukturieren den Deployment-Prozess in definierte
  Phasen. Statt alle Schritte als flache Liste zu definieren, kannst du sie
  nach Funktion gruppieren: Vorbereitungen (`preDeploy`), das eigentliche
  Deployment (`deploy`), Traffic-Umleitung (`routeTraffic`), Post-Deployment-
  Tests (`postRouteTraffic`) und Abschluss-Aktionen (`on:success` /
  `on:failure`).
- **Environment-Tracking**: Jedes Deployment wird einem **Environment**
  zugeordnet. Azure DevOps führt eine Deployment-Historie pro Environment, in
  der du siehst, welche Version wann von wem deployt wurde und ob das
  Deployment erfolgreich war.

**Environments** repräsentieren Zielumgebungen wie Dev, Staging oder Production.
Sie existieren als eigene Ressource in Azure DevOps (unter **Pipelines >
Environments**) und bieten neben der Deployment-Historie auch Approval Gates
und Checks, die wir in Lab 12 kennenlernen.

Ein weiterer praktischer Vorteil von Deployment Jobs: Artefakte, die in einer
vorherigen Stage publiziert wurden, werden **automatisch heruntergeladen** -
du brauchst keinen expliziten `download`-Step. Die Artefakte landen unter
`$(Pipeline.Workspace)/<artefakt-name>/`.

## Aufgabenstellung

### Schritt 1: Environments in Azure DevOps anlegen

Environments können auf zwei Wegen erstellt werden: manuell über die
Web-Oberfläche oder automatisch beim ersten Pipeline-Lauf, der ein noch nicht
existierendes Environment referenziert. Wir legen sie manuell an, damit wir in
Lab 12 direkt Approval Gates konfigurieren können.

1. Gehe zu **Pipelines > Environments**.
2. Klicke auf **"New environment"**.
3. Erstelle die folgenden drei Environments:

| Name         | Beschreibung                  |
|--------------|-------------------------------|
| `dev`        | Entwicklungsumgebung          |
| `staging`    | Staging/Test-Umgebung         |
| `production` | Produktionsumgebung           |

Für jedes Environment:

- Gib den Namen ein (exakt wie in der Tabelle, da die Pipeline diesen Namen
  referenziert).
- Resource: Wähle **"None"**. Environments können optional mit
  Kubernetes-Clustern oder VM-Gruppen verknüpft werden - für unsere simulierten
  Deployments brauchen wir das nicht.
- Klicke auf **"Create"**.

Nach dem Anlegen siehst du unter **Pipelines > Environments** alle drei
Environments. Jedes hat zunächst eine leere Deployment-Historie, die sich füllt,
sobald Deployments durchlaufen.

### Schritt 2: Pipeline mit Deployment Jobs

Jetzt erstellen wir eine Pipeline mit vier Stages: Build, Deploy Dev, Deploy
Staging und Deploy Production. Die drei Deploy-Stages verwenden Deployment Jobs
mit der `runOnce`-Strategie. Die Staging-Stage demonstriert zusätzlich alle
verfügbaren Lifecycle-Hooks.

Ersetze den Inhalt von `azure-pipelines.yml`:

```yaml
trigger:
  branches:
    include:
      - master

variables:
  appVersion: '1.0.$(Build.BuildId)'

stages:
  # ===== Build Stage =====
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
              echo '{"version": "$(appVersion)", "buildId": "$(Build.BuildId)"}' > dist/version.json
            displayName: 'Build'

          - publish: dist
            artifact: app-package
            displayName: 'Artefakte publizieren'

  # ===== Deploy to Dev =====
  - stage: DeployDev
    displayName: 'Deploy Dev'
    dependsOn: Build
    jobs:
      - deployment: DeployToDev
        displayName: 'Deploy to Dev'
        pool:
          vmImage: 'ubuntu-latest'
        environment: 'dev'
        strategy:
          runOnce:
            deploy:
              steps:
                - script: |
                    echo "=== Deployment nach Dev ==="
                    echo "Version: $(appVersion)"
                    echo "Artefakte:"
                    ls -la $(Pipeline.Workspace)/app-package/
                    echo ""
                    echo "version.json:"
                    cat $(Pipeline.Workspace)/app-package/version.json
                    echo ""
                    echo "Simuliere Deployment nach Dev..."
                    sleep 2
                    echo "Dev Deployment erfolgreich!"
                  displayName: 'Deploy to Dev'

                - script: |
                    echo "=== Smoke Test ==="
                    echo "Prüfe, ob die App erreichbar ist..."
                    echo "HTTP 200 OK (simuliert)"
                    echo "Smoke Test bestanden!"
                  displayName: 'Smoke Test'

  # ===== Deploy to Staging =====
  - stage: DeployStaging
    displayName: 'Deploy Staging'
    dependsOn: DeployDev
    jobs:
      - deployment: DeployToStaging
        displayName: 'Deploy to Staging'
        pool:
          vmImage: 'ubuntu-latest'
        environment: 'staging'
        strategy:
          runOnce:
            preDeploy:
              steps:
                - script: |
                    echo "=== Pre-Deploy Check ==="
                    echo "Prüfe Voraussetzungen für Staging..."
                    echo "Datenbank-Migration: nicht erforderlich"
                    echo "Konfiguration: geprüft"
                    echo "Pre-Deploy Checks bestanden!"
                  displayName: 'Pre-Deploy Checks'

            deploy:
              steps:
                - script: |
                    echo "=== Deployment nach Staging ==="
                    echo "Version: $(appVersion)"
                    echo "Artefakte:"
                    ls -la $(Pipeline.Workspace)/app-package/
                    echo ""
                    echo "Simuliere Deployment nach Staging..."
                    sleep 3
                    echo "Staging Deployment erfolgreich!"
                  displayName: 'Deploy to Staging'

            postRouteTraffic:
              steps:
                - script: |
                    echo "=== Integration Tests ==="
                    echo "Führe Integration Tests gegen Staging aus..."
                    echo "  Test 1: API Health Check     - PASS"
                    echo "  Test 2: Login Flow           - PASS"
                    echo "  Test 3: Datenbank-Verbindung - PASS"
                    echo "Alle Integration Tests bestanden!"
                  displayName: 'Integration Tests'

            on:
              success:
                steps:
                  - script: |
                      echo "Staging Deployment erfolgreich abgeschlossen!"
                      echo "Version $(appVersion) ist auf Staging live."
                    displayName: 'Erfolgs-Benachrichtigung'
              failure:
                steps:
                  - script: |
                      echo "FEHLER: Staging Deployment fehlgeschlagen!"
                      echo "Automatischer Rollback wird eingeleitet..."
                    displayName: 'Fehler-Behandlung'

  # ===== Deploy to Production =====
  - stage: DeployProduction
    displayName: 'Deploy Production'
    dependsOn: DeployStaging
    condition: and(succeeded(), eq(variables['Build.SourceBranchName'], 'master'))
    jobs:
      - deployment: DeployToProd
        displayName: 'Deploy to Production'
        pool:
          vmImage: 'ubuntu-latest'
        environment: 'production'
        strategy:
          runOnce:
            preDeploy:
              steps:
                - script: |
                    echo "=== Production Pre-Deploy ==="
                    echo "Version: $(appVersion)"
                    echo "Letzte Prüfungen vor Production..."
                    echo "Alle Checks bestanden."
                  displayName: 'Final Checks'

            deploy:
              steps:
                - script: |
                    echo "=== Production Deployment ==="
                    echo "Deploye Version $(appVersion) nach Production..."
                    sleep 5
                    echo "Production Deployment erfolgreich!"
                    echo ""
                    echo "Die App ist live unter: https://app.example.com"
                  displayName: 'Deploy to Production'

            on:
              success:
                steps:
                  - script: |
                      echo "Version $(appVersion) erfolgreich in Production deployt!"
                    displayName: 'Production Live'
```

Gehe die Pipeline Abschnitt für Abschnitt durch:

- **Build-Stage**: Ein normaler Job (kein Deployment Job), der die Anwendung
  baut und als Artefakt `app-package` publiziert. Die `version.json`-Datei
  enthält die Version und Build-ID, sodass in späteren Stages nachvollziehbar
  ist, welcher Build deployt wurde.
- **DeployDev-Stage**: Der erste Deployment Job. Beachte die Syntax-Unterschiede
  zu einem normalen Job: Statt `job:` steht hier `deployment:`, und statt
  einer flachen `steps:`-Liste gibt es eine `strategy:` mit `runOnce:` und
  einem `deploy:`-Hook. Das Keyword `environment: 'dev'` verknüpft diesen Job
  mit dem gleichnamigen Environment - jeder Lauf erscheint in dessen
  Deployment-Historie. Beachte auch, dass kein `download`-Step nötig ist: Der
  Deployment Job lädt die Artefakte automatisch herunter.
- **DeployStaging-Stage**: Demonstriert alle Lifecycle-Hooks der
  `runOnce`-Strategie:
    - `preDeploy`: Läuft **vor** dem eigentlichen Deployment. Hier können
      Voraussetzungen geprüft werden (z. B. ob eine Datenbank-Migration nötig
      ist oder ob die Konfiguration stimmt).
    - `deploy`: Das eigentliche Deployment. Hier würde man in der Praxis
      Befehle wie `az webapp deploy` oder `kubectl apply` ausführen.
    - `postRouteTraffic`: Läuft **nach** dem Deployment (und nach einer
      optionalen Traffic-Umleitung). Typischerweise werden hier Integration
      Tests gegen die frisch deployte Umgebung ausgeführt.
    - `on.success` / `on.failure`: Abschluss-Hooks, die je nach Ergebnis
      ausgeführt werden. In der Praxis könntest du hier Benachrichtigungen
      senden (z. B. Slack/Teams) oder bei einem Fehler einen automatischen
      Rollback einleiten.
- **DeployProduction-Stage**: Kombiniert Deployment Job und `condition`. Die
  Stage wird nur auf dem `master`-Branch ausgeführt - auf Feature-Branches wird
  sie übersprungen. Hier werden nur `preDeploy`, `deploy` und `on.success`
  verwendet; nicht jeder Hook muss in jeder Stage genutzt werden.

### Schritt 3: Committen und Pipeline starten

```bash
git add azure-pipelines.yml
git commit -m "Add deployment jobs with environments"
git push origin master
```

### Schritt 4: Deployment-Historie prüfen

Nachdem die Pipeline durchgelaufen ist, hat jedes Environment ein Deployment in
seiner Historie. Prüfe das im Browser:

1. Gehe zu **Pipelines > Environments**.
2. Klicke auf das Environment **"staging"**.
3. Du siehst die **Deployment-Historie** - eine chronologische Liste aller
   Deployments mit:
    - **Deployment-Nummer**: Fortlaufend pro Environment.
    - **Version/Commit**: Der Git-Commit, auf dem der Build basiert.
    - **Status**: Succeeded, Failed oder In Progress.
    - **Zeitpunkt**: Wann das Deployment stattfand.
4. Klicke auf ein einzelnes Deployment, um zum zugehörigen Pipeline-Run zu
   springen.
5. Prüfe auch die Environments **"dev"** und **"production"** - auch dort
   sollte jeweils ein erfolgreiches Deployment angezeigt werden.

Die Deployment-Historie ist einer der Hauptvorteile von Environments: Du kannst
jederzeit nachvollziehen, welche Version in welcher Umgebung läuft und wer das
Deployment ausgelöst hat.

## Aufräumen

Environments können bestehen bleiben - sie verursachen keine Kosten und werden
in Lab 12 (Approval Gates) weiterverwendet.
