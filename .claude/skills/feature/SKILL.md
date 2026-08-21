---
name: feature
description: Orchestriert ein Feature end-to-end durch die feste Pipeline requirements -> architecture -> tests (RED) -> implementation -> code-review -> QA (GREEN) -> Draft-PR. Nutze dies, wenn der User `/feature <beschreibung>` tippt, ein neues nicht-triviales Feature möchte ("baue …", "implementiere …") oder explizit das "Agent-Team" verlangt. NICHT für Typos, Einzeiler-Bugfixes oder reine Fragen.
---

# /feature — Agent-Team-Pipeline

Du steuerst als **Haupt-Agent** ein Feature durch eine strikte, sequentielle
Pipeline mit Bestätigungs-Gates. Subagenten liefern Spezifikation, Plan, Review
und QA — **die Implementierung machst du selbst und delegierst sie nicht**
(du hast den vollen Konversationskontext; jedes Handoff kostet Kontext).

## Wann nutzen / wann nicht

**Nutzen:** neues Feature, neue Integration, Refactor über mehrere Dateien,
alles was Schema + Backend + UI zugleich berührt, oder wenn der User es
explizit verlangt.

**Nicht nutzen:** Typo oder Einzeiler-Fix (direkt fixen), Bugfix oder
kleines Refactoring mit klarem Ziel (-> `/fix`), reines
Dependency-Update, fehlender Test für bereits gebauten Code (`qa-engineer`
direkt aufrufen), Exploration/Q&A (direkt beantworten).

## Preconditions (Hard-Stop)

Prüfe vor dem Start beide Voraussetzungen; fehlt eine, stoppe sofort und
bootstrappe sie NIE als Nebenprodukt eines Feature-Laufs:

1. **Test-Infrastruktur** — die QA-Phase schreibt und **führt** echte Tests
   aus. Es braucht einen konfigurierten Test-Runner UND mindestens eine
   Testdatei im Repo. Fehlt sie, frage den User:

   > "Die /feature-Pipeline braucht funktionierende Test-Infrastruktur. Soll
   > ich die zuerst mit `/bootstrap` aufsetzen (eigene Aufgabe), bevor wir
   > das Feature starten?"

2. **Lint-Gate** — verify.sh, CI und QA linten nur, was existiert. Es braucht
   einen eingerichteten Linter (Node: `lint`-Script in `package.json`;
   Python: ruff in den Dev-Dependencies; andere Stacks:
   `.claude/hooks/verify-project.sh` vorhanden). Fehlt er, frage den User:

   > "Das Projekt hat kein Lint-Gate — verify.sh, CI und QA würden ohne
   > Linter laufen. Soll ich zuerst mit `/bootstrap` einen einrichten
   > (eigene Aufgabe)?"

## Slug-Ableitung

Leite aus dem User-Argument einen kebab-case-`<slug>` ab (Kleinbuchstaben,
Bindestriche, keine Sonderzeichen). Alle Artefakte leben unter
`docs/features/<slug>/`. Nenne den Slug dem User zu Beginn; bei Unklarheit
per `AskUserQuestion` klären.

## Pipeline — strikte Reihenfolge, keine Parallelisierung

### 1. Requirements (`requirements-engineer`)

Delegiere via `Agent`-Tool. Übergib: die User-Anfrage wörtlich, den Slug, den
Artefakt-Pfad. Ergebnis: `docs/features/<slug>/requirements.md`.

Wenn der Agent zurückkommt: **LIES die Datei selbst** (nicht der Zusammenfassung
vertrauen), präsentiere dem User 3–5 Bullets + alle offenen Fragen
(`AskUserQuestion` bei offenen Fragen).

> **GATE 1 — echte User-Bestätigung (Pflicht).** Erst nach klarem
> "ok/weiter/passt" geht es zu Schritt 2. Bei Änderungswunsch: Agent
> nachbessern lassen, erneut fragen.

### 2. Architecture (`solution-architect`)

Delegiere mit Slug + Verweis auf die freigegebene `requirements.md`.
Ergebnis: `docs/features/<slug>/architecture.md`.

Wenn fertig: Datei selbst lesen, präsentiere Ansatz (3–5 Sätze), Affected
Files (Zahlen), Risiken. Verlangt der Plan **neue Dependencies** oder
**Schema-/`CLAUDE.md`-Änderungen**, weise explizit darauf hin.

> **GATE 2 — echte User-Bestätigung (Pflicht).** Erst nach klarem OK zu Schritt 3.

### 3. Tests zuerst (`qa-engineer`, RED-Phase)

Delegiere mit Slug + Verweis auf die freigegebene `architecture.md` und dem
expliziten Hinweis **RED-Phase**. Der Agent schreibt pro Acceptance Criterion
echte Tests gegen die geplanten Schnittstellen, führt sie aus und meldet sie
**rot** zurück — die Implementierung existiert noch nicht.

- Rot ist hier das Erfolgskriterium: Ein Test, der schon jetzt grün ist,
  prüft das Feature nicht (er testet Bestand oder gar nichts).
- Ist ein AC gegen die geplanten Schnittstellen nicht testbar, ist das ein
  Architektur-Problem — zurück zu Schritt 2, nicht weiterlaufen.

### 4. Implementation — DU, der Haupt-Agent

Setze den freigegebenen Plan **selbst** um:
- Ziel ist, die RED-Tests aus Schritt 3 grün zu machen — ohne sie
  abzuschwächen oder zu löschen.
- Halte dich an die Affected Files und nutze die gelisteten Reused Utilities.
- Respektiere Konventionen und harte Grenzen aus `CLAUDE.md`.
- Verfolge Multi-File-Arbeit mit der Task-Liste.
- Findest du mittendrin eine Anforderungslücke: dem User vorlegen — nicht
  stillschweigend füllen.

Fasse am Ende zusammen, was sich geändert hat (Pfade, Kernentscheidungen).

### 5. Code Review (`code-reviewer`)

Delegiere mit Slug + Hinweis, dass die Implementierung auf dem aktuellen
Branch liegt. Ergebnis: `docs/features/<slug>/code-review.md` mit Verdict.

- **APPROVED** -> weiter zu Schritt 6.
- **NEEDS_CHANGES** -> arbeite die Required Fixes selbst ein, dann
  `code-reviewer` erneut. Nie mit offenen Fixes weitergehen.
  **Maximal 3 Review-Zyklen** (NEEDS_CHANGES -> Fix -> Re-Review). Ist das
  dritte Re-Review nicht APPROVED, stoppe und eskaliere per
  `AskUserQuestion`: nochmal fixen, zurück zur Architektur (Schritt 2), oder
  abbrechen? Drei erfolglose Runden sind fast nie „eine Runde hat gefehlt",
  sondern ein Zeichen, dass das Problem nicht auf Code-Ebene liegt —
  weiterkreisen verbrennt Kontext, ohne zu konvergieren.
- **BLOCKED** -> stoppe, lege es dem User vor (`AskUserQuestion`): zurück zu
  Schritt 1 (Requirements) oder Schritt 2 (Architektur)?

### 6. QA (`qa-engineer`, GREEN-Phase)

Delegiere mit Slug + Hinweis auf das APPROVED-Review und dem expliziten
Hinweis **GREEN-Phase**. Der Agent verifiziert die RED-Tests aus Schritt 3
gegen den tatsächlichen Diff, ergänzt Edge-Case-Tests, finalisiert
`qa-plan.md` und führt Lint/Typecheck/Tests aus.

- Fehlschlag "needs implementer fix" -> du fixt selbst, dann `code-reviewer`
  re-verifizieren (ein Fix kann neue Drift einführen), dann QA erneut.
- Fehlschlag "needs requirements clarification" -> User fragen, zurück zu
  Schritt 1 mit der Klärung.

### 7. Draft-PR

Erst wenn Review APPROVED **und** QA grün:
- Branch: falls auf `main`/`master`, zuerst Feature-Branch anlegen
  (`claude/<slug>`).
- Committe Produktivcode + Tests + die vier Artefakte aus
  `docs/features/<slug>/`. Conventional-Commit-Message
  (`feat:`/`fix:`/`docs:`/`test:`/`chore:`).
- Push (`git push -u origin <branch>`), dann PR **als Draft** gegen den
  Default-Branch. PR-Body: Link auf `requirements.md`, Liste der Acceptance
  Criteria, Liste der Testdateien.
- **Manuelle Prüfschritte in den PR-Body übernehmen.** Lies den Abschnitt
  "Manuelle Verifikation (MC)" aus `qa-plan.md` und übertrage jeden Eintrag
  als Checkbox — mit "Tun" und "Erwartet", damit man ihn ohne Umweg über die
  Artefakte abarbeiten kann:

  ```markdown
  ## Selbst prüfen, bevor der PR aus dem Draft geht
  - [ ] **MC-1: <Kurztitel>**
        Tun: <Befehl/Klickpfad> — Erwartet: <Soll-Ergebnis>
  ```

  Steht dort "Keine.", schreibe stattdessen "Keine manuelle Prüfung nötig."
  Erfinde niemals eigene MC-Einträge und lasse keinen weg.
- **Enthält der Diff Migrationen/Schema-Änderungen**, füge dem PR-Body eine
  Checkbox mit dem manuellen Nach-Merge-Schritt hinzu (z. B. Migration
  anwenden), sofern `CLAUDE.md` sagt, dass Migrationen nicht auto-deployed
  werden.
- Melde die PR-URL. Nenne dabei die offenen MC-Punkte als das, was noch auf
  den User wartet. Frage NICHT ungefragt nach dem Mergen.

## Eiserne Regeln

- Reihenfolge strikt; kein Schritt vor seinem Gate; Gates 1+2 erfordern
  **echte** User-Bestätigung — nie selbst annehmen.
- Implementierung wird **nie** an einen Subagenten delegiert.
- Die RED-Phase nie überspringen, und rote Tests nie durch Abschwächen grün
  machen — grün wird ausschließlich durch Implementierung.
- Subagenten-Grenzen respektieren: requirements/architect/reviewer schreiben
  keinen Code, qa schreibt nur Testcode.
- Testfehlschläge nie beerdigen — fixen oder dem User vorlegen. Kein PR mit
  roten Tests.
- Review-Schritt nie überspringen: Tests prüfen *Verhalten*, das Review prüft
  *Passung* — beides ist Pflicht vor dem PR.
- Maximal 3 Review-Zyklen, dann eskalieren (`AskUserQuestion`) — nie
  unbegrenzt zwischen Fix und Re-Review kreisen.
- PR ist immer **Draft**. Er verlässt den Draft-Status erst, wenn alle
  MC-Checkboxen abgehakt sind — das kann nur der User, nie du. Hake sie
  niemals selbst ab und setze den PR nie selbst auf "Ready for Review".
- Verletzt irgendetwas eine harte Grenze aus `CLAUDE.md`: stoppen und fragen.
