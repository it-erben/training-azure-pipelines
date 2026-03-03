# Lab 19: Self-hosted Agent auf Linux einrichten

## Hintergrund

In allen bisherigen Labs haben wir **Microsoft-hosted Agents** verwendet —
virtuelle Maschinen, die Azure DevOps bei jedem Pipeline-Run bereitstellt und
nach dem Run wieder löscht. Diese Agents sind bequem: kein Setup, kein Wartung,
immer aktuelle Software. Aber sie haben Grenzen:

- **Spezielle Software**: Die Microsoft-hosted Agents enthalten eine
  vordefinierte Menge an Tools (Node.js, Python, Docker, .NET etc.). Wenn du
  proprietäre Software, spezielle Compiler oder lizenzierte Tools brauchst,
  kannst du sie nicht vorinstallieren.
- **Netzwerkzugriff**: Hosted Agents laufen in Microsofts Cloud-Netzwerk. Sie
  haben keinen Zugriff auf On-Premises-Systeme, private Netzwerke oder
  Datenbanken hinter einer Firewall.
- **Performance**: Hosted Agents verwenden Standard-VMs. Für rechenintensive
  Builds (große C++-Projekte, ML-Training) reicht die Leistung möglicherweise
  nicht aus.
- **Build-Cache**: Da jeder Run eine frische VM bekommt, geht der Build-Cache
  zwischen Runs verloren. Der `Cache@2`-Task (Lab 09) mildert das ab, hat
  aber Overhead durch Upload/Download.
- **Compliance**: In regulierten Branchen (Finanz, Gesundheit, Behörden) kann
  es Vorschriften geben, dass Build-Prozesse auf bestimmten Maschinen oder in
  bestimmten Regionen stattfinden müssen.

In diesen Fällen betreibst du einen **Self-hosted Agent**: einen Prozess auf
deiner eigenen Infrastruktur (physischer Server, VM, Container), der Aufträge
von Azure DevOps entgegennimmt und ausführt. Der Agent kommuniziert über HTTPS
mit Azure DevOps und fragt regelmäßig nach neuen Jobs — du brauchst also keine
eingehenden Firewall-Regeln.

### Agent Pools

Agents werden in **Agent Pools** organisiert. Ein Pool ist eine logische
Gruppe von Agents, die Pipelines als Ziel angeben können. Azure DevOps hat
standardmäßig den Pool `Azure Pipelines` für die Microsoft-hosted Agents.
Self-hosted Agents werden in eigenen Pools verwaltet — so kannst du
verschiedene Pools für verschiedene Zwecke erstellen (z. B. `linux-build`,
`windows-build`, `gpu-training`).

Wenn eine Pipeline `pool: { name: 'linux-training-pool' }` angibt, sucht
Azure DevOps in diesem Pool nach einem freien Agent und weist ihm den Job zu.
Jeder Agent kann nur einen Job gleichzeitig ausführen — für parallele Jobs
brauchst du mehrere Agents im Pool.

## Aufgabenstellung

### Schritt 1: Agent Pool erstellen

Erstelle einen neuen Agent Pool in der Azure DevOps Organisation:

1. Gehe zu **Organization Settings > Agent pools**.
2. Klicke auf **"Add pool"**.
3. Pool type: **Self-hosted**.
4. Name: `linux-training-pool`.
5. Setze den Haken bei **"Grant access permission to all pipelines"** — damit
   können alle Pipelines im Projekt diesen Pool verwenden, ohne dass du jede
   einzeln freigeben musst.
6. Klicke auf **"Create"**.

Der Pool ist jetzt angelegt, aber noch leer. Im nächsten Schritt erstellen wir
einen PAT, mit dem sich der Agent beim Pool anmelden kann.

### Schritt 2: Personal Access Token (PAT) erstellen

Der Agent braucht einen **Personal Access Token (PAT)** für die
Authentifizierung bei Azure DevOps. Der PAT autorisiert den Agent, sich beim
Pool zu registrieren und Jobs entgegenzunehmen.

1. Klicke oben rechts auf dein Profilbild > **"Personal Access Tokens"**.
2. Klicke auf **"+ New Token"**.
3. Name: `self-hosted-agent`.
4. Organization: Deine Trainings-Organisation.
5. Expiration: 30 Tage (für das Training ausreichend).
6. Scopes: Wähle **"Custom defined"** und aktiviere:
   - **Agent Pools**: Read & manage
7. Klicke auf **"Create"**.
8. **Kopiere den Token sofort!** Er wird nur einmal angezeigt. Speichere ihn
   vorübergehend in einer Textdatei oder in der Zwischenablage.

### Schritt 3: Agent auf der lokalen Maschine installieren

Der Azure Pipelines Agent ist ein portabler Prozess, der auf Linux, macOS und
Windows läuft. Du lädst ein Archiv herunter, entpackst es und konfigurierst
den Agent — keine Installation im klassischen Sinne nötig.

Öffne ein Terminal und führe folgende Befehle aus:

**Bash:**

```bash
# Verzeichnis für den Agent erstellen
mkdir -p ~/azagent && cd ~/azagent

# Agent herunterladen (aktuelle Version prüfen unter:
# https://github.com/microsoft/azure-pipelines-agent/releases)
curl -fkSL -o vsts-agent-linux-x64.tar.gz \
  https://vstsagentpackage.azureedge.net/agent/3.248.0/vsts-agent-linux-x64-3.248.0.tar.gz

# Entpacken
tar zxvf vsts-agent-linux-x64.tar.gz
```

**PowerShell:**

```powershell
# Verzeichnis für den Agent erstellen
New-Item -ItemType Directory -Force -Path $HOME\azagent | Out-Null
Set-Location $HOME\azagent

# Agent herunterladen (aktuelle Version prüfen unter:
# https://github.com/microsoft/azure-pipelines-agent/releases)
Invoke-WebRequest -Uri `
  https://vstsagentpackage.azureedge.net/agent/3.248.0/vsts-agent-win-x64-3.248.0.zip `
  -OutFile vsts-agent-win-x64.zip

# Entpacken
Expand-Archive -Path vsts-agent-win-x64.zip -DestinationPath .
```

Nach dem Entpacken siehst du mehrere Dateien, darunter `config.sh` (bzw.
`config.cmd` auf Windows) und `run.sh` (bzw. `run.cmd`). Das sind die
beiden Hauptskripte: eines zum Konfigurieren und eines zum Starten des Agents.

### Schritt 4: Agent konfigurieren

Die Konfiguration verbindet den Agent mit deiner Azure DevOps Organisation und
registriert ihn im Agent Pool. Du brauchst die Organisation-URL, den PAT aus
Schritt 2 und den Pool-Namen aus Schritt 1.

**Bash:**

```bash
# Konfiguration starten
./config.sh

# Du wirst nach folgenden Informationen gefragt:
# Server URL:    https://dev.azure.com/<organisations-name>
# Authentication: PAT (Enter drücken für Default)
# Token:         <dein-pat-token>
# Agent Pool:    linux-training-pool
# Agent Name:    training-agent-01 (oder Enter für Standardnamen)
# Work folder:   _work (oder Enter für Standard)
```

**PowerShell:**

```powershell
# Konfiguration starten
.\config.cmd

# Du wirst nach folgenden Informationen gefragt:
# Server URL:    https://dev.azure.com/<organisations-name>
# Authentication: PAT (Enter drücken für Default)
# Token:         <dein-pat-token>
# Agent Pool:    linux-training-pool
# Agent Name:    training-agent-01 (oder Enter für Standardnamen)
# Work folder:   _work (oder Enter für Standard)
```

Die Konfiguration speichert die Verbindungsdaten lokal in `.credentials`- und
`.agent`-Dateien. Der PAT selbst wird nicht gespeichert — stattdessen tauscht
der Agent ihn gegen ein OAuth-Token, das automatisch erneuert wird.

### Schritt 5: Agent starten

Starte den Agent interaktiv in einem eigenen Terminal-Fenster. Der Agent
verbindet sich mit Azure DevOps und wartet auf Jobs:

**Bash:**

```bash
# Interaktiv starten (für Testzwecke)
./run.sh

# Du siehst:
# Starting Agent listener...
# Listening for Jobs
```

**PowerShell:**

```powershell
# Interaktiv starten (für Testzwecke)
.\run.cmd

# Du siehst:
# Starting Agent listener...
# Listening for Jobs
```

Lass den Agent in diesem Terminal-Fenster laufen und wechsle für die weiteren
Schritte in ein anderes Terminal. Wenn der Agent einen Job erhält, siehst du in
diesem Fenster die Ausgabe in Echtzeit.

**Optional: Agent als Systemdienst installieren (nur Linux)**

Für den dauerhaften Betrieb (z. B. auf einem Build-Server) installierst du den
Agent als systemd-Service. Dann startet er automatisch beim Systemstart und
läuft im Hintergrund:

```bash
# Agent als systemd-Service installieren
sudo ./svc.sh install
sudo ./svc.sh start

# Status prüfen
sudo ./svc.sh status
```

### Schritt 6: Agent im Portal prüfen

Prüfe, ob der Agent erfolgreich registriert und online ist:

1. Gehe zu **Organization Settings > Agent pools > linux-training-pool**.
2. Klicke auf den Tab **"Agents"**.
3. Dein Agent sollte als **"Online"** (grüner Punkt) angezeigt werden. Du
   siehst auch den Agent-Namen, die Version und das Betriebssystem.

Falls der Agent als "Offline" angezeigt wird, prüfe das Terminal-Fenster auf
Fehlermeldungen.

### Schritt 7: Pipeline auf Self-hosted Agent ausführen

Jetzt erstellen wir eine Pipeline, die zwei Stages parallel ausführt: eine auf
einem Microsoft-hosted Agent und eine auf dem Self-hosted Agent. So kannst du
die Unterschiede direkt vergleichen.

Ersetze den Inhalt von `azure-pipelines.yml`:

```yaml
trigger:
  branches:
    include:
      - master

stages:
  # ===== Job auf Microsoft-hosted Agent =====
  - stage: HostedBuild
    displayName: 'Microsoft-hosted Build'
    jobs:
      - job: HostedJob
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - script: |
              echo "=== Microsoft-hosted Agent ==="
              echo "Agent Name: $(Agent.Name)"
              echo "Agent OS:   $(Agent.OS)"
              echo "Agent Version: $(Agent.Version)"
              echo "Machine Name:  $(Agent.MachineName)"
              echo ""
              echo "Vorteile:"
              echo "  - Kein Setup nötig"
              echo "  - Immer aktuell"
              echo "  - Skaliert automatisch"
            displayName: 'Hosted Agent Info'

  # ===== Job auf Self-hosted Agent =====
  - stage: SelfHostedBuild
    displayName: 'Self-hosted Build'
    dependsOn: []  # Parallel zum Hosted Build
    jobs:
      - job: SelfHostedJob
        pool:
          name: 'linux-training-pool'
        steps:
          - script: |
              echo "=== Self-hosted Agent ==="
              echo "Agent Name:    $(Agent.Name)"
              echo "Agent OS:      $(Agent.OS)"
              echo "Agent Version: $(Agent.Version)"
              echo "Machine Name:  $(Agent.MachineName)"
              echo "Home Dir:      $(Agent.HomeDirectory)"
              echo ""
              echo "System-Info:"
              uname -a
              echo ""
              echo "Installierte Tools:"
              which git && git --version
              which node && node --version 2>/dev/null || echo "Node.js: nicht installiert"
              which python3 && python3 --version || echo "Python: nicht installiert"
              which docker && docker --version 2>/dev/null || echo "Docker: nicht installiert"
              echo ""
              echo "Vorteile:"
              echo "  - Spezielle Software möglich"
              echo "  - Netzwerkzugriff auf interne Systeme"
              echo "  - Höhere Leistung möglich"
              echo "  - Build-Cache bleibt erhalten"
            displayName: 'Self-hosted Agent Info'

          - script: |
              echo "=== Custom-Tool Demo ==="
              echo "Auf einem Self-hosted Agent kannst du"
              echo "beliebige Tools vorinstallieren, z.B.:"
              echo "  - Spezielle Compiler"
              echo "  - Lizenzierte Software"
              echo "  - Interne CLI-Tools"
              echo "  - VPN-Clients"
            displayName: 'Custom-Tools'
```

Gehe die Pipeline Abschnitt für Abschnitt durch:

- **HostedBuild-Stage**: Läuft auf dem Microsoft-hosted Agent
  (`vmImage: 'ubuntu-latest'`). Der Step gibt die Agent-Informationen aus —
  du siehst hier einen automatisch generierten Agent-Namen und die
  Azure-Maschine.
- **SelfHostedBuild-Stage**: Läuft auf dem Self-hosted Agent
  (`name: 'linux-training-pool'`). Beachte den Unterschied in der
  `pool`-Konfiguration: statt `vmImage` (für hosted) wird `name` (für den
  Pool-Namen) verwendet. `dependsOn: []` macht diese Stage unabhängig von
  der HostedBuild-Stage, sodass beide **parallel** laufen. Der Step gibt
  dieselben Agent-Informationen aus — hier siehst du den Namen deines
  Rechners und die lokal installierten Tools.

### Schritt 8: Committen und Pipeline beobachten

```bash
git add azure-pipelines.yml
git commit -m "Add self-hosted agent pipeline"
git push origin master
```

Beobachte den Pipeline-Run im Browser. Die beiden Stages `HostedBuild` und
`SelfHostedBuild` starten gleichzeitig. Im Terminal-Fenster deines Agents
siehst du in Echtzeit, wie der Job empfangen und ausgeführt wird.

Vergleiche in den Logs:

- **Agent Name**: Der Hosted Agent hat einen automatisch generierten Namen
  (z. B. `Hosted Agent`), der Self-hosted Agent den von dir vergebenen Namen
  (z. B. `training-agent-01`).
- **Machine Name**: Der Hosted Agent zeigt eine Azure-VM, der Self-hosted
  Agent deinen Rechnernamen.
- **Installierte Tools**: Der Self-hosted Agent zeigt nur die Tools, die auf
  deiner Maschine installiert sind. Falls Node.js oder Docker fehlen, siehst
  du "nicht installiert".

## Validierung

1. Prüfe in **Organization Settings > Agent pools > linux-training-pool**,
   dass der Agent als **"Online"** angezeigt wird.
2. Prüfe, dass die Pipeline beide Stages (Hosted und Self-hosted) erfolgreich
   durchläuft.
3. Vergleiche die Agent-Informationen in den Logs beider Stages.

```bash
az pipelines runs list --top 1 --output table
```

## Erwartetes Ergebnis

Im Log des Self-hosted Agents:

```
=== Self-hosted Agent ===
Agent Name:    training-agent-01
Agent OS:      Linux
Machine Name:  mein-rechner
Home Dir:      /home/user/azagent

System-Info:
Linux mein-rechner 5.15.0-...

Installierte Tools:
/usr/bin/git
git version 2.43.0
...
```

Beide Stages laufen parallel. Die Vergleichstabelle fasst die Unterschiede
zwischen den Agent-Typen zusammen.

## Aufräumen

Nach dem Lab solltest du den Agent sauber deregistrieren, damit er nicht als
"Offline" im Pool hängen bleibt.

**Bash:**

```bash
# Agent stoppen (wenn interaktiv)
# Ctrl+C im Agent-Terminal

# Agent als Service stoppen und deinstallieren (falls installiert)
sudo ./svc.sh stop
sudo ./svc.sh uninstall

# Agent-Konfiguration entfernen (deregistriert den Agent aus dem Pool)
./config.sh remove --auth pat --token <dein-pat-token>

# Agent-Verzeichnis löschen
cd ~ && rm -rf azagent

# Agent Pool löschen (optional)
# Organization Settings > Agent pools > linux-training-pool > Delete
```

**PowerShell:**

```powershell
# Agent stoppen (wenn interaktiv)
# Ctrl+C im Agent-Terminal

# Agent-Konfiguration entfernen (deregistriert den Agent aus dem Pool)
.\config.cmd remove --auth pat --token <dein-pat-token>

# Agent-Verzeichnis löschen
Set-Location $HOME
Remove-Item -Recurse -Force azagent

# Agent Pool löschen (optional)
# Organization Settings > Agent pools > linux-training-pool > Delete
```

Vergiss nicht, den PAT zu widerrufen, da er nicht mehr benötigt wird:

1. Profilbild > **Personal Access Tokens**.
2. Finde den Token `self-hosted-agent`.
3. Klicke auf **"Revoke"**.

## Tipps und Troubleshooting

- **Agent erscheint als "Offline"**: Prüfe, ob der Agent-Prozess läuft.
  Starte ihn mit `./run.sh` und prüfe die Konsole auf Fehlermeldungen. Häufige
  Ursache: Netzwerkprobleme oder ein abgelaufener PAT.
- **"No agent found in pool"**: Die Pipeline referenziert einen Pool-Namen, in
  dem kein Agent online ist. Prüfe, ob der Pool-Name in der Pipeline
  (`name: 'linux-training-pool'`) exakt dem erstellten Pool entspricht.
- **Agent auf Windows**: Verwende `config.cmd` und `run.cmd` statt der
  `.sh`-Dateien. Die Konfigurationsschritte sind identisch.
- **Capabilities und Demands**: Self-hosted Agents melden ihre installierten
  Tools automatisch als **Capabilities** (z. B. `node`, `npm`, `docker`).
  Pipelines können **Demands** stellen, die ein Agent erfüllen muss — z. B.
  `demands: npm`. Wenn kein Agent im Pool die Demands erfüllt, wartet der
  Job unbegrenzt.
- **Parallele Jobs**: Jeder Agent kann nur **einen Job gleichzeitig**
  ausführen. Für parallele Jobs brauchst du mehrere Agents im selben Pool.
  Azure DevOps verteilt die Jobs automatisch auf freie Agents.
- **Agent-Updates**: Self-hosted Agents aktualisieren sich automatisch, wenn
  Azure DevOps eine neue Version bereitstellt. Du siehst die aktuelle Version
  in den Agent-Details unter **Organization Settings > Agent pools**.
- **Docker-basierte Agents**: In der Praxis werden Self-hosted Agents oft als
  Docker-Container betrieben. Das vereinfacht das Setup und die Skalierung —
  bei Bedarf startest du einfach mehr Container. Microsoft stellt ein
  Basis-Image bereit, das du um eigene Tools erweitern kannst.
