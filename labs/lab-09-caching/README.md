# Lab 09: Caching-Strategien

## Hintergrund

Pipelines, die bei jedem Lauf alle Abhängigkeiten erneut herunterladen und
installieren (`npm ci`, `pip install`, `nuget restore`), verschwenden Zeit und
Bandbreite. Bei einem typischen Node.js-Projekt mit vielen Abhängigkeiten dauert
`npm ci` 20–40 Sekunden - bei jedem einzelnen Lauf.

Der `Cache@2`-Task in Azure Pipelines speichert Verzeichnisse zwischen
Pipeline-Läufen. Beim nächsten Lauf wird der Cache wiederhergestellt, sofern
sich der **Cache-Key** nicht geändert hat. Der Cache-Key ist ein
zusammengesetzter Schlüssel, der typischerweise aus einem festen Präfix, dem
Betriebssystem des Agents und dem Hash einer Lock-Datei besteht. Ändert sich die
Lock-Datei (weil z.B. eine neue Abhängigkeit hinzukommt), ändert sich auch der
Key - und der Cache wird neu aufgebaut.

Zusätzlich zum exakten Key unterstützt der Task sogenannte **Restore-Keys**:
Falls der exakte Key nicht gefunden wird, sucht Azure Pipelines nach dem
neuesten Cache, dessen Key mit einem der Restore-Keys **beginnt**. So bekommst
du zumindest einen teilweisen Cache, selbst wenn sich die Abhängigkeiten
geändert haben - die meisten Pakete stammen ja noch aus dem alten Cache.

### Was cachen?

Es gibt zwei Strategien:

1. **Download-Cache** (`~/.npm`, `~/.cache/pip`): Der Paketmanager lädt Pakete
   nicht erneut herunter, muss sie aber trotzdem extrahieren und installieren.
   Die Zeitersparnis ist gering, weil die Installation (Entpacken, Linking,
   Dateioperationen) den Großteil der Zeit ausmacht.
2. **Installationsverzeichnis** (`node_modules`, `venv`): Das gesamte Ergebnis
   der Installation wird gecacht. Bei einem Cache-Hit wird die Installation
   komplett übersprungen. Die Zeitersparnis ist drastisch - von 20–40 Sekunden
   auf unter 1 Sekunde.

Wir verwenden in diesem Lab Strategie 2, weil sie den Caching-Effekt deutlich
sichtbar macht. Der `Cache@2`-Task bietet dafür den Parameter `cacheHitVar`:
Er setzt eine Variable auf `true`, wenn der exakte Cache-Key gefunden wurde.
Mit einer `condition` auf dem Install-Step können wir die Installation bei
Cache-Hit überspringen.

## Aufgabenstellung

### Schritt 1: Projekt mit Abhängigkeiten vorbereiten

Um Caching sinnvoll zu demonstrieren, brauchen wir ein Projekt mit echten
npm-Abhängigkeiten. Bisher hat unser `hello-pipeline`-Projekt keine externen
Pakete verwendet. Jetzt fügen wir einige gängige Abhängigkeiten hinzu, damit
`npm ci` messbar Zeit benötigt.

Ersetze den Inhalt von **package.json** mit folgender Version, die mehrere
Abhängigkeiten mit vielen transitiven Paketen enthält:

```json
{
  "name": "hello-pipeline",
  "version": "1.0.0",
  "description": "Demo-App für Caching-Lab",
  "main": "src/app.js",
  "scripts": {
    "build": "echo 'Building...' && mkdir -p dist && cp src/*.js dist/ && cp index.html dist/",
    "test": "node test/test.js",
    "lint": "echo 'Lint OK'"
  },
  "dependencies": {
    "express": "^4.18.2",
    "dotenv": "^16.3.1",
    "axios": "^1.6.0",
    "lodash": "^4.17.21",
    "moment": "^2.30.1",
    "winston": "^3.11.0"
  },
  "devDependencies": {
    "jest": "^29.7.0",
    "typescript": "^5.3.3",
    "webpack": "^5.89.0",
    "webpack-cli": "^5.1.4",
    "eslint": "^8.56.0"
  }
}
```

Diese Kombination bringt mehrere hundert transitive Abhängigkeiten mit. `webpack`,
`typescript` und `eslint` sind besonders schwergewichtige Pakete.

Erzeuge nun die **package-lock.json**, die als Grundlage für den Cache-Key
dient. Die Lock-Datei fixiert die exakten Versionen aller transitiven
Abhängigkeiten. Führe dazu lokal `npm install` aus:

```bash
npm install
```

Der `Cache@2`-Task verwendet den Hash dieser Datei als Teil des Cache-Keys.
Ändert sich die Lock-Datei, ändert sich der Key - und der Cache wird neu
aufgebaut.

Erstelle außerdem eine **requirements.txt** für das Python-Caching-Beispiel im
zweiten Job. Diese Datei listet Python-Pakete mit festen Versionen:

```
requests==2.31.0
flask==3.0.0
pytest==7.4.3
pandas==2.1.4
boto3==1.34.0
pydantic==2.5.3
```

### Schritt 2: Pipeline mit Caching

Jetzt erstellen wir eine Pipeline mit zwei parallelen Jobs, die jeweils den
`Cache@2`-Task verwenden: einen für Node.js und einen für Python. Beide
verwenden dieselbe Strategie: das Installationsverzeichnis cachen und die
Installation bei Cache-Hit überspringen.

Ersetze den Inhalt von `azure-pipelines.yml`:

```yaml
trigger:
  branches:
    include:
      - master

stages:
  - stage: BuildWithCache
    displayName: 'Build mit Caching'
    jobs:

      # ===== Job 1: Node.js mit node_modules-Cache =====
      - job: NodeBuild
        displayName: 'Node.js Build (cached)'
        pool:
          vmImage: 'ubuntu-latest'
        variables:
          cacheHit: 'false'
        steps:
          - task: NodeTool@0
            inputs:
              versionSpec: '20.x'
            displayName: 'Node.js installieren'

          # node_modules aus dem Cache wiederherstellen
          - task: Cache@2
            displayName: 'node_modules Cache'
            inputs:
              key: 'node_modules | "$(Agent.OS)" | package-lock.json'
              path: 'node_modules'
              cacheHitVar: 'cacheHit'

          - script: |
              echo "=== Cache-Status ==="
              echo "cacheHitVar = $(cacheHit)"
              if [ -d node_modules ]; then
                echo "node_modules existiert"
                echo "Pakete: $(ls node_modules | wc -l)"
                echo "Größe: $(du -sh node_modules | cut -f1)"
              else
                echo "Kein Cache vorhanden (erster Lauf)"
              fi
            displayName: 'Cache-Status prüfen'

          # npm ci nur ausführen, wenn KEIN exakter Cache-Hit
          - script: |
              echo "=== npm ci (kein Cache-Hit) ==="
              START=$(date +%s%N)
              npm ci 2>&1
              END=$(date +%s%N)
              DURATION=$(( (END - START) / 1000000 ))
              echo "Dauer: ${DURATION} ms"
            displayName: 'npm ci'
            condition: ne(variables.cacheHit, 'true')

          - script: |
              echo "=== Cache-Hit: npm ci übersprungen ==="
              echo "node_modules wurde aus dem Cache wiederhergestellt."
              echo "Pakete: $(ls node_modules | wc -l)"
            displayName: 'Cache-Hit bestätigen'
            condition: eq(variables.cacheHit, 'true')

          - script: npm run build
            displayName: 'Build ausführen'

      # ===== Job 2: Python mit venv-Cache =====
      - job: PythonBuild
        displayName: 'Python Build (cached)'
        pool:
          vmImage: 'ubuntu-latest'
        variables:
          cacheHit: 'false'
        steps:
          # Virtualenv aus dem Cache wiederherstellen
          - task: Cache@2
            displayName: 'venv Cache'
            inputs:
              key: 'venv | "$(Agent.OS)" | requirements.txt'
              path: '.venv'
              cacheHitVar: 'cacheHit'

          - script: |
              echo "=== pip install (kein Cache-Hit) ==="
              python -m venv .venv
              source .venv/bin/activate
              START=$(date +%s%N)
              pip install -r requirements.txt 2>&1
              END=$(date +%s%N)
              DURATION=$(( (END - START) / 1000000 ))
              echo "Dauer: ${DURATION} ms"
            displayName: 'pip install'
            condition: ne(variables.cacheHit, 'true')

          - script: |
              echo "=== Cache-Hit: pip install übersprungen ==="
              source .venv/bin/activate
              echo "Installierte Pakete:"
              pip list --format=columns | head -20
            displayName: 'Cache-Hit bestätigen'
            condition: eq(variables.cacheHit, 'true')

  - stage: ComparePerformance
    displayName: 'Cache-Vergleich'
    dependsOn: BuildWithCache
    jobs:
      - job: ShowCacheInfo
        displayName: 'Cache-Informationen'
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - script: |
              echo "=== Caching-Erklärung ==="
              echo ""
              echo "Beim ERSTEN Pipeline-Lauf:"
              echo "  - Kein Cache vorhanden (cacheHitVar = false)"
              echo "  - npm ci / pip install laufen normal"
              echo "  - node_modules / .venv werden am Ende gecacht"
              echo ""
              echo "Bei FOLGENDEN Läufen (gleiche Lock-Datei):"
              echo "  - Cache wird wiederhergestellt (cacheHitVar = true)"
              echo "  - npm ci / pip install werden ÜBERSPRUNGEN"
              echo "  - Zeitersparnis: 20-40 Sekunden pro Job"
              echo ""
              echo "Bei GEÄNDERTEN Abhängigkeiten:"
              echo "  - Cache-Key ändert sich (Lock-Datei-Hash anders)"
              echo "  - npm ci / pip install laufen erneut"
              echo "  - Neuer Cache wird gespeichert"
            displayName: 'Cache-Strategie erklären'
```

Gehe die Pipeline Abschnitt für Abschnitt durch:

- **Cache-Key** (`key: 'node_modules | "$(Agent.OS)" | package-lock.json'`):
  Der Key besteht aus drei Teilen, getrennt durch `|`: einem festen Präfix
  (`node_modules`), dem Betriebssystem des Agents (`$(Agent.OS)`) und dem
  **Hash** der Datei `package-lock.json`. Azure Pipelines berechnet den
  SHA-256-Hash der Datei automatisch. Der OS-Teil stellt sicher, dass Linux-
  und Windows-Agents getrennte Caches verwenden, da native Module
  plattformspezifisch kompiliert werden.
- **`cacheHitVar`**: Der Parameter `cacheHitVar: 'cacheHit'` weist den
  `Cache@2`-Task an, eine Pipeline-Variable `cacheHit` zu setzen. Der Wert ist
  `true`, wenn der **exakte** Cache-Key gefunden wurde, sonst `false` (auch
  bei Restore-Key-Treffern). So können wir die Installation konditionell
  überspringen.
- **`condition`**: Der Step `npm ci` hat die Bedingung
  `condition: ne(variables.cacheHit, 'true')` - er läuft nur, wenn **kein**
  exakter Cache-Hit vorliegt. Bei Cache-Hit wird stattdessen der
  Bestätigungs-Step ausgeführt, der anzeigt, dass `node_modules` aus dem Cache
  stammt.
- **Warum `node_modules` statt `~/.npm`?** Der npm-Download-Cache (`~/.npm`)
  speichert nur die heruntergeladenen Tarballs. `npm ci` muss trotzdem jedes
  Paket extrahieren und in `node_modules` installieren - das dauert fast
  genauso lang wie der Download selbst. Durch Caching von `node_modules`
  direkt wird die gesamte Installation übersprungen.
- **Python-Job**: Zeigt dasselbe Muster für pip mit einem gecachten virtualenv.
  Bei Cache-Hit ist `.venv` sofort verfügbar, ohne `pip install`.
- **ComparePerformance-Stage**: Eine rein informative Stage, die das
  Caching-Verhalten zusammenfasst.

### Schritt 3: Committen und zweimal ausführen

Der Caching-Effekt zeigt sich erst beim zweiten Lauf: Beim ersten Lauf wird der
Cache aufgebaut, beim zweiten Lauf wird er wiederhergestellt. Daher führen wir
die Pipeline bewusst zweimal aus.

```bash
git add package.json package-lock.json requirements.txt azure-pipelines.yml
git commit -m "Add caching to pipeline"
git push origin master
```

**Warte, bis der erste Build vollständig abgeschlossen ist.**
Der Cache wird erst nach Abschluss aller Jobs gespeichert. Ein zweiter Lauf 
während des ersten findet also noch keinen Cache. 

Starte dann einen zweiten Build manuell:

```bash
# Pipeline-ID herausfinden
az pipelines list --output table

# Zweiten Build starten (ersetze <pipeline-id> durch die ID
# aus der vorherigen Ausgabe)
az pipelines run --id <pipeline-id> --branch master
```

### Schritt 4: Build-Zeiten vergleichen

Öffne beide Pipeline-Runs im Browser und vergleiche die Logs:

1. **Erster Lauf**: Im Step "node_modules Cache" siehst du die Meldung
   `Cache not found for input keys`. Der Step "npm ci" läuft und dauert
   typischerweise 20–40 Sekunden.
2. **Zweiter Lauf**: Im Step "node_modules Cache" siehst du
   `Cache restored from key: node_modules | "Linux" | <hash>`. Der Step
   "npm ci" wird **komplett übersprungen** (als "skipped" markiert). Stattdessen
   läuft der Step "Cache-Hit bestätigen", der die Anzahl der wiederhergestellten
   Pakete anzeigt.

Die gleiche Beobachtung kannst du für den Python-Job machen: `pip install`
wird beim zweiten Lauf übersprungen, `.venv` stammt aus dem Cache.

## Validierung

Prüfe per CLI, dass beide Runs erfolgreich waren:

```bash
# Beide Runs vergleichen
az pipelines runs list --top 2 --output table
```

Öffne im Browser die Logs beider Runs und prüfe:

- **Step "node_modules Cache"**: Zeigt beim ersten Lauf `Cache not found`,
  beim zweiten Lauf `Cache restored`.
- **Step "npm ci"**: Beim ersten Lauf ausgeführt (20–40 Sekunden), beim
  zweiten Lauf als **skipped** markiert.
- **Step "Cache-Hit bestätigen"**: Beim zweiten Lauf ausgeführt, zeigt
  Anzahl der Pakete in `node_modules`.

## Aufräumen

Kein Aufräumen nötig. Pipeline-Caches werden automatisch nach 7 Tagen ohne
Verwendung gelöscht. Du kannst die Cache-Nutzung einer Pipeline unter
**Pipelines > <Pipeline-Name> > ... > Cache** einsehen.
