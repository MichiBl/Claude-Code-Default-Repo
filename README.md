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

## Was drin ist

Alle Dateien liegen bereits unter ihren verbindlichen Punkt-Namen
(`.claude/`, `.github/` usw.) und werden von `setup.sh` unverändert
ins Zielprojekt kopiert.

```
CLAUDE.md                        # generische Vorlage mit <PLATZHALTERN>
.claude/
├── settings.json                # registriert beide Hooks
├── agents/
│   ├── requirements-engineer.md # Feature -> testbare Spezifikation (sonnet)
│   ├── solution-architect.md    # Spezifikation -> dateigenauer Plan (opus)
│   ├── code-reviewer.md         # Diff vs. Plan, Security, Drift (opus)
│   └── qa-engineer.md           # AC -> echte Tests + Gates (sonnet)
├── skills/feature/SKILL.md      # /feature — orchestriert die Pipeline
└── hooks/
    ├── verify.sh                # Stop-Hook: Lint/Typecheck/Tests, Stack-Autoerkennung (Node/uv/pip)
    └── secret-scan.sh           # PreToolUse-Hook: gitleaks vor git commit/push
.githooks/pre-commit             # gitleaks-Scan bei jedem Commit (auch ohne Claude)
.gitignore                       # .env, Deps, Build-Artefakte, settings.local.json
.gitleaks.toml                   # Default-Ruleset + Platzhalter-Allowlist
.github/workflows/
├── secret-scan.yml              # CI-Backstop: gitleaks über volle Historie (sofort aktiv)
├── ci-node.yml.example          # Lint • tsc • Test • Build  (umbenennen -> ci.yml)
└── ci-python.yml.example        # ruff • mypy/pip-audit • pytest  (umbenennen -> ci.yml)
```

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
| Claude-Hook `secret-scan.sh` | bevor Claude committet/pusht |
| Git-Hook `.githooks/pre-commit` | bei jedem lokalen Commit (auch ohne Claude) |
| CI `secret-scan.yml` | auf jedem PR/Push — nicht überspringbar |
| GitHub Push Protection | serverseitig — **pro Repo manuell aktivieren** |

Alle vier Schichten nutzen gitleaks bzw. GitHubs eigenen Scanner; ein
Binary, keine Sprachabhängigkeit. Falsch-Positive kommen mit
Begründungskommentar in die `.gitleaks.toml`-Allowlist.

## Pro Projekt noch zu tun

1. `CLAUDE.md`-Platzhalter ausfüllen (macht Claude auf Zuruf).
2. `ci-*.yml.example` nach `ci.yml` umbenennen und anpassen.
3. `brew install gitleaks` (einmal pro Maschine).
4. GitHub: Secret scanning + Push protection aktivieren; Branch Protection
   mit den Checks `CI` und `Secret Scan` als Required.
5. Test-Infrastruktur aufsetzen, falls das Projekt neu ist — die
   `/feature`-Pipeline verweigert den Start ohne.
