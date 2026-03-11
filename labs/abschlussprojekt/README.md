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

Alle Tests sollten grün sein.

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
Setze im `Docker@2`-Task den `buildContext` auf `app` - das bedeutet, dass das
Verzeichnis `app` nach der Dockerfile durchsucht wird. Verwende
`<dein-acr-name>` wie in Lab 08.

**Anforderung 4 — ACI-Deployment**: Deploye den Container mit `az container
create` auf Azure Container Instances. Bediene dich dabei an Aufgabe 13b.
Verwende einen eindeutigen Container-
und DNS-Namen (z. B. `dashboard-dev-<teilnehmernr>`).

**Anforderung 5 — Health Check**: Nach dem Deployment ist die App unter
`http://<dns-name-label>.westeurope.azurecontainer.io` erreichbar. Prüfe den
`/health`-Endpoint mit `curl`.

**Anforderung 6 — Variable Group**: Erstelle eine Variable Group
`dashboard-config` mit mindestens einer Variable (z. B. `ENVIRONMENT=production`):

Binde die Variable Group in der Pipeline mit `- group: dashboard-config` ein.

**Anforderung 7 — Approval Gate (Bonus)**: Konfiguriere auf dem Environment
`production` einen Approval Check (siehe Lab 12). Füge eine zusätzliche
Deploy-Stage hinzu, die auf dieses Environment deployt.

**Anforderung 8 — Template (Bonus)**: Lagere z. B. den Health Check in eine
eigene Datei `templates/health-check.yml` aus und binde sie mit `template:` ein
(siehe Lab 20). Da das Template im selben Repository liegt, brauchst du kein
`resources.repositories`.
