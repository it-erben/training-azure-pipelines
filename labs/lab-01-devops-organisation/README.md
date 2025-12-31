# Lab 01: Azure DevOps Organisation und Projekt anlegen

## Hintergrund

Azure DevOps ist die zentrale Plattform von Microsoft für
Software-Entwicklungsteams. Sie bietet Boards (Projektmanagement), Repos (
Git-Repositories), Pipelines (CI/CD), Test Plans und Artifacts. Alles beginnt
mit einer **Organisation**, die als Container für alle Projekte dient. Ein *
*Projekt** bündelt Repos, Pipelines und Boards zu einer logischen Einheit.

In diesem Lab lernst du dein vorbereitetes Projekt kennen und richtest dein
erstes Repository ein. Alle folgenden Labs bauen darauf auf.

## Aufgabenstellung

### Schritt 1: Bei Azure DevOps Organisation anmelden

Eine **Organisation** ist die oberste Verwaltungsebene in Azure DevOps. Sie
gehört typischerweise einem Unternehmen oder Team und enthält alle Projekte,
Benutzer und Abrechnungsinformationen. Für dieses Training wurde bereits eine
Organisation namens `iterben` eingerichtet.

1. Öffne im Browser: <https://dev.azure.com/iterben/>
2. Melde dich mit deinem Azure-Account an (dem Account, der für das Training
   freigeschaltet wurde).
3. Du landest auf dem **Organisations-Dashboard**. Hier siehst du eine Übersicht
   aller Projekte, auf die du Zugriff hast. Wenn du dich zum ersten Mal
   anmeldest, kann die Liste noch leer sein.

### Schritt 2: Dein Projekt kennenlernen

Ein **Projekt** ist der zentrale Arbeitsbereich innerhalb einer Organisation. Es
bündelt Repositories, Pipelines, Boards und Artifacts zu einer logischen
Einheit - vergleichbar mit einem Workspace für ein Softwareprodukt oder ein
Team.

Für jeden Teilnehmer wurde bereits ein eigenes Projekt per Terraform
bereitgestellt. Dein Projekt heißt so wie dein Benutzername (z. B.
`teilnehmer01`). Du findest es auf dem Organisations-Dashboard.

1. Suche dein Projekt auf dem Dashboard und klicke darauf.
2. Mache dich mit der Oberfläche vertraut: Links findest du die Bereiche
   **Boards**, **Repos**, **Pipelines**, **Test Plans** und **Artifacts**.

### Schritt 3: Azure CLI mit DevOps verbinden

Neben der Web-Oberfläche lässt sich Azure DevOps auch über die **Azure CLI**
steuern. Das ist nützlich, um Pipelines zu starten, Repos zu
erstellen oder Build-Ergebnisse abzufragen, ohne den Browser öffnen zu
müssen. Die Azure CLI ist ein Kommandozeilen-Tool, das lokal auf deinem Rechner
läuft und sich per Access Token mit Azure verbindet.

Öffne **Git Bash** und führe die folgenden Befehle nacheinander aus:

**Bash:**
```bash
# Ersetze hier deine Teilnehmernummer (z. B. "01")
TEILNEHMER_NR="<deine nummer>"

PROJECT_NAME="teilnehmer$TEILNEHMER_NR"
ORGANIZATION="iterben"
```

**PowerShell:**
```powershell
# Ersetze hier deine Teilnehmernummer (z. B. "01")
$TEILNEHMER_NR = "<deine nummer>"

$PROJECT_NAME = "teilnehmer$TEILNEHMER_NR"
$ORGANIZATION = "iterben"
```

```bash
# Die Azure CLI hat ein Plugin-System. Die DevOps-Befehle (az devops, az repos,
# az pipelines) sind als Extension ausgelagert und müssen einmalig installiert
# werden. --yes überspringt die Bestätigungsabfrage.
az extension add --name azure-devops --yes

# Wir setzen die aktive Azure-Subscription, damit alle nachfolgenden Befehle
# im richtigen Abrechnungskontext laufen. Die ID identifiziert die
# Trainings-Subscription.
az account set --subscription "30b490cd-637c-4934-87a7-a38eba455adf"
```

**Bash:**
```bash
# Damit du nicht bei jedem CLI-Aufruf Organisation und Projekt angeben musst,
# setzen wir beides als Default. Diese Einstellung wird in
# ~/.azure/config gespeichert und gilt für alle zukünftigen CLI-Aufrufe.
az devops configure --defaults \
  organization=https://dev.azure.com/$ORGANIZATION \
  project=$PROJECT_NAME
```

**PowerShell:**
```powershell
# Damit du nicht bei jedem CLI-Aufruf Organisation und Projekt angeben musst,
# setzen wir beides als Default. Diese Einstellung wird in
# ~/.azure/config gespeichert und gilt für alle zukünftigen CLI-Aufrufe.
az devops configure --defaults `
  organization=https://dev.azure.com/$ORGANIZATION `
  project=$PROJECT_NAME
```

### Schritt 4: Git einrichten

Bevor du mit Repositories arbeiten kannst, muss Git lokal konfiguriert werden.
Dazu gehören dein Name und deine E-Mail-Adresse (werden in Commits angezeigt)
sowie die Authentifizierung gegenüber Azure DevOps.

```bash
# Git muss wissen, wer du bist. Diese Angaben erscheinen in jedem Commit.
git config --global user.name "Teilnehmer $TEILNEHMER_NR"
git config --global user.email "teilnehmer${TEILNEHMER_NR}@infoiterben.onmicrosoft.com"
```

Für die Authentifizierung bei `git clone`, `git push` etc. nutzen wir den
**Git Credential Manager (GCM)**, der bei Git for Windows / Git Bash bereits
enthalten ist. Er öffnet beim ersten Zugriff ein Browserfenster, in dem du dich
mit deinem Azure-Account anmeldest. Danach werden die Zugangsdaten im
Windows Credential Manager gespeichert und automatisch wiederverwendet.

Prüfe, ob GCM aktiv ist:

```bash
git config --global credential.helper
```

Die Ausgabe sollte `manager` oder `manager-core` sein. Falls nicht, aktiviere
ihn:

```bash
git config --global credential.helper manager
```

### Schritt 5: Erstes Repository erstellen

Beim Anlegen eines Projekts wird automatisch ein Standard-Repository mit dem
Projektnamen erzeugt. Für unsere Pipeline-Übungen erstellen wir ein separates,
dediziertes Repository namens `hello-pipeline`. Ein Projekt kann beliebig
viele Repositories enthalten.

**Bash:**
```bash
REPO_NAME="hello-pipeline"
```

**PowerShell:**
```powershell
$REPO_NAME = "hello-pipeline"
```

```bash
# Erstelle ein neues, leeres Git-Repository in Azure DevOps.
# --output table formatiert die Ausgabe als lesbare Tabelle.
az repos create --name "$REPO_NAME" --output table

# Klone das (noch leere) Repository auf deinen lokalen Rechner.
# Dabei wird ein Ordner "hello-pipeline" im aktuellen Verzeichnis angelegt.
git clone https://dev.azure.com/$ORGANIZATION/$PROJECT_NAME/_git/$REPO_NAME
cd hello-pipeline
```

Die Ausgabe sollte etwa wie folgt aussehen:

```terminaloutput
ID                                    Name            Default Branch    Project
------------------------------------  --------------  ----------------  ---------
47dd4b45-6ae8-45d6-a67f-12d40c693656  hello-pipeline                    ae-labs
Cloning into 'hello-pipeline'...
warning: You appear to have cloned an empty repository.
```

Die Warnung "empty repository" ist normal, denn das Repository enthält noch
keine Commits. Den Default Branch (`main`) legt Git automatisch beim ersten Push
an.

### Schritt 6: Beispieldatei anlegen und pushen

Jetzt fügen wir dem Repository eine erste Datei hinzu. Die folgende
HTML-Datei dient uns in den folgenden Labs als Beispiel-Datei, das von der
Pipeline verarbeitet werden kann.

Lege folgende Datei an:

**index.html**
```bash
# Einfache HTML-Seite erstellen - das wird unser "Anwendungscode"
<!DOCTYPE html>
<html>
<head><title>Hello Pipeline</title></head>
<body><h1>Hello from Azure Pipelines!</h1></body>
</html> 
```

Committe und pushe sie dann:

```bash
# Datei zur Staging Area hinzufügen, committen und auf Azure DevOps pushen.
# Beim ersten Push wird automatisch der Branch "main" als Default Branch
# im Remote-Repository angelegt.
git add index.html
git commit -m "Initial commit: add index.html"
git push origin main
```

Falls du beim Push nach Zugangsdaten gefragt wirst, öffnet sich ein
Browserfenster (Git Credential Manager). Melde dich dort mit deinem
Azure-Account an. Die Credentials werden danach automatisch gespeichert.

## Validierung

Zum Abschluss prüfen wir, ob alles korrekt eingerichtet wurde - sowohl per CLI
als auch im Browser:

**Bash:**
```bash
# Zeigt die Details deines Projekts an (Name, ID, Status).
# Wenn dieser Befehl funktioniert, sind Organisation und Projekt korrekt
# als Defaults konfiguriert.
az devops project show --project $PROJECT_NAME --output table

# Listet alle Repositories in deinem Projekt auf.
# Du solltest mindestens zwei sehen: das automatisch erstellte Standard-Repo
# und das manuell erstellte "hello-pipeline".
az repos list --output table
```

**PowerShell:**
```powershell
# Zeigt die Details deines Projekts an (Name, ID, Status).
# Wenn dieser Befehl funktioniert, sind Organisation und Projekt korrekt
# als Defaults konfiguriert.
az devops project show --project $PROJECT_NAME --output table

# Listet alle Repositories in deinem Projekt auf.
# Du solltest mindestens zwei sehen: das automatisch erstellte Standard-Repo
# und das manuell erstellte "hello-pipeline".
az repos list --output table
```

Öffne zusätzlich im Browser die Organisation
<https://dev.azure.com/iterben>, navigiere zu deinem Projekt und öffne den
Bereich **Repos**. Dort solltest du das Repository `hello-pipeline` mit der
Datei `index.html` im Branch `main` sehen können.
