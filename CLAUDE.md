# CLAUDE.md

Kontextdatei für Claude Code. Vor jeder Aufgabe lesen.

<!-- Das hier ist der Kontext DIESES Repos. Die auszuliefernde Vorlage mit
     <PLATZHALTERN> liegt unter templates/CLAUDE.md — dorthin gehören
     Änderungen an dem, was Zielprojekte bekommen. -->

## Projektbeschreibung

Claude-Code-Default-Setup: ein wiederverwendbarer Werkzeugkasten, den man per
`./setup.sh <ziel>` in ein anderes Projekt kopiert. Er bringt dorthin
Agenten-Definitionen, Skills, Schutz-Hooks gegen Secret-Leaks, CI-Vorlagen und
eine `CLAUDE.md`-Vorlage. Das Repo enthält keinen Anwendungscode — sein Produkt
sind Anweisungen (Markdown) und Shellskripte.

## Tech Stack

- **Sprache/Runtime**: Bash (Zielversion 3.2, siehe Harte Grenzen) + Markdown
- **UI**: keins (CLI)
- **Daten/Backend**: keins — reine Dateikopien
- **Externe Dienste**: `gh` (nur `setup-github.sh`), `gitleaks` (optional,
  überall mit Graceful Degradation)
- **Tests**: `tests/hook-selftest.sh` · **Lint**: `shellcheck -S warning`

## Projektstruktur

```
setup.sh                    # kopiert/vergleicht/aktualisiert den Werkzeugkasten
setup-github.sh             # serverseitige GitHub-Schalter (Rulesets, Push Protection)
CLAUDE.md                   # DIESE Datei — Kontext des Template-Repos
templates/CLAUDE.md         # die auszuliefernde Vorlage mit <PLATZHALTERN>
tests/hook-selftest.sh      # das verbindliche Gate (siehe unten)
.claude/hooks/              # die Schutz-Hooks — das eigentliche Produkt
.claude/agents/             # Agenten der Feature-Pipeline
.claude/skills/             # /feature, /fix, /bootstrap
.githooks/pre-commit        # gitleaks bei jedem Commit, auch ohne Claude
.github/workflows/          # *.yml aktiv; *.yml.example sind Vorlagen für Zielprojekte
docs/requirements-status.md # Roadmap-Vorlage (wird mitkopiert)
```

## Harte Grenzen (nicht verhandelbar)

- **`./tests/hook-selftest.sh` muss grün bleiben.** Es ist das einzige Gate
  über den Skripten. Neue Funktionalität bekommt neue Assertions dort — sonst
  ist sie nicht abgesichert. Verbindlich ist „0 fehlgeschlagen und keine
  bestehende Assertion verloren", nicht eine absolute Zahl: die Zahl der
  übersprungenen Tests hängt daran, ob `npm`/`gitleaks` im PATH liegen.
- **Bash 3.2 kompatibel** (macOS-Standard-Bash). Keine assoziativen Arrays,
  kein `${var,,}`, keine leeren Array-Expansionen unter `set -u`. Zu den
  bekannten Fallen stehen bereits Kommentare im Code — lies sie, bevor du sie
  umschreibst. `shellcheck` prüft das NICHT.
- **Keine neuen Laufzeit-Abhängigkeiten.** Erlaubt: bash, git, coreutils,
  optional `gitleaks` und `python3`/`python` — beide nur mit Fallback, nie als
  Voraussetzung. Kein `jq`, keine neuen Sprach-Runtimes, keine npm-/pip-Pakete
  für die Hooks.
- **Ein Hook darf nie still ausfallen.** Fehlt eine Toolchain, gehört das auf
  stderr, samt Benennung der Schicht, die stattdessen trägt. „Sieht geschützt
  aus, ist es nicht" ist der gefährlichste Zustand dieses Setups.

## KERN und PROJEKT

`setup.sh` unterscheidet zwei Sorten Dateien. Ordne jede neue Datei bewusst
zu — `is_core()` in `setup.sh` ist die maßgebliche Definition.

| Sorte | Was | Regel |
|---|---|---|
| **KERN** | `.claude/agents/`, `.claude/skills/`, `.claude/hooks/`, `.githooks/` | muss in allen Projekten identisch sein; `--update` überschreibt |
| **PROJEKT** | `CLAUDE.md`, `.claude/settings.json`, `.github/**`, `.gitleaks.toml`, `.gitignore`, `.env.example`, `docs/requirements-status.md` | darf abweichen; wird nie überschrieben |

Dazu eine dritte, ungeschriebene Sorte: **template-eigene Dateien**, die in
keinem Zielprojekt etwas zu suchen haben. Aktuell
`.github/workflows/hook-selftest.yml`, `.github/workflows/template-pin-check.yml`
und `.claude/hooks/verify-project.sh`. Sie werden in `process_tree()` namentlich
vom Kopieren ausgeschlossen, und je eine Assertion im Selbsttest belegt, dass
sie nach einem `setup.sh`-Lauf im Ziel fehlen. Legst du eine weitere solche
Datei an, gehört sie in beide Listen.

`LICENSE` gehört ebenfalls nicht ins Zielprojekt, kommt aber ohne Ausschluss
aus: `setup.sh` verarbeitet im Wurzelverzeichnis nur namentlich genannte
Dateien. Dasselbe gilt für `README.md` und alles unter `tests/`.

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

- **Sprache**: Kommentare, Doku und Skript-Ausgaben Deutsch; Bezeichner im
  Code Englisch.
- **Kommentare erklären das Warum**, meist mit dem konkreten Fehlmodus, den
  sie verhindern. Ein Kommentar, der wiederholt, was der Code tut, ist keiner.
- **Struktur**: Hooks halten ihren Exit-Code-Vertrag ein und dokumentieren ihn
  im Dateikopf (`0` = erlauben, `2` = blockieren mit Begründung auf stderr).
- **Im Klartext**: Bei Findings mit Entscheidungsbedarf (Review-Ergebnisse,
  Security-Punkte, Risiken) immer zusätzlich in nicht-technischer Sprache
  erklären, was das Problem für Nutzer/Betreiber konkret bedeutet. Reine
  Referenz-Tabellen (Dateilisten, Coverage-Maps) brauchen das nicht.
- **Secrets**: keine Secrets im Code — Konfiguration über `.env`
  (siehe `.env.example`).
- **Commits**: Conventional Commits (`feat:` / `fix:` / `docs:` / `test:` /
  `ci:` / `chore:`). Ein Thema = ein Commit.
- **Action-Pins**: immer Full-SHA plus Versionskommentar in der Zeile darüber.
  Dependabot parst `*.yml.example` NICHT — hebt es die aktiven Workflows,
  müssen die Vorlagen von Hand nachgezogen werden. Der Selbsttest erzwingt
  das (gleiche Action → gleicher SHA über alle Workflows).
- **Dependabot-`cooldown`**: jeder `package-ecosystem`-Block in
  `.github/dependabot.yml` trägt einen — auch die auskommentierten Vorlagen,
  die sonst beim Aktivieren ohne Wartezeit starten. Er deckt den einen Fall ab,
  den weder Audit noch CVE-Alert sehen: ein kompromittiertes Release am Tag
  seiner Veröffentlichung. Security-Updates sind ausgenommen und kommen
  weiterhin sofort. Der Selbsttest erzwingt die Anwesenheit, nicht die Tage.

## Build & Dev Commands

Diese Befehle sind die verbindlichen Gates — CI, der Stop-Hook
(`.claude/hooks/verify-project.sh`) und der qa-engineer führen genau diese aus.

```bash
# install    — keiner nötig; optional: brew install gitleaks shellcheck
./tests/hook-selftest.sh                     # test (das Gate)
shellcheck -s bash -S warning \
  .claude/hooks/*.sh .githooks/pre-commit \
  setup.sh setup-github.sh tests/hook-selftest.sh    # lint
./setup.sh --diff <zielprojekt>              # Kern-Verfall prüfen (Exit 1 = Verfall)
```

Es gibt keinen Typecheck und keinen Build — das Repo kompiliert nichts.

## Environment Variables

Keine. `.env.example` im Root ist die Vorlage, die Zielprojekte bekommen, und
wird in diesem Repo selbst nicht benutzt.

## Sicherheitsmodell

Das Repo hat keine Laufzeit-Angriffsfläche — es kopiert Dateien. Was es
schützt, ist die Secret-Hygiene der Projekte, in die es kopiert wird:

0. `permissions.deny` in `.claude/settings.json` blockt Lesezugriffe auf
   `.env`-Dateien/Keys; `.claude/hooks/protect-secrets.sh` blockt
   Schreibzugriffe darauf (beides Best-Effort — indirekte Wege wie
   Shell-Redirects sind nicht abgedeckt; die harten Garantien liefern 1–4).
1. `.claude/hooks/secret-scan.sh` blockt `git commit`/`push` mit Secrets.
2. `.githooks/pre-commit` (gitleaks) blockt lokal jeden Commit — braucht
   `core.hooksPath=.githooks`, das `session-start.sh` und `--update` setzen.
3. CI `.github/workflows/secret-scan.yml` ist der nicht überspringbare Backstop.
4. GitHub Push Protection (per `setup-github.sh` aktiviert).

Falsch-Positive: `.gitleaks.toml`-Allowlist, mit Begründungskommentar.
`.env.example` ist der bewusste blinde Fleck aller gitleaks-Schichten — dort
dürfen NUR Platzhalter stehen. Deshalb ist es auch die einzige Datei, die
`protect-secrets.sh` als editierbare Vorlage durchlässt.

## Roadmap & Offene Punkte

`docs/requirements-status.md` ist in diesem Repo die auszuliefernde Vorlage,
keine gepflegte Roadmap. Arbeitspakete kommen hier direkt aus der Anfrage.

## Feature-Workflow (Agent-Team)

Für Änderungen an diesem Repo gilt: die Pipeline (`/feature`) ist meist
überdimensioniert — die typische Änderung ist ein Hook oder ein Workflow-Step
plus Assertion, also `/fix`-Format. Was immer gilt:

- Jede Verhaltensänderung an einem Skript braucht eine Assertion in
  `tests/hook-selftest.sh`, und die Assertion muss nachweislich rot werden,
  wenn man die Änderung zurücknimmt.
- Manuelle Prüfschritte, die kein Test abdecken kann, wandern als
  MC-Checkbox-Block in den PR-Body. Diese Haken setzt nur der Mensch; Claude
  hakt nie selbst ab und nimmt den PR nie selbst aus dem Draft-Status.

## CI/CD

- `secret-scan.yml` — gitleaks über die volle Historie, hartes Gate auf jedem
  PR. Der Job heißt `gitleaks (hard gate)`; das Branch-Ruleset verlangt genau
  diesen Namen.
- `hook-selftest.yml` — shellcheck + `tests/hook-selftest.sh`. Läuft per
  Repo-Guard nur in diesem Repo.
- `template-pin-check.yml` — wöchentlich; prüft die Action-Pins der
  `*.yml.example` gegen die neuesten Upstream-Releases und meldet Abweichungen
  als Issue. Repo-Guard, einziger Workflow mit `issues: write`.
- `ci-*.yml.example` und `core-drift.yml.example` sind Vorlagen für
  Zielprojekte und laufen hier nicht.

Kein Deploy — die Verteilung ist `./setup.sh` von Hand.

## Known Issues & Technical Debt

- Die Pins in `*.yml.example` altern weiter still — Dependabot parst diese
  Dateien nicht —, aber es fällt jetzt auf: `template-pin-check.yml` vergleicht
  wöchentlich gegen die Upstream-Releases und öffnet bei Abweichung ein Issue
  (Label `maintenance`, genau eines, wird aktualisiert statt dupliziert).
  **Das Heben selbst bleibt Handarbeit**, samt Prüfung der Breaking Changes
  übersprungener Major-Versionen gegen die tatsächliche Nutzung.
  Zuletzt geschehen: 2026-08-01.
- Die Agenten-Tests im Selbsttest prüfen nur Struktur-Marker, nicht Verhalten
  — LLM-Ausgaben sind deterministisch nicht prüfbar.
- `setup.sh --diff` erkennt Kern-Verfall nur, wenn es jemand ausführt.
  `core-drift.yml.example` deckt das für Zielprojekte ab, muss dort aber
  einmal als `core-drift.yml` aktiviert werden.
