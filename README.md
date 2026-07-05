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

### Bestehende Projekte aktualisieren

```bash
./Claude-Code-Default-Repo/setup.sh --diff /pfad/zum/projekt
```

Zeigt pro Template-Datei `fehlt` / `identisch` / `weicht ab` (mit Kurz-Diff),
ohne etwas zu ändern — Verbesserungen am Template lassen sich so gezielt in
ältere Projekte übernehmen.

## Was drin ist

Der Baum unten zeigt alle Dateien — `setup.sh` kopiert sie unverändert
an dieselben Pfade im Zielprojekt.

```
CLAUDE.md                        # generische Vorlage mit <PLATZHALTERN>
.env.example                     # Vorlage für lokale Konfiguration (echte Werte nur in .env)
.claude/
├── settings.json                # registriert die Hooks + deny-Regeln (Claude liest nie .env/Keys)
├── agents/
│   ├── requirements-engineer.md # Feature -> testbare Spezifikation (sonnet)
│   ├── solution-architect.md    # Spezifikation -> dateigenauer Plan (sonnet)
│   ├── code-reviewer.md         # Diff vs. Plan, Security, Drift (sonnet)
│   └── qa-engineer.md           # AC -> echte Tests + Gates (sonnet)
├── skills/feature/SKILL.md      # /feature — orchestriert die Pipeline
└── hooks/
    ├── session-start.sh         # SessionStart-Hook: installiert fehlende Deps (v. a. Web-Sessions)
    ├── verify.sh                # Stop-Hook: Lint/Typecheck/Tests, Stack-Autoerkennung (Node/uv/pip)
    └── secret-scan.sh           # PreToolUse-Hook: gitleaks vor git commit/push
.githooks/pre-commit             # gitleaks-Scan bei jedem Commit (auch ohne Claude)
.gitignore                       # .env, Deps, Build-Artefakte, settings.local.json
.gitleaks.toml                   # Default-Ruleset + Platzhalter-Allowlist
.github/
├── dependabot.yml               # hält die SHA-gepinnten Actions aktuell (wöchentlich, gebündelt)
└── workflows/
    ├── secret-scan.yml          # CI-Backstop: gitleaks über volle Historie (sofort aktiv)
    ├── ci-node.yml.example      # Lint • tsc • Test • Build  (umbenennen -> ci.yml)
    └── ci-python.yml.example    # ruff • mypy/pip-audit • pytest  (umbenennen -> ci.yml)
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

Alle Agents lesen die Projekt-Spezifika aus der `CLAUDE.md` des jeweiligen
Projekts — deshalb ist die Vorlage sorgfältig auszufüllen, besonders
**Harte Grenzen** (Review-Verdict BLOCKED bei Verstoß) und
**Build & Dev Commands** (die verbindlichen Gates für Hook, CI und QA).

## Secret-Schutz (Defense in Depth)

| Schicht | greift |
|---------|--------|
| `permissions.deny` in `settings.json` | Claude liest `.env`/Keys gar nicht erst (nichts im Kontext) |
| Claude-Hook `secret-scan.sh` | bevor Claude committet/pusht |
| Git-Hook `.githooks/pre-commit` | bei jedem lokalen Commit (auch ohne Claude) |
| CI `secret-scan.yml` | auf jedem PR/Push — nicht überspringbar |
| GitHub Push Protection | serverseitig — **pro Repo manuell aktivieren** |

Die Scan-Schichten nutzen gitleaks bzw. GitHubs eigenen Scanner; ein
Binary, keine Sprachabhängigkeit. Falsch-Positive kommen mit
Begründungskommentar in die `.gitleaks.toml`-Allowlist. Die deny-Regeln
davor sind bewusst eng (`.env`, `.env.local`, Keys, `secrets/`) —
`.env.example` bleibt lesbar, damit Claude die Vorlage pflegen kann.

## Pro Projekt noch zu tun

1. `CLAUDE.md`-Platzhalter ausfüllen (macht Claude auf Zuruf).
2. `ci-*.yml.example` nach `ci.yml` umbenennen und anpassen.
3. `brew install gitleaks` (einmal pro Maschine).
4. GitHub: Secret scanning + Push protection aktivieren; Branch Protection
   mit den Checks `CI` und `Secret Scan` als Required.
5. Test-Infrastruktur aufsetzen, falls das Projekt neu ist — die
   `/feature`-Pipeline verweigert den Start ohne.
