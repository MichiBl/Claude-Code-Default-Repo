# Git Hooks

Versionierte Git-Hooks für dieses Repo. Aktuell: ein **Pre-Commit-Secret-Scan**
(gitleaks), der das Committen von API-Keys, Tokens und Private Keys blockt.

## Aktivierung

```bash
git config core.hooksPath .githooks
brew install gitleaks   # macOS; sonst: https://github.com/gitleaks/gitleaks#installing
```

Node-Projekte können das automatisieren, indem sie in `package.json` ergänzen:

```json
"scripts": { "prepare": "git config core.hooksPath .githooks" }
```

## Schichten (Defense in Depth)

| Schicht | Wo | Blockt |
|---------|----|--------|
| **Claude-Hook** (`.claude/hooks/secret-scan.sh`) | in Claude-Code-Sessions | bevor Claude committet/pusht |
| **Pre-Commit-Hook** (dieses Verzeichnis) | lokal, jeder Commit | bevor der Commit entsteht — schnellste Linie, mit `--no-verify` umgehbar |
| **`Secret Scan`-Workflow** | CI, jeder PR/Push | vor dem Merge — nicht überspringbares Gate |
| **GitHub Push Protection** | serverseitig | bevor der Push GitHub erreicht — stärkste Linie, siehe unten |

Falsch-Positive / bewusst öffentliche Werte: `.gitleaks.toml` pflegen.

## Empfohlen: GitHub Push Protection aktivieren

Einmalig pro Repo auf GitHub: **Settings → Code security and analysis →**
**Secret scanning** aktivieren + **Push protection** aktivieren.
(Kostenlos für öffentliche Repos; private brauchen GitHub Advanced Security.)

> Landet ein Secret doch einmal im Remote: als kompromittiert behandeln und
> **rotieren** — den Commit zu entfernen reicht nicht, er bleibt in der Historie.
