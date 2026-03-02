# Lab 03: Trigger konfigurieren (Branch, Path, Schedule)

## Hintergrund

Trigger bestimmen, **wann** eine Pipeline automatisch gestartet wird. Azure
Pipelines kennt drei Hauptarten:

- **CI-Trigger (trigger)**: Reagiert auf Pushes in bestimmte Branches oder bei
  Änderungen an bestimmten Dateipfaden.
- **PR-Trigger (pr)**: Reagiert auf Pull Requests gegen bestimmte Branches.
- **Scheduled Trigger (schedules)**: Startet die Pipeline zu festen Zeiten (
  Cron-Syntax).

Durch Kombinieren dieser Trigger sparst du Build-Minuten und stellst
sicher, dass nur relevante Änderungen einen Build auslösen.

## Aufgabenstellung

### Schritt 1: Feature-Branch erstellen

Um die verschiedenen Trigger-Konfigurationen zu testen, brauchen wir einen
separaten Branch. In einem typischen Git-Workflow entwickelt man neue Features
in **Feature-Branches**, die erst nach einem Review per Pull Request in `master`
gemerged werden.

Wechsle in das Verzeichnis deines `hello-pipeline`-Repositories und erstelle
einen Feature-Branch:

```bash
# Erstelle einen neuen Branch namens "feature/add-css" und wechsle direkt
# hinein. Der Branch basiert auf dem aktuellen Stand von master.
git checkout -b feature/add-css
```

### Schritt 2: Pipeline mit erweiterten Triggern anlegen

Ersetze den gesamten Inhalt von `azure-pipelines.yml` mit der folgenden
Konfiguration. Die neue Version definiert drei Trigger-Arten:

- **`trigger`** (CI-Trigger): Reagiert auf Pushes. Mit `branches.include` und
  `branches.exclude` legst du fest, welche Branches einen Build auslösen.
  Mit `paths.include` und `paths.exclude` kannst du zusätzlich filtern, ob
  sich relevante Dateien geändert haben - z.B. soll ein reiner
  Dokumentations-Commit keinen Build auslösen.
- **`pr`** (Pull-Request-Trigger): Reagiert auf Pull Requests gegen bestimmte
  Branches. Auch hier lassen sich Pfad-Filter setzen.
- **`schedules`** (Zeitplan-Trigger): Startet die Pipeline zu festen Zeiten
  per Cron-Syntax. Nützlich z. B. für nächtliche Integrationstests.

```yaml
# Pipeline mit verschiedenen Trigger-Konfigurationen
trigger:
  branches:
    include:
      - master
      - release/*
    exclude:
      - feature/experimental-*
  paths:
    include:
      - src/*
      - azure-pipelines.yml
    exclude:
      - '*.md'
      - docs/*

pr:
  branches:
    include:
      - master
  paths:
    exclude:
      - '*.md'

schedules:
  - cron: '0 6 * * Mon-Fri'
    displayName: 'Werktags um 06:00 UTC'
    branches:
      include:
        - master
    always: false  # Nur ausführen, wenn es Änderungen gab

pool:
  vmImage: 'ubuntu-22.04'

steps:
  - script: |
      echo "=== Trigger-Informationen ==="
      echo "Build Reason: $(Build.Reason)"
      echo "Source Branch: $(Build.SourceBranch)"
      echo "Source Branch Name: $(Build.SourceBranchName)"
      echo ""
      if [ "$(Build.Reason)" = "IndividualCI" ]; then
        echo "Dieser Build wurde durch einen Push ausgelöst."
      elif [ "$(Build.Reason)" = "PullRequest" ]; then
        echo "Dieser Build wurde durch einen Pull Request ausgelöst."
      elif [ "$(Build.Reason)" = "Schedule" ]; then
        echo "Dieser Build wurde durch einen Zeitplan ausgelöst."
      elif [ "$(Build.Reason)" = "Manual" ]; then
        echo "Dieser Build wurde manuell ausgelöst."
      fi
    displayName: 'Trigger-Analyse'

  - script: |
      echo "=== Geänderte Dateien ==="
      echo "Hinweis: Bei CI-Builds zeigt dies die Änderungen im letzten Commit"
      git diff --name-only HEAD~1 HEAD 2>/dev/null || echo "(Erster Commit oder kein Vergleich möglich)"
    displayName: 'Geänderte Dateien anzeigen'
```

### Schritt 3: Projektstruktur anlegen

Um die Path-Filter sinnvoll testen zu können, brauchen wir eine realistische
Verzeichnisstruktur. Wir legen einen `src/`-Ordner für Anwendungscode und
einen `docs/`-Ordner für Dokumentation an. Gemäß unserer Trigger-Konfiguration
sollen Änderungen in `src/` einen Build auslösen, Änderungen in `docs/` oder
an `*.md`-Dateien hingegen nicht.

Erstelle die folgenden Verzeichnisse und Dateien:

**Bash:**

```bash
# Verzeichnisse erstellen (-p sorgt dafür, dass kein Fehler auftritt,
# falls die Verzeichnisse schon existieren)
mkdir -p src docs
```

**PowerShell:**

```powershell
# Verzeichnisse erstellen (-Force sorgt dafür, dass kein Fehler auftritt,
# falls die Verzeichnisse schon existieren)
New-Item -ItemType Directory -Force -Path src, docs | Out-Null
```

**src/app.js** - eine einfache JavaScript-Datei als Beispiel-Anwendungscode:

```javascript
console.log("Hello from the app!");
```

**docs/README.md** - Projektdokumentation, die keinen Build auslösen soll:

```markdown
# Hello Pipeline Dokumentation

Dies ist die Projektdokumentation.
```

**src/style.css** - ein Stylesheet, das im `src/`-Ordner liegt und damit
Build-relevant ist:

```css
body {
    font-family: Arial, sans-serif;
    background-color: #f0f0f0;
}

h1 {
    color: #333;
}
```

### Schritt 4: Verschiedene Trigger testen

In diesem Schritt führen wir vier Tests durch, um das Zusammenspiel
von Branch- und Path-Filtern zu verstehen. Nach jedem Test prüfst du in Azure
DevOps unter **Pipelines**, ob ein neuer Build ausgelöst wurde oder nicht.

**Test 1: Push auf Feature-Branch (sollte NICHT triggern)**

Füge alle oben erstellten Dateien mit `git add` dem Index hinzu und erstelle
einen Commit:

```bash
git add src/app.js src/style.css docs/README.md azure-pipelines.yml
git commit -m "Add project structure and update triggers"
git push origin feature/add-css
```

Prüfe in Azure DevOps unter **Pipelines**: Es sollte **kein** neuer Build
gestartet werden. Der Grund: In der `trigger`-Konfiguration sind unter
`branches.include` nur `master` und `release/*` aufgeführt - der Branch
`feature/add-css` ist nicht enthalten und wird daher ignoriert.

**Test 2: Push auf master (sollte triggern)**

Wechsle auf den Branch `master` und merge den Feature-Branch:

```bash
git checkout master
git merge feature/add-css
git push origin master
```

Prüfe in Azure DevOps: Es sollte ein Build gestartet werden. Der Branch
`master` ist in `branches.include` enthalten, und es wurden Dateien unter `src/`
geändert, die in `paths.include` erfasst sind. Beide Bedingungen müssen
gleichzeitig erfüllt sein.

**Test 3: Nur Dokumentation ändern (sollte NICHT triggern)**

Öffne die Datei `docs/README.md` und füge eine beliebige neue Zeile hinzu
(z.B. `Dies ist ein Testabsatz.`). Committe und pushe:

```bash
git add docs/README.md
git commit -m "Update documentation"
git push origin master
```

Prüfe in Azure DevOps: Es sollte **kein** Build gestartet werden. Zwar ist der
Branch `master` im Include, aber die geänderte Datei liegt unter `docs/*` und
hat die Endung `*.md` - beides ist in `paths.exclude` ausgeschlossen. Path-
Excludes haben Vorrang: Wenn alle geänderten Dateien ausgeschlossen sind, wird
kein Build ausgelöst.

**Test 4: Pipeline-Datei ändern (sollte triggern)**

Öffne `azure-pipelines.yml` und füge am Anfang der Datei eine Kommentarzeile
hinzu (z. B. `# Trigger-Test`). Kommentare beginnen in YAML mit `#` und haben
keinen Einfluss auf die Pipeline-Logik:

```bash
git add azure-pipelines.yml
git commit -m "Add comment to pipeline file"
git push origin master
```

Prüfe in Azure DevOps: Ein Build wird gestartet, da `azure-pipelines.yml`
explizit in `paths.include` aufgeführt ist. Es ist eine gute Praxis, die
Pipeline-Datei selbst in den Path-Filter aufzunehmen, damit Änderungen an der
Build-Konfiguration direkt getestet werden.

## Validierung

Prüfe per CLI, welche Builds ausgelöst wurden und aus welchem Grund:

```bash
# Zeige die letzten 5 Builds an. In der Spalte "Reason" siehst du den
# Auslöser (z. B. "individualCI" für einen Push-Trigger, "manual" für
# manuell gestartete Builds).
az pipelines runs list --top 5 --output table

# Für detailliertere Informationen zu einem bestimmten Build kannst du
# die Run-ID aus der obigen Tabelle verwenden (ersetze <run-id>):
az pipelines runs show --id <run-id> --output json | jq
```

## Erwartetes Ergebnis

```
# az pipelines runs list --top 5 --output table
Run ID  Number      Status     Result     Source Branch
------  ----------  ---------  ---------  -------------------
3       20260222.3  completed  succeeded  refs/heads/master       # Test 4
2       20260222.2  completed  succeeded  refs/heads/master       # Test 2
1       20260222.1  completed  succeeded  refs/heads/master       # Lab 02
```

Beachte: Test 1 (Feature-Branch) und Test 3 (nur Doku) sollten **keine** Builds
ausgelöst haben.

## Aufräumen

Da der Feature-Branch gemerged wurde, wird er nicht mehr benötigt. Lösche ihn
sowohl lokal als auch auf dem Remote, um die Branch-Liste sauber zu halten:

```bash
# Lokalen Branch löschen (-d prüft, ob der Branch gemerged wurde;
# bei einem ungemergeden Branch müsstest du -D verwenden)
git branch -d feature/add-css

# Remote-Branch in Azure DevOps löschen
git push origin --delete feature/add-css
```
