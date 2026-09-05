# Arbeitsregeln

## Ton

- Knapp. Sag, was zu sagen ist, dann Schluss. Kein Vorgeplänkel, keine
  Zusammenfassung des gerade Getanen, kein „gute Frage“, kein Wiederholen der
  Aufgabe.
- Keine Füll-Adjektive (robust, nahtlos, mächtig, umfassend, produktionsreif).
  Knapp sagen, was der Code tut, nicht wie gut er ist. Nicht paraphrasieren, was
  die nächsten Zeilen tun. Stattdessen das WARUM und WIE erklären, wenn das dem
  Verständnis wirklich hilft.
- Docs und READMEs: was es ist, wie man es nutzt, was es bereitstellt. Sonst
  nichts.
- Commit-Nachrichten: conventional-commit, Imperativ, möglichst einzeilig. Den
  Scope richtig wählen — Release-Tooling routet unter Umständen darüber. Breaking
  Changes bekommen ein `!` (`feat(api)!: …`) oder einen `BREAKING CHANGE:`-Footer.
  Betreffzeile ≤ 72 Zeichen, Imperativ („add“, „fix“, nicht „added“, „fixes“).
  Body auf 72 Zeichen umbrechen.
- Kleine, fokussierte Commits bevorzugen. Release-Tooling leitet Versionssprünge
  und Changelog oft aus den Commit-Betreffzeilen ab.
- Keine Ticket-Nummern in Code, Commits oder Docs.
- Kommentare erklären das *Warum*, nicht das *Was*. Code-Kommentare benennen die
  Absicht oder eine Einschränkung, die der Code nicht zeigen kann. Kommentare
  löschen, die den Code nur wiederholen.
- Kommentare und Docs immer als Ganzes betrachten. Nie nur anhängen. Im Kontext
  prüfen und auf den faktischen Stand bringen. Im Zweifel im Code recherchieren.
  Veraltete und aus dem Kontext gefallene Verweise entfernen, ebenso frühere
  Beobachtungen, Schilderungen von Situationen, die zu einer früheren Änderung
  führten, Maschinennamen oder -adressen sowie jede Vermutung über die
  nachgelagerte Nutzung dieses Repos und seiner Artefakte — abgesehen von
  gültigen, aktuellen Beispielen.
- Auf ein anderes Repository oder Projekt nur verweisen, wenn dessen Zustand der
  unmittelbare Grund für die Änderung ist (ein Dependency-Bump, ein eingespielter
  Fix, ein an eine veröffentlichte Version gebundener API-Vertrag). Kontext für
  Reviewer, Dank oder Querverweise gehören in den PR-Thread oder ein Issue, nicht
  in den Commit.
- Deklarative Fakten schreiben. Keine Personalpronomen („ich“, „wir“, „du“).
  Keine Leseransprache: kein „beachte, dass…“, „wie man sieht…“, „wir haben uns
  entschieden…“, „das sollte helfen…“. Die Regel gilt für Dokumentation, die
  ein Artefakt beschreibt. Ausgenommen sind Folien und Labs, siehe unten.
- Nicht erzählen. Keine Historie, was zuerst versucht wurde, was scheiterte oder
  welche Alternativen erwogen wurden.
- Keine Füll-Verben ohne Konkretes. „Aufräumen“, „verbessern“, „refactoren“
  allein sagen nichts; entweder die tatsächliche Änderung benennen oder die Zeile
  weglassen.
- Keine Checklisten, keine „Summary“-/„Test plan“-Abschnitte, keine
  Marketing-Sprache, keine Emojis.

## Sprache

Alle Materialien dieser Schulung sind auf Deutsch zu formulieren, bis auf Code,
der immer Englisch ist. Bezeichner der Azure-DevOps-Oberfläche bleiben in der
Form, in der sie dort stehen (Variable Group, Approval Gate, Deployment Slot).

## Folien

Neun Marp-Decks unter `slides/<NN-thema>/slides.md`, ein Modul je Deck.
Lehrmaterial, das die Pronomen- und Leseransprache-Regel aufhebt.

- **Geduzt.** „du“, „dir“, „dein“.
- Frontmatter: `header: "Modul NN: Thema"`, `footer: "CC BY-NC-SA 4.0,
  Alexander Erben"`, `paginate: true`.
- Titelfolie ist `# Modul NN`, darunter `## Thema`.
- `## Lernziele` als zweite Folie in allen neun Decks, mit der Einleitung
  „Nach diesem Modul kannst du:“. Jedes Ziel ein fetter Infinitivsatz plus
  Erläuterung nach einem Gedankenstrich.
- Folientitel sind nummeriert (`## 1. Variable-Scopes`), knapp die Hälfte
  aller Folien. Beim Einfügen die Nummern des Abschnitts nachziehen.
- Ein Konzept wird als Liste seiner Ausprägungen aufgeschlüsselt, jede mit
  fettem Namen, Gedankenstrich und einem Satz Erklärung.
- YAML-Beispiele sind lauffähige Ausschnitte einer Pipeline, keine
  Pseudo-Syntax.

## Lab-Anleitungen

22 Labs unter `labs/lab-NN[b]-thema/README.md`. Alle 22 folgen demselben
Aufbau; davon nicht abweichen.

- Geduzt wie die Folien; „wir“ für das gemeinsame Vorgehen im Schritt.
- `## Hintergrund` steht in jedem Lab und ist der längste Teil: Es erklärt
  das Konzept, bevor irgendein Handgriff kommt — welche Arten es gibt, worin
  sie sich unterscheiden, welche Syntax wann greift. Ein Lab, das mit dem
  ersten Klick beginnt, ist unvollständig.
- `## Aufgabenstellung` folgt, gegliedert in `### Schritt N: …`.
- `## Validierung` oder `## Erwartetes Ergebnis` sagt, woran der Erfolg
  erkennbar ist.
- `## Aufräumen` baut die angelegten Azure-Ressourcen wieder ab. Dreizehn der
  22 Labs haben den Abschnitt; jedes Lab, das Ressourcen anlegt, braucht ihn.
- `## Tipps und Troubleshooting` am Ende für die bekannten Fehlerbilder.
- Ein Suffix-Buchstabe markiert ein optionales Zusatzlab (`lab-07b`,
  `lab-13b`).
- Neue Labs in die Tabelle in `labs/README.md` eintragen, mit Schwierigkeit
  und geschätzter Zeit, und in `SCHULUNGSPLAN.md` einplanen.
- Knapp auf Satzebene gilt weiterhin: keine Füll-Adjektive, kein Marketing,
  keine Zusammenfassung des Abschnitts darüber.

## Vor dem Abschluss

- Lint, Tests und Build des Projekts für alles Berührte ausführen.
- `pre-commit run --all-files` laufen lassen und alle Befunde beheben.
- Bei geänderten Pipeline-YAMLs prüfen, dass die Schritte gegen die aktuelle
  Task-Version geschrieben sind (`Docker@2`, `Cache@2`, `AzureWebApp@1`).
- Nicht „fertig“ behaupten, ohne die Prüfung ausgeführt zu haben. Belege vor
  Behauptungen.
- Alle TODO-Marker entfernen, die du in deiner Sitzung hinzugefügt hast, und
  nacharbeiten — oder dem Nutzer sagen, dass ein Follow-up nötig ist. Alle Marker
  und Verweise auf deine eigene Aufgabenliste oder historische Arbeitsschritte
  (P2, P3a, Item 1, Task A usw.) samt ihrer Erzählung entfernen. Wenn wirklich
  etwas offen bleibt, dem Nutzer außerhalb von Code, Docs, Markdown, Kommentaren,
  PR-Beschreibungen, Commit-Nachrichten oder allem anderen in diesem Repo und
  seiner angeschlossenen Pipeline Bescheid geben.

## Aufbau dieses Repos

Dreitägige Schulung „Azure DevOps Pipelines“, neun Module und 22 Labs.

- `slides/01-…` bis `slides/09-…` — die Decks.
- `labs/lab-01-…` bis `labs/lab-20-…` plus `lab-07b` und `lab-13b`, Index in
  `labs/README.md`.
- `SCHULUNGSPLAN.md` — die Zeitplanung über drei Tage, jeweils sechs Stunden.
  Mit *optional* markierte Labs sind Zusatzaufgaben.
- `TRAINER.md` — wie die Teilnehmerkonten und Service Principals aus der
  Terraform-Konfiguration in `internal/azure-setup` abgerufen werden.
- `abschlussprojekt/` — `app` als Ausgangspunkt, `loesung` als Referenz.
- `demos/classic-visual-editor` — die einzige Demo, zum klassischen Editor als
  Kontrast zu YAML.
- `scripts/cleanup-all.sh` — räumt die Azure-Ressourcen eines Teilnehmers ab.

### Modulplan

- Modul 01: Einführung in Azure DevOps (Lab 01)
  - Was ist Azure DevOps? (5 Dienste)
  - Organisation und Projektstruktur
  - Azure CLI und DevOps Extension
- Modul 02: Pipeline-Grundlagen (Labs 02-03)
  - Pipeline als YAML (Anatomie, Tasks, Pools)
  - Trigger-Typen (CI, PR, Schedule, Manual, Pipeline)
  - Branch/Path-Filter
- Modul 03: Variablen und Secrets (Labs 04-05)
  - Variable-Scopes (Job, Stage, Pipeline, Group)
  - Syntax: `$()`, `${{ }}`, `$[]`
  - Parameters vs. Variables, Key Vault Integration
- Modul 04: Multi-Stage Pipelines (Labs 06-07)
  - Pipeline-Hierarchie (Pipeline → Stage → Job → Step)
  - dependsOn, Conditions
  - Artefakte und Output-Variablen
- Modul 05: Containerisierung und Optimierung (Labs 08-10)
  - Docker@2 Task, ACR, Multi-Stage Dockerfiles
  - Cache@2 Task (npm, pip)
  - Matrix-Builds (OS × Version), maxParallel
- Modul 06: Deployment-Strategien (Labs 11-13)
  - Deployment Jobs vs. reguläre Jobs
  - Environments, Approval Gates
  - App Service Deployment (AzureWebApp@1)
- Modul 07: Advanced Deployments (Labs 14-15)
  - Blue/Green mit Deployment Slots
  - Canary Deployments, Rollback-Strategien
  - Lifecycle Hooks
- Modul 08: Infrastructure as Code (Labs 16-18)
  - Terraform: init → plan → apply, Remote State
  - Bicep: Azure-native DSL, what-if
  - Drift Detection
- Modul 09: Fortgeschrittene Themen (Labs 19-21)
  - Self-hosted Agents (Installation, Pools, systemd)
  - Pipeline-Templates (Step, Job, Stage, Variable)
  - Security Scanning (SAST, Dependency, Container, Secrets)

## Fallstricke dieses Repos

- **`solutions/` ist leer.** Es gibt keine Musterlösungen zu den Labs; die
  Abnahme läuft über den `## Validierung`-Abschnitt im Lab. Die einzige
  Referenzlösung im Repo ist `abschlussprojekt/loesung`.
- **Der Modulplan zählt 21 Labs, es liegen 22 im Verzeichnis.** Die
  Zusatzlabs `lab-07b-azure-artifacts` und `lab-13b-container-instances` sind
  dort nicht aufgeführt, und `lab-21` gibt es gar nicht — das letzte ist
  `lab-20-templates`. Der Plan oben ist die fachliche Gliederung, nicht das
  Inhaltsverzeichnis; maßgeblich sind `labs/README.md` und
  `SCHULUNGSPLAN.md`.
- **Die Labs legen echte Azure-Ressourcen an**, auf Konten, die aus
  `internal/azure-setup` provisioniert werden. Ein Lab ohne `## Aufräumen`
  hinterlässt laufende Kosten. `scripts/cleanup-all.sh` ist der Notausstieg.
- **`TRAINER.md` verweist auf ein anderes Repo.** Die Terraform-Konfiguration
  für Teilnehmerkonten liegt in `internal/azure-setup`, nicht hier. Keine
  Zugangsdaten in dieses Repo kopieren.
- **markdownlint erlaubt hier 120 Zeichen**, yamllint 140. Die bestehenden
  Dateien brechen bei rund 80 um; dabei bleiben.
- **Die Linter-Einstellungen stehen doppelt**, in `.gitlab-ci.yml` über die
  Komponenten und lokal in `.pre-commit-config.yaml`. Beide synchron halten.
- **Die CI läuft auf zwei Plattformen.** `.gitlab-ci.yml` bindet die
  GitLab-Komponenten ein, `.github/workflows/ci.yml` ruft `lint.yml`,
  `slides.yml`, `release.yml` und `pages.yml` aus
  `it-erben/ci`. Die PDFs gehen dort auf
  GitHub Pages, ein Deployment gibt es auf GitHub nicht.
