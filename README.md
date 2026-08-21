# Claude Code Default Setup

Wiederverwendbares Standard-Setup für neue Projekte — destilliert aus
[stock-wise-scanner-29](https://github.com/MichiBl/stock-wise-scanner-29),
[Stockwise-News-Agent](https://github.com/MichiBl/Stockwise-News-Agent) und
[local-mail-ai](https://github.com/MichiBl/local-mail-ai-).

## Voraussetzungen

- macOS oder Linux (Windows über WSL), mit `bash` und `git` — mehr braucht
  der Werkzeugkasten selbst nicht (Ziel-Kompatibilität: Bash 3.2, die
  macOS-Standard-Bash).
- `gitleaks` für die lokalen Secret-Scans (`brew install gitleaks`); fehlt
  es, degradieren die Hooks mit Hinweis — die CI scannt trotzdem.
- Optional: `gh` (nur für `setup-github.sh`) sowie `shellcheck` und
  `python3` (nur zum Entwickeln am Template selbst; die Hooks haben
  Fallbacks ohne Python).

## Verwendung

```bash
git clone https://github.com/MichiBl/Claude-Code-Default-Repo.git
./Claude-Code-Default-Repo/setup.sh /pfad/zum/neuen/projekt
```

Existierende Dateien werden nie überschrieben. Danach in Claude Code im
Zielprojekt: *"Fülle die CLAUDE.md-Platzhalter anhand dieses Repos aus."*

### Serverseitige GitHub-Einstellungen aktivieren

Branch Protection, Dependabot und Secret scanning sind **Konto-/Repo-
Einstellungen bei GitHub** — sie können nicht als Datei im Repo leben.
`setup-github.sh` aktiviert sie per GitHub CLI, so weit Plan und Rechte es
erlauben (Rest wird gemeldet, nicht abgebrochen):

```bash
# einmalig: brew install gh && gh auth login

# erst ansehen, was serverseitig passieren würde — ändert nichts:
./Claude-Code-Default-Repo/setup-github.sh /pfad/zum/projekt --dry-run

./Claude-Code-Default-Repo/setup-github.sh /pfad/zum/projekt \
  --check "lint • typecheck • test (uv)"   # CI-Job-Name(n) des Projekts
```

`--dry-run` setzt keinen schreibenden Aufruf ab, nimmt aber denselben
Entscheidungsweg wie der Echtlauf — es sieht also auch, welche Rulesets schon
existieren und deshalb übersprungen würden.

Das aktiviert Dependabot alerts + Auto-Fix-PRs, Secret scanning + Push
protection (falls der Plan es hergibt) und importiert das Branch-Ruleset
aus `.github/rulesets/main-schutz.json` (PR-Pflicht, Required Status
Checks, kein Force-Push/Delete auf den Default-Branch). Der
gitleaks-Check ist im Ruleset vorkonfiguriert; die projektspezifischen
CI-Job-Namen kommen per `--check` dazu. Ohne `gh` geht es von Hand:
Settings → Rules → Rulesets → **Import a ruleset** → die JSON-Datei wählen.

Die Vorlage verlangt bewusst **0 Approvals** (Solo-Betrieb: der Autor merged
selbst, sonst blockierte jeder PR). Für Team-Projekte vor dem Import
`required_approving_review_count` in der JSON auf ≥ 1 setzen.

Achtung: Auf privaten Repos im Free-Plan speichert GitHub Rulesets, setzt
sie aber nicht durch — die CI-Gates auf jedem PR gelten unabhängig davon.

### Bestehende Projekte aktualisieren

```bash
./Claude-Code-Default-Repo/setup.sh --diff   /pfad/zum/projekt   # nur prüfen
./Claude-Code-Default-Repo/setup.sh --update /pfad/zum/projekt   # Kern übernehmen
```

Dateien zerfallen dafür in zwei Sorten:

| Sorte | Was | Regel |
|---|---|---|
| **KERN** | `.claude/agents/`, `.claude/skills/`, `.claude/hooks/`, `.githooks/`, `.github/workflows/secret-scan.yml` | muss überall identisch sein — Abweichung ist Verfall |
| **PROJEKT** | `CLAUDE.md`, `.claude/settings.json`, `ci.yml`, `dependabot.yml`, `rulesets/*.json`, `.gitleaks.toml`, `.gitignore`, `.env.example`, `docs/requirements-status.md` | darf und soll abweichen — wird nie überschrieben |

`secret-scan.yml` ist die eine Ausnahme unter `.github/`: der
gitleaks-Backstop ist stack-unabhängig und die wichtigste Schutzschicht —
als PROJEKT-Datei würde ausgerechnet sie still veralten, weil `--update`
sie nie anfassen dürfte. Alles Stack-Abhängige (`ci.yml`, `dependabot.yml`)
bleibt PROJEKT.

`--diff` zeigt pro Datei `fehlt` / `identisch` / `weicht ab`, den Kurz-Diff
aber nur für KERN-Dateien (bei PROJEKT-Dateien wäre er reines Rauschen). Der
Exit-Code ist **1**, sobald eine KERN-Datei abweicht oder fehlt — damit taugt
der Modus als Prüfung, nicht nur als Bericht.

`--update` überschreibt genau diese KERN-Dateien mit dem Stand des Templates
und lässt alles andere in Ruhe. Danach `git diff` im Zielprojekt durchsehen
und committen.

**Damit es jemand merkt.** `--diff` hilft nur, wenn man es ausführt — mit
einem lokalen Klon beider Repos. Über mehrere Projekte hinweg passiert das
erfahrungsgemäß nicht, und dann laufen die Kopien wieder auseinander. Deshalb
liegt im Zielprojekt `.github/workflows/core-drift.yml.example`: einmal nach
`core-drift.yml` umbenennen, und der Workflow klont wöchentlich das Template,
fährt `setup.sh --diff .` und wird bei Kern-Verfall rot. Rot heißt dort nicht
„kaputt", sondern „Kern veraltet" — beheben mit `./setup.sh --update .`.

**Auch die Gegenrichtung wird geprüft.** `--diff` und `--update` melden
Dateien in den Kern-Verzeichnissen des Ziels, die das Template nicht kennt —
etwa einen Hook, den das Template inzwischen gelöscht hat, der im Projekt
aber noch in `settings.json` verdrahtet ist und dort alten Code ausführt.
Gelöscht wird nichts (es kann ein bewusst projekteigener Hook/Agent sein),
und Verwaiste zählen nicht als Verfall — der `--diff`-Exit-Code bleibt
davon unberührt.

**Kopiert heißt nicht aktiv.** Zwei Hook-Sorten brauchen eine Verdrahtung, die
in einer PROJEKT-Datei bzw. in der Git-Config steht — beide Modi melden das:

| Was | Verdrahtung | Verhalten |
|---|---|---|
| `.claude/hooks/*.sh` | `.claude/settings.json` | wird **gemeldet**, nie automatisch geändert (dort stehen projekteigene Permissions) |
| `.githooks/pre-commit` | `git config core.hooksPath` | wird von `--update` **und** von `session-start.sh` gesetzt, sofern noch nichts konfiguriert ist; ein eigener Wert bleibt unangetastet und wird nur gemeldet |

`core.hooksPath` steht in `.git/config` und wird **nicht** mitversioniert — nach
jedem frischen Klon fehlt sie wieder. Deshalb zieht `session-start.sh` sie bei
jedem Session-Start nach, genau wie fehlende `node_modules` oder ein leeres
`.venv`. Ohne das wäre es ein manueller Schritt pro Rechner und pro Klon, den
zuverlässig niemand macht.

Ein Hook, der im Verzeichnis liegt, aber nie aufgerufen wird, ist der
gefährlichste Zustand — das Projekt sieht geschützt aus und ist es nicht.
`--diff` wertet einen inaktiven `pre-commit` deshalb wie Kern-Verfall (Exit 1).

Warum die Trennung: Ohne sie meldet `--diff` in jedem Projekt Abweichungen in
`CLAUDE.md` & Co. — Rauschen, in dem echter Verfall des Werkzeugkastens
untergeht. Genau so laufen Kopien über Monate auseinander, ohne dass es
jemandem auffällt.

### Gesundheitscheck: --doctor

```bash
./Claude-Code-Default-Repo/setup.sh --doctor /pfad/zum/projekt
```

Beantwortet die Frage „ist dieses Projekt wirklich geschützt?" in einem
Lauf — je Schicht `ok`/`fehlt`, mit konkretem Behebungsbefehl:

1. gitleaks installiert
2. `core.hooksPath` zeigt auf `.githooks`
3. jeder Hook in `.claude/hooks/` ist in `settings.json` verdrahtet
4. `CLAUDE.md` ohne unbefüllte Platzhalter
5. `.github/workflows/ci.yml` existiert
6. Lint-Gate vorhanden (`lint`-Script bzw. ruff bzw. `verify-project.sh`)
7. Werkzeug-Kern deckungsgleich (nutzt die `--diff`-Prüfung)

Exit 1, sobald etwas fehlt — damit taugt der Modus auch als Skript-Check.
Verändert nichts am Projekt. Zusätzlich warnt `session-start.sh` bei jedem
Session-Start, wenn gitleaks fehlt (nie blockierend).

## Was drin ist

Der Baum unten zeigt alles, was `setup.sh` unverändert an dieselben Pfade
im Zielprojekt kopiert (Ausnahmen sind im Baum markiert). Die Skripte selbst
(`setup.sh`, `setup-github.sh`) und `tests/hook-selftest.sh` bleiben in
diesem Repo.

Zwei Dateien sind template-eigen und werden bewusst **nicht** kopiert:
`.github/workflows/hook-selftest.yml` (testet die Hooks dieses Repos) und
`.claude/hooks/verify-project.sh` (Gate dieses Repos — im Zielprojekt würde es
die Stack-Autoerkennung von `verify.sh` abschalten). Ebenso liegt die
`CLAUDE.md`-Vorlage unter `templates/CLAUDE.md`: die `CLAUDE.md` im Root ist
der ausgefüllte Kontext dieses Repos, damit Claude beim Arbeiten *an* dem
Werkzeugkasten nicht auf Platzhalter schaut.

```
CLAUDE.md                        # aus templates/CLAUDE.md — Vorlage mit <PLATZHALTERN>
                                 # (die CLAUDE.md im Repo-Root ist dessen eigener Kontext)
docs/requirements-status.md      # zentrale Roadmap: Punkte mit Status + Akzeptanzkriterien
.env.example                     # Vorlage für lokale Konfiguration (echte Werte nur in .env)
.claude/
├── settings.json                # registriert die Hooks + deny-Regeln gegen .env-/Key-Lesezugriffe
├── agents/
│   ├── requirements-engineer.md # Feature -> testbare Spezifikation (sonnet)
│   ├── solution-architect.md    # Spezifikation -> dateigenauer Plan (sonnet)
│   ├── code-reviewer.md         # Diff vs. Plan, Security, Drift (sonnet)
│   └── qa-engineer.md           # AC -> echte Tests + Gates (sonnet)
├── skills/
│   ├── feature/SKILL.md         # /feature — orchestriert die Pipeline
│   ├── fix/SKILL.md             # /fix — Fast Lane für Bugfixes (Regressionstest + minimaler Fix)
│   └── bootstrap/SKILL.md       # /bootstrap — richtet Lint-/Test-Gates in neuen Projekten ein
└── hooks/
    ├── session-start.sh         # SessionStart-Hook: fehlende Deps + core.hooksPath (v. a. Web-Sessions)
    ├── verify.sh                # Stop-Hook: Lint/Typecheck/Tests, Stack-Autoerkennung (Node/uv/pip)
    ├── verify-project.sh        # Gate DIESES Repos (Selbsttest + shellcheck) — wird NICHT kopiert
    ├── secret-scan.sh           # PreToolUse-Hook: gitleaks vor git commit/push
    └── protect-secrets.sh       # PreToolUse-Hook: blockt Edit/Write auf .env-/Secret-Dateien
.githooks/
├── pre-commit                   # gitleaks-Scan bei jedem Commit (auch ohne Claude)
├── pre-push                     # gitleaks-Scan über die Push-Ranges (fängt --no-verify-Commits)
└── README.md                    # Aktivierung + Schichtenübersicht für dieses Verzeichnis
.gitignore                       # .env, Deps, Build-Artefakte, settings.local.json
.gitleaks.toml                   # Default-Ruleset + Platzhalter-Allowlist
.github/
├── dependabot.yml               # hält die SHA-gepinnten Actions aktuell (wöchentlich, gebündelt)
├── pull_request_template.md     # PR-Gerüst mit dem MC-Checkbox-Block (Haken setzt nur der Mensch)
├── rulesets/
│   └── main-schutz.json         # Branch-Ruleset-Vorlage (Import via setup-github.sh oder UI)
└── workflows/
    ├── secret-scan.yml          # CI-Backstop: gitleaks über volle Historie (sofort aktiv)
    ├── core-drift.yml.example   # meldet wöchentlich, wenn der Kern veraltet ist (umbenennen)
    ├── hook-selftest.yml        # testet die Schutz-Hooks — nur Template-Repo, wird NICHT kopiert
    ├── template-pin-check.yml   # meldet veraltete Pins der Vorlagen — dito, wird NICHT kopiert
    ├── ci-node.yml.example      # Lint • tsc • Test • Build  (setup.sh aktiviert sie als ci.yml)
    ├── ci-python-uv.yml.example  # ruff • pip-audit • pytest   (setup.sh wählt sie bei uv.lock)
    └── ci-python-pip.yml.example # ruff • mypy • pytest        (setup.sh wählt sie sonst)
```

### Andere Stacks (Go, Rust, …)

Der Stop-Hook `verify.sh` kennt Node und Python. Für alles andere legt das
Zielprojekt ein eigenes ausführbares `.claude/hooks/verify-project.sh` an —
existiert es, führt `verify.sh` nur dieses aus (gleicher Vertrag: exit 0 =
grün, exit 2 + stderr = Claude muss nachbessern).

## Die Feature-Pipeline

`/feature <beschreibung>` führt durch:

1. **requirements-engineer** -> `docs/features/<slug>/requirements.md` — **Gate: User-OK**
2. **solution-architect** -> `architecture.md` — **Gate: User-OK**
3. **qa-engineer (RED)** -> Tests aus den Acceptance Criteria, die vor der
   Implementierung rot sein müssen (ein schon grüner Test prüft das Feature nicht)
4. **Implementierung durch den Haupt-Agenten** (wird nie delegiert) — macht
   die RED-Tests grün
5. **code-reviewer** -> `code-review.md` (APPROVED / NEEDS_CHANGES / BLOCKED)
6. **qa-engineer (GREEN)** -> `qa-plan.md` finalisiert + Edge-Case-Tests, Gates grün
7. **Draft-PR** mit verlinkten Artefakten

### Manuelle Prüfschritte (MC)

Was kein Test abdecken *kann* — Rendering in einem echten Mail-Client,
Plausibilität einer LLM-Ausgabe — landet nicht im Nirwana, sondern als
nummerierter MC-Eintrag im `qa-plan.md`, mit **Tun**, **Erwartet** und
**Warum manuell**. Trägt „Warum manuell" nicht, ist der Eintrag keine
Prüfaufgabe, sondern eine Automatisierungslücke — dann schreibt die QA den
Test. Der Normalfall ist „Keine."

Der Draft-PR übernimmt diese Einträge als Checkbox-Block:

```markdown
## Selbst prüfen, bevor der PR aus dem Draft geht
- [ ] **MC-1: <Kurztitel>**
      Tun: <Befehl/Klickpfad> — Erwartet: <Soll-Ergebnis>
```

Diese Haken setzt **nur der Mensch**. Claude hakt nie selbst ab und nimmt
den PR nie selbst aus dem Draft-Status — der Draft ist damit das Gate für
genau das, was Automatisierung nicht verifizieren kann.

Alle Agents lesen die Projekt-Spezifika aus der `CLAUDE.md` des jeweiligen
Projekts — deshalb ist die Vorlage sorgfältig auszufüllen, besonders
**Harte Grenzen** (Review-Verdict BLOCKED bei Verstoß) und
**Build & Dev Commands** (die verbindlichen Gates für Hook, CI und QA).

Nicht alles braucht die Pipeline: Bugfixes und kleine, klar umrissene
Änderungen laufen über `/fix` (Ursache -> Regressionstest -> minimaler
Fix; die Verifikation übernimmt der Stop-Hook). Typos und Einzeiler
werden direkt gefixt, ganz ohne Skill.

## Secret-Schutz (Defense in Depth)

| Schicht | greift |
|---------|--------|
| `permissions.deny` in `settings.json` | blockt direkte Lesezugriffe von Claude auf `.env`-Dateien/Keys (Best-Effort, keine Garantie) |
| Claude-Hook `protect-secrets.sh` | blockt Schreibzugriffe (Edit/Write) von Claude auf dieselben Dateien — Vorlagen wie `.env.example` bleiben editierbar |
| Claude-Hook `secret-scan.sh` | bevor Claude committet/pusht |
| Git-Hook `.githooks/pre-commit` | bei jedem lokalen Commit (auch ohne Claude) |
| Git-Hook `.githooks/pre-push` | bei jedem lokalen Push — scannt die exakten Commit-Ranges des Pushs; fängt auch git-Aliasse, Skript-Pushes und `--no-verify`-Commits |
| CI `secret-scan.yml` | auf jedem PR/Push — nicht überspringbar |
| GitHub Push Protection | serverseitig — `setup-github.sh` aktiviert sie, soweit Plan und Rechte es hergeben (sonst manuell) |

### Selbsttest der Schutz-Hooks

Die Hooks sind das Produkt dieses Repos — und Shellskripte gehen leise kaputt.
`tests/hook-selftest.sh` prüft deshalb die Exit-Code-Verträge von
`protect-secrets.sh`, `verify.sh`, `secret-scan.sh`, `session-start.sh`,
`.githooks/pre-commit` und `.githooks/pre-push` gegen Wegwerf-Fixtures, dazu die CI-Aktivierung von
`setup.sh` (Node/uv/pip, nie überschreiben) und per Struktur-Check, dass die
tragenden Regeln der Agenten-Dateien (Verdict-Schema, SRP-Prüfpunkt,
Pipeline-Gates) nicht versehentlich wegeditiert wurden — das *Verhalten* der
Agenten selbst ist nicht deterministisch testbar, nur die Präsenz ihrer
Anweisungen. Der Workflow `.github/workflows/hook-selftest.yml`
führt ihn auf jedem PR aus — per Repo-Guard **nur in diesem Template-Repo**;
`setup.sh` kopiert Workflow und Test nicht in Zielprojekte. Lokal:
`./tests/hook-selftest.sh` (gitleaks-Tests werden ohne gitleaks übersprungen).

Die Scan-Schichten nutzen gitleaks bzw. GitHubs eigenen Scanner; ein
Binary, keine Sprachabhängigkeit. Falsch-Positive kommen mit
Begründungskommentar in die `.gitleaks.toml`-Allowlist. Die deny-Regeln
davor decken `.env`-Varianten (auch in Unterordnern), Keys und `secrets/`
ab — bewusst als Aufzählung statt `.env.*`, damit `.env.example` lesbar
bleibt und Claude die Vorlage pflegen kann. Eine exotische Variante
(z. B. `.env.custom`) muss man selbst ergänzen — in allen drei Listen
(settings.json, `protect-secrets.sh`, `.gitignore`); der Selbsttest gleicht
sie gegeneinander ab. Deny-Regeln und
`protect-secrets.sh` fangen direkte Lese- bzw. Schreibzugriffe ab, sind aber
Best-Effort — verlässlich blocken erst die Scan-Schichten darunter.

Ehrlich benannt: Alle Schichten schützen die **Git-Historie**. Das Auslesen
von Secrets zur Laufzeit über die Shell (`cat .env`, Upload per curl) deckt
keine davon ab — dort ist die Grenze der Permission-Prompt von Claude Code.

## Pro Projekt noch zu tun

1. `CLAUDE.md`-Platzhalter ausfüllen (macht Claude auf Zuruf).
2. `ci.yml` prüfen und ans Projekt anpassen — bei erkanntem Stack (Node,
   Python mit/ohne uv) hat `setup.sh` sie schon aus der passenden
   `ci-*.yml.example` erzeugt; nur bei unerkanntem Stack ist das Umbenennen
   von Hand nötig.
3. `brew install gitleaks` (einmal pro Maschine).
4. `./setup-github.sh /pfad/zum/projekt --check "<CI-Job-Name>"` ausführen
   (siehe oben) — oder von Hand: Secret scanning + Push protection
   aktivieren und das Ruleset aus `.github/rulesets/` importieren.
5. Lint-Gate sicherstellen (Node: `lint`-Script in `package.json`, Python:
   ruff als Dev-Dependency) — ohne Linter laufen verify.sh, CI und QA leer;
   `setup.sh` warnt, wenn er fehlt.
6. Test-Infrastruktur aufsetzen, falls das Projekt neu ist — die
   `/feature`-Pipeline verweigert den Start ohne (ebenso ohne Lint-Gate).
   Das erledigt `/bootstrap [stack]` in Claude Code: Linter, Test-Runner
   mit Smoke-Test und CI in einem Rutsch.

## Lizenz

[MIT](LICENSE). Der Werkzeugkasten wird per `setup.sh` wortwörtlich in andere
Projekte kopiert — die MIT-Bedingungen (Copyright-Hinweis erhalten) gelten
damit auch für die kopierten Dateien.
