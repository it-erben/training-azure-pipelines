# Demo: Klassischer visueller Editor für Azure Pipelines

## Einleitung

Bevor YAML-Pipelines zum Standard wurden, bot Azure DevOps einen **visuellen
Editor** (auch „Classic Editor" genannt) zum Erstellen von Build- und
Release-Pipelines. Über eine grafische Oberfläche konnten Tasks per
Drag-and-Drop zusammengestellt, Trigger konfiguriert und Variablen verwaltet
werden — ganz ohne eine einzige Zeile YAML.

Microsoft empfiehlt seit mehreren Jahren die Verwendung von YAML-Pipelines.
Der klassische Editor wird jedoch weiterhin unterstützt und begegnet einem in
der Praxis regelmäßig:

- **Legacy-Projekte**, die vor der YAML-Ära aufgesetzt wurden
- **Teams**, die den visuellen Ansatz bevorzugen oder noch nicht migriert haben
- **Release-Pipelines**, für die es in YAML kein vollständig gleichwertiges
  Pendant gibt (z. B. grafische Approval Gates)

Diese Demo zeigt den klassischen Editor, damit die Teilnehmer ihn einordnen
können, wenn sie ihm in der Praxis begegnen. Die gesamte Schulung arbeitet
weiterhin ausschließlich mit YAML-Pipelines.

---

## Voraussetzungen

- Azure-DevOps-Organisation **iterben** mit Zugang zum Projekt
- Repository **hello-pipeline** (angelegt in Lab 01/02) mit mindestens einer
  Datei im `main`-Branch
- **Bei aktuellen Versionen von Azure DevOps müssen Classic Pipelines erst 
  aktiviert werden**. Dies geht über die **Settings** der Organisation im
  Menüpunkt **Pipelines > Settings**. Dort sind zwei Schalter, die 
  standardmäßig Classic Pipelines deaktiveren. Diese Schalter müssen
  **ausgeschaltet** werden.

---

## Teil 1: Klassische Build-Pipeline erstellen

### Schritt 1: Neues Pipeline-Projekt über den klassischen Editor anlegen

1. Öffne das Projekt im Browser unter <https://dev.azure.com/iterben>.
2. Navigiere im linken Menü zu **Pipelines > Pipelines**.
3. Klicke auf **"New pipeline"**.
4. Auf der Seite **"Where is your code?"** klicke unten auf den Link
   **"Use the classic editor"**.

### Schritt 2: Repository auswählen

1. Wähle als Quelle **Azure Repos Git**.
2. Wähle das Projekt und das Repository **hello-pipeline**.
3. Wähle den Branch **main** (bzw. **master**, falls so benannt).
4. Klicke auf **"Continue"**.

### Schritt 3: Template auswählen

1. Auf der Template-Seite wähle **"Empty job"**.

### Schritt 4: Agent-Pool konfigurieren

1. Klicke auf **"Agent job 1"** in der Pipeline-Ansicht.
2. Unter **Agent pool** wähle **Azure Pipelines**.
3. Unter **Agent Specification** wähle **ubuntu-22.04**.

### Schritt 5: Tasks hinzufügen

**Task 1 — Command Line:**

1. Klicke auf das **+**-Symbol neben **Agent job 1**.
2. Suche nach **"Command Line"** und füge den Task hinzu.
3. Konfiguriere den Task:
   - **Display name:** `Echo-Nachricht`
   - **Script:** `echo "Hello from Classic Pipeline!"`

**Task 2 — Copy Files:**

1. Klicke erneut auf **+** neben **Agent job 1**.
2. Suche nach **"Copy Files"** und füge den Task hinzu.
3. Konfiguriere den Task:
   - **Source Folder:** `$(Build.SourcesDirectory)`
   - **Contents:** `**`
   - **Target Folder:** `$(Build.ArtifactStagingDirectory)`

**Task 3 — Publish Build Artifacts:**

1. Füge den Task **"Publish Build Artifacts"** hinzu.
2. Konfiguriere den Task:
   - **Path to publish:** `$(Build.ArtifactStagingDirectory)`
   - **Artifact name:** `drop`
   - **Artifact publish location:** `Azure Pipelines`

### Schritt 6: Trigger konfigurieren

1. Wechsle zum Tab **"Triggers"**.
2. Aktiviere **"Enable continuous integration"**.
3. Unter **Branch filters** füge den Branch `main` hinzu.
4. Optional: Unter **Path filters** einen Include-Pfad hinzufügen,
   z. B. `/src`.

### Schritt 7: Variablen anlegen

1. Wechsle zum Tab **"Variables"**.
2. Klicke auf **"+ Add"** und lege eine Variable an:
   - **Name:** `environment`
   - **Value:** `demo`
3. Zeige die Option **"Settable at queue time"** — damit kann der Wert beim
   manuellen Starten überschrieben werden.

### Schritt 8: Pipeline speichern und starten

1. Klicke auf **"Save & queue"** > **"Save & queue"**.
2. Im Dialog optional einen Kommentar eingeben und auf **"Save and run"**
   klicken.
3. Beobachte den Build-Lauf: Klicke auf den **Agent job**, um die
   Live-Ausgabe der Tasks zu sehen.

---

## Teil 2: Klassische Release-Pipeline erstellen

### Schritt 1: Neue Release-Pipeline anlegen

1. Navigiere zu **Pipelines > Releases**.
2. Klicke auf **"New pipeline"**.
3. Wähle das Template **"Empty job"**.

### Schritt 2: Artifact hinzufügen

1. Klicke im Pipeline-Diagramm auf **"+ Add an artifact"**.
2. Wähle als Source type **Build**.
3. Wähle die zuvor erstellte klassische Build-Pipeline als **Source**.
4. Belasse die Standard-Einstellungen und klicke auf **"Add"**.

### Schritt 3: Dev-Stage konfigurieren

1. Klicke auf **"Stage 1"** und benenne sie um in **"Dev"**.
2. Klicke auf den Link **"1 job, 0 task"** innerhalb der Stage.
3. Klicke auf **+** neben **Agent job** und füge einen **Command Line**-Task
   hinzu:
   - **Display name:** `Deploy to Dev`
   - **Script:** `echo "Deploying to Dev environment..."`
4. Stelle den **Agent pool** auf **Azure Pipelines** /
   **ubuntu-22.04**.

### Schritt 4: Pre-Deployment Approval für Dev hinzufügen

1. Kehre zur Pipeline-Übersicht zurück.
2. Klicke auf das **Blitz-/Personen-Symbol** links neben der Stage **Dev**.
3. Aktiviere **"Pre-deployment approvals"**.
4. Füge einen Approver hinzu (z. B. den eigenen Account).

### Schritt 5: Prod-Stage hinzufügen

1. Klicke auf **"+ Add"** neben der Dev-Stage, um eine neue Stage
   hinzuzufügen.
2. Wähle **"Empty job"** und benenne die Stage **"Prod"**.
3. Konfiguriere einen **Command Line**-Task:
   - **Display name:** `Deploy to Prod`
   - **Script:** `echo "Deploying to Prod environment..."`
4. Klicke auf das **Blitz-/Personen-Symbol** links neben **Prod**.
5. Aktiviere **"Pre-deployment approvals"** und füge einen Approver hinzu.

### Schritt 6: Continuous-Deployment-Trigger aktivieren

1. Klicke auf das **Blitz-Symbol** am Artifact (oben rechts am
   Artifact-Kasten).
2. Aktiviere den **"Continuous deployment trigger"**.
3. Füge einen Branch-Filter hinzu: `main`.

### Schritt 7: Release erstellen und Approval-Workflow durchspielen

1. Klicke auf **"Create release"** > **"Create"**.
2. Öffne das erstellte Release.
3. Die Dev-Stage wartet auf Genehmigung — klicke auf **"Approve"**.
4. Beobachte, wie die Dev-Stage durchläuft.
5. Anschließend wartet die Prod-Stage auf Genehmigung — klicke erneut auf
   **"Approve"**.
6. Beobachte den vollständigen Release-Durchlauf.
