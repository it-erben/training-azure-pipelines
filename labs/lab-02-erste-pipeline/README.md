# Lab 02: Erste Pipeline mit YAML erstellen

## Hintergrund

Azure Pipelines verwendet YAML-Dateien zur Definition von CI/CD-Workflows. Eine
Pipeline besteht aus **Stages** (Phasen), **Jobs** (Aufträge) und **Steps**
(Schritte). In der einfachsten Form genügt ein `trigger` und eine Liste von
`steps`. Die YAML-Datei liegt im Repository und wird versioniert. Das nennt
man "Pipeline as Code".

Der Microsoft-hosted Agent Pool `ubuntu-22.04` stellt eine vorkonfigurierte
Linux-VM bereit, auf der deine Pipeline-Schritte ausgeführt werden.

## Aufgabenstellung

### Schritt 1: Pipeline-YAML erstellen

Azure Pipelines werden als YAML-Dateien definiert, die im Repository liegen. Das
nennt man **Pipeline as Code** - die Pipeline-Definition wird gemeinsam mit dem
Anwendungscode versioniert, reviewed und gemerged. Änderungen an der Pipeline
durchlaufen denselben Workflow wie Code-Änderungen.

Die wichtigsten Elemente einer Pipeline-YAML:

- **`trigger`**: Definiert, bei welchen Git-Events die Pipeline automatisch
  startet (z. B. Push auf `main`).
- **`pool`**: Gibt an, auf welcher Infrastruktur die Pipeline läuft. Mit
  `vmImage` nutzen wir einen von Microsoft gehosteten Agent.
- **`steps`**: Die einzelnen Schritte, die nacheinander ausgeführt werden. Jeder
  `script`-Step führt Shell-Befehle aus.

Wechsle in dein geklontes Repository (`hello-pipeline`) und erstelle dort die
folgende Datei:

**azure-pipelines.yml**

```yaml
# Meine erste Azure Pipeline
trigger:
  branches:
    include:
      - main

pool:
  vmImage: 'ubuntu-22.04'

steps:
  - script: echo "Hallo aus Azure Pipelines!"
    displayName: 'Begrüßung'

  - script: |
      echo "Build-Nummer: $(Build.BuildNumber)"
      echo "Repository: $(Build.Repository.Name)"
      echo "Branch: $(Build.SourceBranchName)"
      echo "Commit: $(Build.SourceVersion)"
    displayName: 'Build-Informationen anzeigen'

  - script: |
      echo "Betriebssystem:"
      uname -a
      echo ""
      echo "Installierte Tools:"
      node --version
      python3 --version
      dotnet --version
      java -version 2>&1 | head -1
    displayName: 'Agent-Umgebung prüfen'

  - script: |
      echo "Dateien im Repository:"
      ls -la
      echo ""
      echo "Inhalt von index.html:"
      cat index.html
    displayName: 'Repository-Inhalt anzeigen'
```

### Schritt 2: Pipeline-Datei committen und pushen

Die Pipeline-Datei muss sich im Repository befinden, damit Azure DevOps sie
finden kann. Committe und pushe die Datei:

```bash
git add azure-pipelines.yml
git commit -m "Add initial pipeline definition"
git push origin main
```

Damit liegt die Datei auf dem Remote-Repository in Azure DevOps. Im nächsten
Schritt verbinden wir sie mit einer Pipeline.

### Schritt 3: Pipeline in Azure DevOps erstellen

Jetzt verknüpfen wir die YAML-Datei mit einer Pipeline in Azure DevOps. Azure
DevOps bietet einen Assistenten, der dich durch die Einrichtung führt.

1. Öffne dein Projekt im Browser unter <https://dev.azure.com/iterben>.
2. Klicke im linken Navigationsmenü auf **Pipelines** und dann auf den Button
   **"Create pipeline"** (bzw. **"New pipeline"**, falls bereits Pipelines
   existieren).
3. Unter **"Where is your code?"** wähle **"Azure Repos Git"**. Damit weiß Azure
   DevOps, dass die YAML-Datei in einem Azure-DevOps-eigenen Repository liegt (nicht z.B. auf GitHub).
4. Wähle das Repository **"hello-pipeline"** aus der Liste. Azure DevOps erkennt
   automatisch die Datei `azure-pipelines.yml` im Root-Verzeichnis.
5. Es wird dir eine Vorschau der YAML-Datei angezeigt - prüfe kurz, ob der
   Inhalt korrekt aussieht, und klicke dann auf **"Run"**. Damit wird die
   Pipeline angelegt und sofort zum ersten Mal ausgeführt.

### Schritt 4: Pipeline-Ausführung beobachten

Nach dem Klick auf "Run" wird die Pipeline in die Warteschlange gestellt. Ein
freier Microsoft-hosted Agent übernimmt den Job, checkt dein Repository aus und
führt die Steps nacheinander aus. Das dauert typischerweise 10–30 Sekunden.

1. Die Pipeline startet automatisch. Klicke auf den laufenden Build, um die
   **Live-Ansicht** zu öffnen. Dort siehst du den Fortschritt in Echtzeit.
2. Klicke auf den **Job** (z.B. "Job"), um die Detail-Ansicht der einzelnen
   Steps zu öffnen. Jeder Step lässt sich aufklappen, um die Konsolenausgabe zu
   sehen:
    - **Begrüßung**: Gibt eine einfache Nachricht aus.
    - **Build-Informationen**: Zeigt **vordefinierte Variablen**, die Azure
      Pipelines automatisch setzt. Variablen wie `$(Build.BuildNumber)` oder
      `$(Build.SourceBranchName)` sind in jeder Pipeline verfügbar und liefern
      Kontext über den aktuellen Build.
    - **Agent-Umgebung**: Zeigt, welche Laufzeiten und Tools auf dem
      Microsoft-hosted Agent vorinstalliert sind (Node.js, Python, .NET, Java).
      Diese stehen in jedem Build zur Verfügung, ohne dass du sie installieren
      musst.
    - **Repository-Inhalt**: Zeigt die Dateien im ausgecheckten Repository.
      Azure Pipelines führt vor dem ersten Step automatisch einen
      `git checkout` aus - dein Code steht dem Agent also zur Verfügung.

### Schritt 5: Pipeline auch per CLI starten

Pipelines lassen sich nicht nur über die Web-Oberfläche, sondern auch über die
Azure CLI starten. Das ist nützlich für Automatisierung oder wenn du schnell
einen Build anstoßen willst, ohne den Browser zu wechseln.

```bash
# Zeige alle Pipelines in deinem Projekt an.
# In der Spalte "ID" findest du die numerische Pipeline-ID.
az pipelines list --output table

# Starte die Pipeline manuell (ersetze <pipeline-id> durch die tatsächliche ID
# aus der vorherigen Ausgabe, z. B. 1).
# --branch gibt an, welcher Branch ausgecheckt werden soll.
az pipelines run --id <pipeline-id> --branch main --output table

# Prüfe den Status des letzten Builds.
# --top 1 zeigt nur den neuesten Build an.
az pipelines runs list --top 1 --output table
```

## Validierung

Prüfe sowohl per CLI als auch im Browser, dass alles funktioniert hat:

```bash
# Prüfe, ob die Pipeline existiert und korrekt angelegt wurde.
az pipelines list --output table

# Prüfe den Status des letzten Builds.
# Erwartung: Status "completed" und Result "succeeded".
# Falls Result "failed" ist, klicke im Browser auf den Build, um die
# Fehlerdetails in den Logs zu sehen.
az pipelines runs list --top 1 --output table
```

Öffne im Browser den Bereich **"Pipelines"** in deinem Projekt. Der letzte Build
sollte mit einem grünen Häkchen als erfolgreich markiert sein. Klicke auf den
Build, um die Logs der einzelnen Steps zu inspizieren.
