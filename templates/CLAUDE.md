# CLAUDE.md

Kontextdatei für Claude Code. Vor jeder Aufgabe lesen.
<!-- Alle <PLATZHALTER> ausfüllen; nicht zutreffende Abschnitte löschen,
     nicht leer stehen lassen. -->

## Projektbeschreibung

<WAS das Projekt ist, für WEN, und was es KONKRET tut — 2 bis 4 Sätze.
Beispiel: "X ist ein web-basiertes Tool, das Daten aus A importiert,
B berechnet und C anzeigt.">

## Tech Stack

- **Sprache/Runtime**: <z. B. TypeScript + React 18 + Vite | Python 3.12 + uv>
- **UI**: <z. B. shadcn/ui + Tailwind — oder "keins (CLI)">
- **Daten/Backend**: <z. B. Supabase (PostgreSQL, Edge Functions) | SQLite | Dateien>
- **Externe Dienste**: <APIs, LLMs, SMTP … — oder "keine">
- **Tests**: <z. B. Vitest | pytest> · **Lint**: <z. B. ESLint | ruff (+ mypy)>

## Projektstruktur

```
<Kompakter Verzeichnisbaum mit 1-Zeilen-Zweck pro Eintrag. Nur die Ebenen,
die man zum Navigieren braucht. Auto-generierte Verzeichnisse markieren.>
```

## Harte Grenzen (nicht verhandelbar)

<Nur aufnehmen, was wirklich hart ist — Verstöße sind im Code-Review
automatisch BLOCKED. Abschnitt löschen, wenn es keine gibt. Beispiele:>
- <z. B. READ-ONLY: niemals Mails senden / Daten löschen / … >
- <z. B. Kein Cloud-LLM im Laufzeitpfad>
- <z. B. Keine PII ins Repo: Nutzdaten, Outputs und .env werden nie committet>
- <z. B. Ressourcen-Limits: Modellgröße, num_ctx, Speicher>

## Arbeitsweise

Verhaltensregeln gegen typische LLM-Fehler. Bei trivialen Aufgaben mit
Augenmaß anwenden.

**Erst denken, dann coden**
- Annahmen explizit benennen. Bei Unsicherheit nachfragen statt raten.
- Mehrdeutigkeiten offenlegen, nicht still eine Variante wählen.
- Gibt es einen einfacheren Weg, sag es. Begründeter Widerspruch ist erwünscht.

**Einfachheit zuerst**
- Minimaler Code, der das Problem löst. Nichts Spekulatives.
- Keine Features über das Verlangte hinaus, keine Abstraktion für
  Einmal-Code, keine ungefragte „Flexibilität".
- Kein Error-Handling für unmögliche Fälle.
- Eine Datei/Klasse, eine Kernverantwortung: würde eine Änderung einer
  bestehenden Einheit eine zweite, fachfremde Verantwortung anbauen,
  stattdessen einen Split vorschlagen. Abstraktion auf Vorrat (Interfaces,
  Schichten „für später") bleibt trotzdem tabu.
- Faustregel: Würde ein Senior das als überkompliziert bezeichnen?
  Dann vereinfachen.

**Chirurgische Änderungen**
- Diffs minimal halten: kein Refactoring, keine Formatierung, keine
  Kommentare an Code, der nicht zur Aufgabe gehört.
- Bestehenden Stil übernehmen, auch wenn du es anders machen würdest.
- Nur durch die eigene Änderung verwaiste Imports/Variablen/Funktionen
  entfernen. Vorhandenen Dead Code nur melden, nicht ungefragt löschen.

**Zielgetriebene Umsetzung**
- Aufgaben in prüfbare Ziele übersetzen: „Validierung hinzufügen" →
  „Tests für ungültige Eingaben schreiben, dann grün machen".
- Bei mehrstufigen Aufgaben kurzen Plan nennen, je Schritt mit Verifikation.

## Konventionen

- **Sprache**: <z. B. UI-Texte Deutsch, Code + Kommentare Englisch>
- **Typisierung**: <z. B. Type Hints auf allen Signaturen | kein `any`>
- **Struktur**: <z. B. Prompts als Textdateien in `prompts/`, nicht inline |
  Datenzugriff nur über Hooks in `src/hooks/`, keine Direktzugriffe in Komponenten>
- **Im Klartext**: Bei Findings mit Entscheidungsbedarf (Review-Ergebnisse,
  Security-Punkte, Risiken) immer zusätzlich in nicht-technischer Sprache
  erklären, was das Problem für Nutzer/Betreiber konkret bedeutet — als
  eigene Spalte oder Satz. Reine Referenz-Tabellen (Dateilisten,
  Coverage-Maps) brauchen das nicht.
- **Secrets**: keine Secrets im Code — Konfiguration über `.env`
  (siehe `.env.example`); echte Werte nur lokal bzw. im Secret-Store des
  Deploy-Ziels.
- **Commits**: Conventional Commits (`feat:` / `fix:` / `docs:` / `test:` / `chore:`)
- **Auto-generierte Dateien**: <welche — nie manuell editieren; oder "keine">

## Build & Dev Commands

<Diese Befehle sind die verbindlichen Gates — CI, der Stop-Hook
(.claude/hooks/verify.sh) und der qa-engineer führen genau diese aus.>

```bash
<install>        # z. B. npm install | uv sync --extra dev
<dev>            # z. B. npm run dev (localhost:8080) | python main.py
<lint>           # z. B. npm run lint | uv run ruff check .
<typecheck>      # z. B. npx tsc -b --noEmit | uv run mypy src  (falls vorhanden)
<test>           # z. B. npm test | uv run pytest -q
<build>          # z. B. npm run build  (falls vorhanden)
```

## Environment Variables

`.env.example` nach `.env` kopieren und ausfüllen:

```
<VAR_NAME>=      # wofür, wo man den Wert bekommt
```

<Falls zutreffend: welche Secrets NICHT in .env leben, sondern im
Dashboard/Secret-Store des Deploy-Ziels konfiguriert werden.>

## Sicherheitsmodell

<Wie Auth/Zugriff funktioniert, in 3–6 Bullets. Beispiele: welches
Auth-Muster neue Endpunkte nutzen MÜSSEN; wie DB-Zugriffe abgesichert sind
(RLS o. Ä.); was bewusst öffentlich ist. Abschnitt löschen, wenn das Projekt
keine Angriffsfläche hat.>

Secret-Schutz (Defense in Depth, generisch eingerichtet):
0. `permissions.deny` in `.claude/settings.json` blockt direkte Lesezugriffe
   von Claude auf `.env`-Dateien/Keys; der Hook
   `.claude/hooks/protect-secrets.sh` blockt Schreibzugriffe darauf (beides
   Best-Effort — indirekte Wege sind nicht vollständig abgedeckt; die harten
   Garantien liefern die Schichten 1–4).
1. Claude-Hook `.claude/hooks/secret-scan.sh` blockt commit/push mit Secrets.
2. Git-Hooks `.githooks/pre-commit` und `pre-push` (gitleaks) blocken lokal
   jeden Commit bzw. Push mit Secrets.
3. CI `.github/workflows/secret-scan.yml` ist der nicht überspringbare Backstop.
4. GitHub Push Protection (im Repo aktivieren!) blockt serverseitig.
Falsch-Positive: `.gitleaks.toml`-Allowlist, mit Begründungskommentar.

## Roadmap & Offene Punkte

Die zentrale Roadmap liegt in `docs/requirements-status.md`: alle geplanten
Punkte mit Status und Akzeptanzkriterien, sortiert nach Priorität.
„Nächster Punkt" heißt: der oberste offene Punkt dort. Nach Abschluss den
Status dort abhaken (erst nach verifizierten Akzeptanzkriterien) und neue
Erkenntnisse als neue Punkte ergänzen.

## Feature-Workflow (Agent-Team)

Nicht-triviale Features laufen über `/feature <beschreibung>` durch die
Pipeline requirements-engineer → solution-architect → qa-engineer (Tests
zuerst, RED) → Implementierung (Haupt-Agent) → code-reviewer → qa-engineer
(GREEN) → Draft-PR. Artefakte liegen unter `docs/features/<slug>/`. Die
RED-Tests entstehen vor der Implementierung und müssen rot sein — grün
werden sie ausschließlich durch die Implementierung, nie durch Abschwächen.

Was kein Test abdecken kann, wird im `qa-plan.md` als nummerierter
MC-Eintrag festgehalten (Tun / Erwartet / Warum manuell) und wandert als
Checkbox-Block in den PR-Body. Diese Haken setzt nur der Mensch: Claude hakt
nie selbst ab und nimmt den PR nie selbst aus dem Draft-Status.

Bugfixes und kleine, klar umrissene
Änderungen laufen über `/fix <beschreibung>` (Regressionstest + minimaler
Fix, ohne Pipeline-Gates). Kleinigkeiten (Typos, Einzeiler) direkt fixen.
Fehlen Lint-/Test-Gates (neues Projekt), richtet `/bootstrap [stack]` sie ein.

## CI/CD

<Welche Workflows existieren und was sie gaten. Default: `ci.yml`
(Lint + Typecheck + Tests + Build) und `secret-scan.yml` (gitleaks) auf
jedem PR. Deploy-Prozess beschreiben, falls vorhanden — inkl. manueller
Schritte (z. B. "Migrationen werden NICHT auto-deployed, nach Merge
manuell anwenden").>

## Known Issues & Technical Debt

<Ehrliche Liste. Beispiele: "keine Tests für Modul X", "Verzeichnis Y ist
ein divergierendes Duplikat — nur Z editieren", "Komponente W mischt
Concerns — beim Anfassen Utilities extrahieren". Oder "Keine bekannt.">
