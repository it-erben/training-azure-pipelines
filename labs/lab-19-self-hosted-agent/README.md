# Lab 19: Self-hosted Agent einrichten

## Hintergrund

In allen bisherigen Labs haben wir **Microsoft-hosted Agents** verwendet —
virtuelle Maschinen, die Azure DevOps bei jedem Pipeline-Run bereitstellt und
nach dem Run wieder löscht. Diese Agents sind bequem: kein Setup,
keine Wartung, immer aktuelle Software. Aber sie haben Grenzen:

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

Wenn eine Pipeline `pool: { name: 'training-pool-<teilnehmernr>' }` angibt, sucht
Azure DevOps in diesem Pool nach einem freien Agent und weist ihm den Job zu.
Jeder Agent kann nur einen Job gleichzeitig ausführen — für parallele Jobs
brauchst du mehrere Agents im Pool.

## Aufgabenstellung

### Schritt 1: Agent Pool erstellen

Erstelle einen neuen Agent Pool in deinem Projekt:

1. Gehe zu **Project Settings > Agent pools**.
2. Klicke auf **"Add pool"**.
3. Pool type: **Self-hosted**.
4. Name: `training-pool-<teilnehmernr>`.
5. Setze den Haken bei **"Grant access permission to all pipelines"**
6. Klicke auf **"Create"**.

Der Pool ist jetzt angelegt, aber noch leer. Im nächsten Schritt erstellen wir
einen PAT, mit dem sich der Agent beim Pool anmelden kann.

### Schritt 2: Personal Access Token (PAT) erstellen

Der Agent braucht einen **Personal Access Token (PAT)** für die
Authentifizierung bei Azure DevOps. Der PAT autorisiert den Agent, sich beim
Pool zu registrieren und Jobs entgegenzunehmen.

1. Klicke oben links neben dein Profilbild auf das kleine Zahnrad und wähle
   **"Personal Access Tokens"**.
2. Klicke auf **"+ New Token"**.
3. Name: `self-hosted-agent`.
4. Organization: Deine Trainings-Organisation.
5. Expiration: 30 Tage (für das Training ausreichend).
6. Scopes: Wähle **"Full Access"**
7. Klicke auf **"Create"**.
8. **Kopiere den Token sofort!** Er wird nur einmal angezeigt. Speichere ihn
   vorübergehend in einer Textdatei.

### Schritt 3: Agent auf der lokalen Maschine installieren

Der Azure Pipelines Agent ist ein portabler Prozess, der auf Linux, macOS und
Windows läuft. Du lädst ein Archiv herunter, entpackst es und konfigurierst
den Agent.

Klicke hierzu auf den Agent Pool, den du eben erstellt hast, und wähle
**New Agent**. Befolge danach die Anleitung für dein System.

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
# Agent Pool:    training-pool-<teilnehmernr>
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
# Agent Pool:    training-pool-<teilnehmernr>
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

### Schritt 6: Agent im Portal prüfen

Prüfe, ob der Agent erfolgreich registriert und online ist:

1. Gehe zu **Organization Settings > Agent pools > training-pool-<teilnehmernr>**.
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
          name: 'training-pool-<teilnehmernr>'
        steps:
          - script: |
              echo "=== Self-hosted Agent ==="
              echo "Agent Name:    $(Agent.Name)"
              echo "Agent OS:      $(Agent.OS)"
              echo "Agent Version: $(Agent.Version)"
              echo "Machine Name:  $(Agent.MachineName)"
              echo "Home Dir:      $(Agent.HomeDirectory)"
            displayName: 'Agent Info'

          # Linux/macOS: Bash-Befehle für System-Info
          - bash: |
              echo "System-Info:"
              uname -a
              echo ""
              echo "Installierte Tools:"
              which git && git --version
              which node && node --version 2>/dev/null || echo "Node.js: nicht installiert"
              which python3 && python3 --version || echo "Python: nicht installiert"
              which docker && docker --version 2>/dev/null || echo "Docker: nicht installiert"
            displayName: 'Installierte Tools (Linux/macOS)'
            condition: ne(variables['Agent.OS'], 'Windows_NT')

          # Windows: PowerShell-Befehle für System-Info
          - powershell: |
              Write-Host "System-Info:"
              [System.Environment]::OSVersion | Format-List
              Write-Host ""
              Write-Host "Installierte Tools:"
              @("git", "node", "python", "docker") | ForEach-Object {
                $cmd = Get-Command $_ -ErrorAction SilentlyContinue
                if ($cmd) { Write-Host "${_}: $(& $_ --version 2>&1)" }
                else { Write-Host "$($_): nicht installiert" }
              }
            displayName: 'Installierte Tools (Windows)'
            condition: eq(variables['Agent.OS'], 'Windows_NT')

          - script: |
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
  (`name: 'training-pool-<teilnehmernr>'`). Beachte den Unterschied in der
  `pool`-Konfiguration: statt `vmImage` (für hosted) wird `name` (für den
  Pool-Namen) verwendet. `dependsOn: []` macht diese Stage unabhängig von
  der HostedBuild-Stage, sodass beide **parallel** laufen. Der Step gibt
  dieselben Agent-Informationen aus — hier siehst du den Namen deines
  Rechners und die lokal installierten Tools.

### Schritt 8: Committen und Pipeline beobachten

```bash
git add azure-pipelines.yml
git commit -m "Add self-hosted agent pipeline"
git push
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
