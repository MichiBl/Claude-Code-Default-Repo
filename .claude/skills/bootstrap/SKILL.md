---
name: bootstrap
description: Richtet in einem neuen Projekt die minimale Gate-Infrastruktur ein (Linter, Test-Runner, ein Smoke-Test, CI), damit verify.sh, die /feature-Preconditions und die CI von Anfang an greifen. Nutze dies, wenn der User `/bootstrap [stack]` tippt, ein Projekt auf der grünen Wiese startet, oder wenn die /feature-Pipeline wegen fehlender Test-/Lint-Infrastruktur stoppt.
---

# /bootstrap — Gate-Infrastruktur für neue Projekte

Du richtest die **minimale** Infrastruktur ein, die die Qualitäts-Gates
dieses Setups brauchen: einen Linter, einen Test-Runner mit mindestens einem
echten Test, und die passende CI. Ziel ist ein Zustand, in dem `verify.sh`
tatsächlich prüft (statt mangels Tooling still grün zu sein) und die
`/feature`-Pipeline ihre Preconditions erfüllt sieht.

Minimal heißt minimal: kein Framework-Scaffolding, keine Beispiel-App,
keine Dependencies über Linter + Test-Runner hinaus.

## Workflow

### 1. Stack bestimmen

Nimm das Argument (`node`, `python`, …), sonst erkenne den Stack an
vorhandenen Dateien (`package.json` -> Node, `pyproject.toml` /
`requirements.txt` -> Python). Ist beides nicht eindeutig, frage den User
per `AskUserQuestion`.

### 2. Gates einrichten

Prüfe zuerst, was schon existiert — **ergänze nur Fehlendes**, überschreibe
nie vorhandene Konfiguration.

**Node:**
- `package.json` (falls fehlend: `npm init -y`, dann Felder aufräumen).
- ESLint als Dev-Dependency + minimale Flat-Config; `"lint"`-Script.
- Vitest (oder der im Projekt schon vorhandene Runner) als Dev-Dependency;
  `"test"`-Script.
- Bei TypeScript-Projekten: `typescript` + minimales `tsconfig.json`.
- Ein Smoke-Test unter `src/` bzw. `tests/`, der etwas Echtes prüft
  (z. B. ein exportiertes Utility) — kein `expect(true).toBe(true)`.

**Python (uv):**
- `pyproject.toml` (falls fehlend: `uv init`), `ruff` und `pytest` in die
  Dev-Dependencies (`uv add --dev ruff pytest`), `uv.lock` committen.
- `tests/test_smoke.py` mit einem echten Assert gegen Projektcode.

**Anderer Stack (Go, Rust, …):**
- Richte die nativen Werkzeuge ein (z. B. `go vet` + `go test`,
  `cargo clippy` + `cargo test`).
- Lege ein ausführbares `.claude/hooks/verify-project.sh` an, das sie
  ausführt — Vertrag: exit 0 = grün, exit 2 + Befund auf stderr = Claude
  muss nachbessern. Existiert diese Datei, führt `verify.sh` nur sie aus.

### 3. CI aktivieren

Liegt unter `.github/workflows/` ein passendes Example
(`ci-node.yml.example` / `ci-python-uv.yml.example` /
`ci-python-pip.yml.example`), benenne es nach `ci.yml`
um und passe es an die eingerichteten Befehle an. Für andere Stacks: kurz
anbieten, eine `ci.yml` zu schreiben — nicht ungefragt erfinden.

### 4. Verifizieren & dokumentieren

- Führe Lint und Tests einmal selbst aus — beide müssen **grün** sein.
  Rot heißt: fixen, nicht abliefern.
- Trage die echten Befehle in `CLAUDE.md` unter **Build & Dev Commands**
  ein (das sind die verbindlichen Gates für Hook, CI und QA) und
  aktualisiere den Tech-Stack-Abschnitt, falls er noch Platzhalter enthält.
- Committe als eigene Aufgabe (`chore: bootstrap lint/test gates`) —
  nie als Nebenprodukt eines Feature-Laufs.

## Grenzen

- Keine Anwendungslogik schreiben — nur Gate-Infrastruktur.
- Nichts Bestehendes überschreiben; bei Konflikten (z. B. anderer Linter
  schon konfiguriert) den vorhandenen Weg respektieren.
