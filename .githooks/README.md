# Git Hooks

Versionierte Git-Hooks für dieses Repo. Aktuell zwei gitleaks-Scans:

* **pre-commit** — blockt das Committen von API-Keys, Tokens und Private Keys
  (scannt die gestagten Änderungen).
* **pre-push** — blockt das Pushen von Secrets, die es trotzdem in die lokale
  Historie geschafft haben (`--no-verify`, Commits vor Hook-Aktivierung,
  Skripte). Scannt exakt die Commit-Ranges, die Git dem Hook per stdin
  übergibt — also genau das, was der Remote noch nicht hat.

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
| **`permissions.deny`** (`.claude/settings.json`) | in Claude-Code-Sessions | Lesezugriffe von Claude auf `.env`-Dateien/Keys (Best-Effort) |
| **Claude-Hook** (`.claude/hooks/protect-secrets.sh`) | in Claude-Code-Sessions | Schreibzugriffe (Edit/Write) auf dieselben Dateien — `.env.example` bleibt editierbar |
| **Claude-Hook** (`.claude/hooks/secret-scan.sh`) | in Claude-Code-Sessions | bevor Claude committet/pusht |
| **Pre-Commit-Hook** (dieses Verzeichnis) | lokal, jeder Commit | bevor der Commit entsteht — schnellste Linie, mit `--no-verify` umgehbar |
| **Pre-Push-Hook** (dieses Verzeichnis) | lokal, jeder Push | bevor Commits das Remote erreichen — fängt auch, was am pre-commit vorbeikam; mit `--no-verify` umgehbar |
| **`Secret Scan`-Workflow** | CI, jeder PR/Push | vor dem Merge — nicht überspringbares Gate |
| **GitHub Push Protection** | serverseitig | bevor der Push GitHub erreicht — stärkste Linie, siehe unten |

Falsch-Positive / bewusst öffentliche Werte: `.gitleaks.toml` pflegen.

## Empfohlen: GitHub Push Protection aktivieren

Einmalig pro Repo auf GitHub: **Settings → Code security and analysis →**
**Secret scanning** aktivieren + **Push protection** aktivieren.
(Kostenlos für öffentliche Repos; private brauchen GitHub Advanced Security.)

> Landet ein Secret doch einmal im Remote: als kompromittiert behandeln und
> **rotieren** — den Commit zu entfernen reicht nicht, er bleibt in der Historie.
