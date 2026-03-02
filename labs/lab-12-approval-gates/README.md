# Lab 12: Approval Gates und Checks

## Hintergrund

In den bisherigen Labs wurden alle Deployments automatisch ausgeführt, sobald
die vorherige Stage erfolgreich war. In produktionsnahen Szenarien ist das zu
riskant: Ein fehlerhafter Build könnte direkt in Production landen, ohne dass
jemand die Staging-Testergebnisse geprüft hat. Außerdem möchte man bestimmte
Regeln erzwingen - z.B. dass nur der `master`-Branch nach Production deployt
werden darf oder dass Deployments nur während der Geschäftszeiten stattfinden.

Azure DevOps löst das über **Approvals and Checks**, die auf Environments
konfiguriert werden. Jedes Mal, wenn eine Pipeline ein Deployment auf ein
geschütztes Environment starten will, werden die konfigurierten Checks
ausgewertet. Die Pipeline pausiert, bis alle Checks bestanden sind:

- **Approvals**: Eine oder mehrere benannte Personen müssen das Deployment
  manuell freigeben. Die Pipeline zeigt einen "Review"-Button, und die Approver
  erhalten optional eine E-Mail-Benachrichtigung. Erst nach der Freigabe läuft
  die Deployment-Stage weiter. Bei einer Ablehnung ("Reject")
  wird die Stage als fehlgeschlagen markiert.
- **Branch Control**: Erlaubt Deployments nur von bestimmten Branches (z. B.
  `refs/heads/master`). Wenn jemand versucht, von einem Feature-Branch nach
  Production zu deployen, blockiert dieser Check automatisch - ohne dass ein
  Mensch eingreifen muss.
- **Business Hours**: Erlaubt Deployments nur während definierter Zeitfenster
  (z. B. werktags 8–18 Uhr). Außerhalb dieser Zeiten wird das Deployment in eine
  Warteschlange gestellt und startet automatisch, sobald das Zeitfenster wieder
  offen ist.
- **Exclusive Lock**: Stellt sicher, dass immer nur ein Deployment gleichzeitig
  auf einem Environment läuft. Wenn ein zweites Deployment startet, während das
  erste noch läuft, wartet es, bis das erste abgeschlossen ist.

Diese Mechanismen werden auf dem **Environment** konfiguriert, nicht in der
Pipeline-YAML-Datei. Das hat einen wichtigen Vorteil: Die Regeln gelten für
**alle** Pipelines, die auf dieses Environment deployen - unabhängig davon, wer
die Pipeline geschrieben hat. Ein Entwickler kann die Checks nicht umgehen,
indem er die YAML-Datei ändert.

## Voraussetzungen

Dieses Lab baut auf Lab 11 auf. Du brauchst:

- Die drei Environments `dev`, `staging` und `production` aus Lab 11.
- Die Pipeline mit Deployment Jobs aus Lab 11. Wir verwenden dieselbe Pipeline
  und ändern sie in diesem Lab nicht - die Checks werden ausschließlich über die
  Web-Oberfläche konfiguriert.

## Aufgabenstellung

### Schritt 1: Approval Gate für Production einrichten

Das wichtigste Gate: Bevor ein Deployment nach Production läuft, muss ein Mensch
es freigeben. So stellst du sicher, dass jemand die Staging-Testergebnisse
geprüft hat und bewusst die Entscheidung trifft, die neue Version live zu
schalten.

1. Gehe zu **Pipelines > Environments**.
2. Klicke auf **"production"**.
3. Klicke **"Approvals and checks"**. Es öffnet sich die Übersicht der
   konfigurierten Checks (zunächst leer).
4. Klicke auf **"+"**
5. Wähle **"Approvals"** aus der Liste der Check-Typen.
6. Konfiguriere den Approval:
    - **Approvers**: Füge dich selbst hinzu (und optional einen Kollegen). Du
      kannst einzelne Benutzer, Gruppen oder Teams als Approver angeben.
    - **Instructions**: Gib eine Anweisung ein, die der Approver beim Freigeben
      sieht, z.B.:
      `Bitte prüfe die Staging-Testergebnisse, bevor du das Production-Deployment freigibst.`
    - Klappe **"Advanced"** auf und konfiguriere:
        - **Allow approvers to approve their own runs**: **Ja** (Haken setzen).
          Normalerweise sollte der Entwickler, der den Code gepusht hat, nicht
          selbst freigeben - für das Training erlauben wir das, da du
          wahrscheinlich alleine arbeitest.
        - **Timeout**: `1440` Minuten (24 Stunden). Wird die Freigabe nicht
          innerhalb dieser Zeit erteilt, wird die Pipeline automatisch
          abgebrochen.
7. Klicke auf **"Create"**.

### Schritt 2: Branch Control Check hinzufügen

Dieser Check stellt sicher, dass nur Deployments vom `master`-Branch nach
Production gelangen. Selbst wenn jemand die `condition` in der Pipeline-YAML-
Datei entfernt, blockiert dieser Check das Deployment von Feature-Branches.

1. Du bist weiterhin unter **"Approvals and checks"** für das
   Production-Environment.
2. Klicke auf **"+ Add new"** > **"Branch control"**.
3. **Allowed branches**: Gib `refs/heads/master` ein. Du kannst hier auch
   Wildcards verwenden (z. B. `refs/heads/release/*`), um mehrere Branches
   zuzulassen.
4. **Verify branch protection**: Optional. Wenn aktiviert, prüft Azure DevOps
   zusätzlich, ob auf dem Branch Branch-Policies aktiv sind (z.B. Pflicht-
   Reviews). Für das Training kannst du das deaktiviert lassen.
5. Klicke auf **"Create"**.

### Schritt 3: Exclusive Lock hinzufügen

Der Exclusive Lock verhindert, dass zwei Deployments gleichzeitig auf Production
laufen. Das ist wichtig, weil parallele Deployments zu inkonsistenten Zuständen
führen können - z.B. wenn ein Deployment die Datenbank migriert, während ein
anderes noch die alte Schema-Version erwartet.

1. Unter **"Approvals and checks"** für das Production-Environment.
2. Klicke auf **"+ Add new"** > **"Exclusive lock"**.
3. **Timeout**: `60` Minuten. Wenn ein Deployment länger als 60 Minuten auf die
   Freigabe des Locks wartet, wird es automatisch abgebrochen.
4. Klicke auf **"Create"**.

Du solltest jetzt unter **"Approvals and checks"** drei Einträge sehen:
Approvals, Branch control und Exclusive lock.

### Schritt 4: Staging mit Business-Hours-Check einrichten

Um auch automatisierte Checks zu demonstrieren, konfigurieren wir einen
Business-Hours-Check auf dem Staging-Environment. Dieser Check erlaubt
Deployments nur während der Geschäftszeiten.

1. Gehe zurück zu **Pipelines > Environments** und klicke auf **"staging"**.
2. Klicke auf **"Approvals and checks"** > **"+"**.
3. Wähle **"Business Hours"**.
4. Konfiguriere:
    - **Time zone**: `(UTC+01:00) Amsterdam, Berlin, Bern...`
    - **Business days**: Montag bis Freitag.
    - **Start time**: `08:00`.
    - **End time**: `18:00`.
5. Klicke auf **"Create"**.

Wenn du dieses Lab außerhalb der konfigurierten Geschäftszeiten bearbeitest,
wird der Check das Staging-Deployment blockieren. In diesem Fall kannst du den
Check vorübergehend löschen und später wiederherstellen, oder die Zeiten
anpassen. Alternativ kannst du die Zeiten auf `00:00` bis `23:59` setzen, um den
Check zu demonstrieren, ohne blockiert zu werden.

### Schritt 5: Pipeline ausführen und Approval erleben

Die Pipeline aus Lab 11 referenziert die Environments `dev`, `staging` und
`production`. Da wir auf diesen Environments jetzt Checks konfiguriert haben,
wird die Pipeline an den entsprechenden Stellen pausieren.

Um die Pipeline zu triggern, machen wir eine kleine Änderung am Code. Öffne
`src/app.js` und füge am Ende eine Kommentarzeile hinzu (z. B.
`// Approval flow test`). Committe und pushe die Änderung:

```bash
git add src/app.js
git commit -m "Trigger approval flow"
git push origin master
```

### Schritt 6: Approval erteilen

Öffne den Pipeline-Run im Browser und beobachte den Ablauf:

1. Die Stages **Build** und **Deploy Dev** laufen automatisch durch, da auf dem
   `dev`-Environment keine Checks konfiguriert sind.
2. **Deploy Staging** wird durch den Business-Hours-Check geprüft. Innerhalb der
   konfigurierten Zeiten läuft die Stage automatisch weiter. Außerhalb der
   Zeiten siehst du eine Wartemeldung.
3. Vor **Deploy Production** pausiert die Pipeline. Du siehst einen
   **"Review"**-Button oder die Meldung **"Waiting for approval"**. Azure DevOps
   prüft gleichzeitig den Branch-Control-Check (der automatisch bestanden wird,
   da wir von `master` deployen) und den Exclusive-Lock-Check
   (der bestanden wird, da kein anderes Deployment läuft).
4. Klicke auf **"Review"**. Es öffnet sich ein Dialog mit:
    - Den konfigurierten **Instructions** ("Bitte prüfe die
      Staging-Testergebnisse...").
    - Einem **Kommentarfeld**, in dem du optional einen Grund für die Freigabe
      oder Ablehnung angeben kannst.
    - Den Buttons **"Approve"** und **"Reject"**.
5. Klicke auf **"Approve"**. Die Production-Stage startet jetzt.
6. Optional: Starte die Pipeline noch einmal und klicke auf **"Reject"**, um zu
   sehen, wie die Stage als fehlgeschlagen markiert wird.

### Schritt 7: Approval-Historie prüfen

Nach dem Approval kannst du die Historie einsehen:

1. Gehe zu **Pipelines > Environments > production**.
2. Unter **"Deployments"** siehst du das aktuelle Deployment mit Status
   "Succeeded".
3. Klicke auf das Deployment - im Detail siehst du, wer den Approval erteilt hat
   und wann.

Du kannst offene Approvals auch per CLI abfragen:

```bash
# Laufende und wartende Runs anzeigen
az pipelines runs list --query "[?status=='notStarted' || status=='inProgress']" --output table
```

## Aufräumen

Entferne den Business-Hours-Check vom Staging-Environment, damit er die
folgenden Labs nicht blockiert:

1. Gehe zu **Environments > staging > Approvals and checks**.
2. Klicke auf den Business-Hours-Check.
3. Klicke auf die drei Punkte (**...**) > **"Delete"**.

Die anderen Checks (Approval, Branch Control, Exclusive Lock) können auf dem
Production-Environment bestehen bleiben. Sie stören die folgenden Labs nicht, da
du bei jedem Production-Deployment einfach auf "Approve" klickst. Falls du die
Checks doch stören, kannst du sie jederzeit unter **Environments >
production > Approvals and checks** entfernen.
