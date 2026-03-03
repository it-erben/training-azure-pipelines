# Abschlussprojekt: Pipeline Challenge

## Einleitung

Du hast in den Labs einzelne Pipeline-Konzepte kennengelernt — Trigger,
Variablen, Stages, Docker, Deployments, Environments, Templates. Jetzt
kombinierst du sie: Du bekommst eine fertige Node.js-App und einen
Anforderungskatalog. Deine Aufgabe ist es, die `azure-pipelines.yml` **von
Grund auf selbst zu schreiben**, sodass alle Anforderungen erfüllt sind.

Im Gegensatz zu den bisherigen Labs gibt es hier keine Schritt-für-Schritt-
Anleitung. Du darfst (und sollst!) in den vorherigen Labs nachschauen. Der
Zeitrahmen ist **60–90 Minuten**.

## Voraussetzungen

- Die **Azure Container Registry (ACR)** aus Lab 08 mit der Service Connection
  `acr-training-connection`.
- Die Service Connection `azure-training-connection` (Lab 05).
- Die Environments `dev` und `production` (Lab 11).

## Die App

Im Verzeichnis `app/` findest du ein fertiges **Team Status Dashboard** — eine
Node.js-Webanwendung mit einem `/health`-Endpoint, einer `/api/info`-Route und
einem visuellen Dashboard.

Kopiere das gesamte `app/`-Verzeichnis in dein `hello-pipeline`-Repository.

Teste die App dann lokal:

```bash
npm test
```

Alle Tests sollten grün sein. Optional kannst du auch den Docker-Build lokal
testen:

```bash
docker build -t team-dashboard .
docker run -p 8080:80 team-dashboard
# Öffne http://localhost:8080 im Browser
```

## Anforderungen

Schreibe eine `azure-pipelines.yml` im Root deines `hello-pipeline`-Repositorys,
die folgende Anforderungen erfüllt:

| Nr | Anforderung                                                        | Hinweis | Pflicht |
|----|--------------------------------------------------------------------|---------|---------|
| 1  | Pipeline triggert bei Push auf `master`                            | Lab 02  | Ja      |
| 2  | Tests laufen in einer eigenen Stage                                | Lab 06  | Ja      |
| 3  | Docker-Image wird gebaut und in die ACR gepusht                    | Lab 08  | Ja      |
| 4  | Deployment auf ACI über einen Deployment Job mit Environment `dev` | Lab 11  | Ja      |
| 5  | Health Check nach dem Deployment (HTTP-Request auf `/health`)      | Lab 13  | Ja      |
| 6  | Mindestens eine Variable kommt aus einer Variable Group            | Lab 04  | Ja      |
| 7  | Approval Gate vor einer `production`-Stage                         | Lab 12  | Bonus   |
| 8  | Wiederverwendbares Template (z. B. für den Health Check)           | Lab 20  | Bonus   |

### Details zu den Anforderungen

**Anforderung 3 — Docker-Image**: Das Dockerfile liegt unter `app/Dockerfile`.
Setze im `Docker@2`-Task den `buildContext` auf `app`. Verwende
`<dein-acr-name>` wie in Lab 08.

**Anforderung 4 — ACI-Deployment**: Deploye den Container mit `az container
create` auf Azure Container Instances. Verwende einen eindeutigen Container-
und DNS-Namen (z. B. `dashboard-dev-<teilnehmernr>`). Um das Docker-Image aus
der ACR zu pullen, brauchst du die ACR-Credentials:

**Bash:**

```bash
ACR_USERNAME=$(az acr credential show --name <dein-acr-name> --query username -o tsv)
ACR_PASSWORD=$(az acr credential show --name <dein-acr-name> --query "passwords[0].value" -o tsv)
```

**PowerShell:**

```powershell
$ACR_USERNAME = (az acr credential show --name <dein-acr-name> --query username -o tsv)
$ACR_PASSWORD = (az acr credential show --name <dein-acr-name> --query "passwords[0].value" -o tsv)
```

Übergib diese Credentials an `az container create` mit `--registry-login-server`,
`--registry-username` und `--registry-password`.

**Anforderung 5 — Health Check**: Nach dem Deployment ist die App unter
`http://<dns-name-label>.westeurope.azurecontainer.io` erreichbar. Prüfe den
`/health`-Endpoint mit `curl`.

**Anforderung 6 — Variable Group**: Erstelle eine Variable Group
`dashboard-config` mit mindestens einer Variable (z. B. `ENVIRONMENT=production`):

**Bash:**

```bash
az pipelines variable-group create \
  --name "dashboard-config" \
  --variables ENVIRONMENT=production \
  --authorize true \
  --output table
```

**PowerShell:**

```powershell
az pipelines variable-group create `
  --name "dashboard-config" `
  --variables ENVIRONMENT=production `
  --authorize true `
  --output table
```

Binde die Variable Group in der Pipeline mit `- group: dashboard-config` ein.

**Anforderung 7 — Approval Gate (Bonus)**: Konfiguriere auf dem Environment
`production` einen Approval Check (siehe Lab 12). Füge eine zusätzliche
Deploy-Stage hinzu, die auf dieses Environment deployt.

**Anforderung 8 — Template (Bonus)**: Lagere z. B. den Health Check in eine
eigene Datei `templates/health-check.yml` aus und binde sie mit `template:` ein
(siehe Lab 20). Da das Template im selben Repository liegt, brauchst du kein
`resources.repositories`.

## Hinweise

- **Du darfst in den bisherigen Labs nachschauen** — das ist kein Gedächtnistest,
  sondern eine Integrationsübung.
- **Fang einfach an** und arbeite dich durch die Anforderungen:
  1. Trigger und eine leere Pipeline (Anforderung 1)
  2. Test-Stage mit `npm test` (Anforderung 2)
  3. Docker Build and Push (Anforderung 3)
  4. ACI-Deployment mit Deployment Job (Anforderung 4)
  5. Health Check nach dem Deployment (Anforderung 5)
  6. Variable Group einbinden (Anforderung 6)
  7. Production-Stage mit Approval Gate (Anforderung 7, Bonus)
  8. Health Check als Template auslagern (Anforderung 8, Bonus)
- **Committe nach jedem Zwischenschritt** und prüfe, ob die Pipeline
  durchläuft. So findest du Fehler früh.
- Denke daran, dass `npm test` im Verzeichnis `app/` laufen muss
  (`workingDirectory: app`).

## Lösung

> Versuche es erst selbst! Die Lösung hilft dir am meisten, wenn du vorher
> schon eigene Versuche unternommen hast.

Die Musterlösung findest du unter
[`loesung/azure-pipelines.yml`](loesung/azure-pipelines.yml). Sie enthält auch
ein Health-Check-Template unter
[`loesung/templates/health-check.yml`](loesung/templates/health-check.yml).
