---
name: feature
description: Orchestriert ein Feature end-to-end durch die feste Pipeline requirements -> architecture -> implementation -> code-review -> QA -> Draft-PR. Nutze dies, wenn der User `/feature <beschreibung>` tippt, ein neues nicht-triviales Feature möchte ("baue …", "implementiere …") oder explizit das "Agent-Team" verlangt. NICHT für Typos, Einzeiler-Bugfixes oder reine Fragen.
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

### 3. Implementation — DU, der Haupt-Agent

Setze den freigegebenen Plan **selbst** um:
- Halte dich an die Affected Files und nutze die gelisteten Reused Utilities.
- Respektiere Konventionen und harte Grenzen aus `CLAUDE.md`.
- Verfolge Multi-File-Arbeit mit der Task-Liste.
- Findest du mittendrin eine Anforderungslücke: dem User vorlegen — nicht
  stillschweigend füllen.

Fasse am Ende zusammen, was sich geändert hat (Pfade, Kernentscheidungen).

### 4. Code Review (`code-reviewer`)

Delegiere mit Slug + Hinweis, dass die Implementierung auf dem aktuellen
Branch liegt. Ergebnis: `docs/features/<slug>/code-review.md` mit Verdict.

- **APPROVED** -> weiter zu Schritt 5.
- **NEEDS_CHANGES** -> arbeite die Required Fixes selbst ein, dann
  `code-reviewer` erneut, bis APPROVED. Nie mit offenen Fixes weitergehen.
- **BLOCKED** -> stoppe, lege es dem User vor (`AskUserQuestion`): zurück zu
  Schritt 1 (Requirements) oder Schritt 2 (Architektur)?

### 5. QA (`qa-engineer`)

Delegiere mit Slug + Hinweis auf das APPROVED-Review. Der Agent schreibt
`qa-plan.md` + echte Tests und führt Lint/Typecheck/Tests aus.

- Fehlschlag "needs implementer fix" -> du fixt selbst, dann `code-reviewer`
  re-verifizieren (ein Fix kann neue Drift einführen), dann QA erneut.
- Fehlschlag "needs requirements clarification" -> User fragen, zurück zu
  Schritt 1 mit der Klärung.

### 6. Draft-PR

Erst wenn Review APPROVED **und** QA grün:
- Branch: falls auf `main`/`master`, zuerst Feature-Branch anlegen
  (`claude/<slug>`).
- Committe Produktivcode + Tests + die vier Artefakte aus
  `docs/features/<slug>/`. Conventional-Commit-Message
  (`feat:`/`fix:`/`docs:`/`test:`/`chore:`).
- Push (`git push -u origin <branch>`), dann PR **als Draft** gegen den
  Default-Branch. PR-Body: Link auf `requirements.md`, Liste der Acceptance
  Criteria, Liste der Testdateien.
- **Enthält der Diff Migrationen/Schema-Änderungen**, füge dem PR-Body eine
  Checkbox mit dem manuellen Nach-Merge-Schritt hinzu (z. B. Migration
  anwenden), sofern `CLAUDE.md` sagt, dass Migrationen nicht auto-deployed
  werden.
- Melde die PR-URL. Frage NICHT ungefragt nach dem Mergen.

## Eiserne Regeln

- Reihenfolge strikt; kein Schritt vor seinem Gate; Gates 1+2 erfordern
  **echte** User-Bestätigung — nie selbst annehmen.
- Implementierung wird **nie** an einen Subagenten delegiert.
- Subagenten-Grenzen respektieren: requirements/architect/reviewer schreiben
  keinen Code, qa schreibt nur Testcode.
- Testfehlschläge nie beerdigen — fixen oder dem User vorlegen. Kein PR mit
  roten Tests.
- Review-Schritt nie überspringen: Tests prüfen *Verhalten*, das Review prüft
  *Passung* — beides ist Pflicht vor dem PR.
- PR ist immer **Draft**.
- Verletzt irgendetwas eine harte Grenze aus `CLAUDE.md`: stoppen und fragen.
