# Claude Code Default Setup

Wiederverwendbares Standard-Setup für neue Projekte — destilliert aus
[stock-wise-scanner-29](https://github.com/MichiBl/stock-wise-scanner-29),
[Stockwise-News-Agent](https://github.com/MichiBl/Stockwise-News-Agent) und
[local-mail-ai](https://github.com/MichiBl/local-mail-ai-).

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
./Claude-Code-Default-Repo/setup-github.sh /pfad/zum/projekt \
  --check "lint • typecheck • test (uv)"   # CI-Job-Name(n) des Projekts
```

Das aktiviert Dependabot alerts + Auto-Fix-PRs, Secret scanning + Push
protection (falls der Plan es hergibt) und importiert das Branch-Ruleset
aus `.github/rulesets/main-schutz.json` (PR-Pflicht, Required Status
Checks, kein Force-Push/Delete auf den Default-Branch). Der
gitleaks-Check ist im Ruleset vorkonfiguriert; die projektspezifischen
CI-Job-Namen kommen per `--check` dazu. Ohne `gh` geht es von Hand:
Settings → Rules → Rulesets → **Import a ruleset** → die JSON-Datei wählen.

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
| **KERN** | `.claude/agents/`, `.claude/skills/`, `.claude/hooks/`, `.githooks/` | muss überall identisch sein — Abweichung ist Verfall |
| **PROJEKT** | `CLAUDE.md`, `.claude/settings.json`, `ci.yml`, `dependabot.yml`, `rulesets/*.json`, `.gitleaks.toml`, `.gitignore`, `.env.example`, `docs/requirements-status.md` | darf und soll abweichen — wird nie überschrieben |

`--diff` zeigt pro Datei `fehlt` / `identisch` / `weicht ab`, den Kurz-Diff
aber nur für KERN-Dateien (bei PROJEKT-Dateien wäre er reines Rauschen). Der
Exit-Code ist **1**, sobald eine KERN-Datei abweicht oder fehlt — damit taugt
der Modus als Prüfung, nicht nur als Bericht.

`--update` überschreibt genau diese KERN-Dateien mit dem Stand des Templates
und lässt alles andere in Ruhe. Danach `git diff` im Zielprojekt durchsehen
und committen.

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
└── README.md                    # Aktivierung + Schichtenübersicht für dieses Verzeichnis
.gitignore                       # .env, Deps, Build-Artefakte, settings.local.json
.gitleaks.toml                   # Default-Ruleset + Platzhalter-Allowlist
.github/
├── dependabot.yml               # hält die SHA-gepinnten Actions aktuell (wöchentlich, gebündelt)
├── rulesets/
│   └── main-schutz.json         # Branch-Ruleset-Vorlage (Import via setup-github.sh oder UI)
└── workflows/
    ├── secret-scan.yml          # CI-Backstop: gitleaks über volle Historie (sofort aktiv)
    ├── hook-selftest.yml        # testet die Schutz-Hooks — nur Template-Repo, wird NICHT kopiert
    ├── ci-node.yml.example      # Lint • tsc • Test • Build  (setup.sh aktiviert sie als ci.yml)
    └── ci-python.yml.example    # ruff • mypy/pip-audit • pytest  (setup.sh aktiviert uv- ODER pip-Job)
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
3. **Implementierung durch den Haupt-Agenten** (wird nie delegiert)
4. **code-reviewer** -> `code-review.md` (APPROVED / NEEDS_CHANGES / BLOCKED)
5. **qa-engineer** -> `qa-plan.md` + echte Tests, Gates grün
6. **Draft-PR** mit verlinkten Artefakten

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
| CI `secret-scan.yml` | auf jedem PR/Push — nicht überspringbar |
| GitHub Push Protection | serverseitig — `setup-github.sh` aktiviert sie, soweit Plan und Rechte es hergeben (sonst manuell) |

### Selbsttest der Schutz-Hooks

Die Hooks sind das Produkt dieses Repos — und Shellskripte gehen leise kaputt.
`tests/hook-selftest.sh` prüft deshalb die Exit-Code-Verträge von
`protect-secrets.sh`, `verify.sh`, `secret-scan.sh`, `session-start.sh` und
`.githooks/pre-commit` gegen Wegwerf-Fixtures, dazu die CI-Aktivierung von
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
(z. B. `.env.custom`) muss man selbst ergänzen. Deny-Regeln und
`protect-secrets.sh` fangen direkte Lese- bzw. Schreibzugriffe ab, sind aber
Best-Effort — verlässlich blocken erst die Scan-Schichten darunter.

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
