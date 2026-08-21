# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/de/1.1.0/), Versionen
nach [SemVer](https://semver.org/lang/de/). Ein Release = Versions-Bump in
`VERSION` + Eintrag hier + Git-Tag (`vX.Y.Z`).

## [1.0.0] — 2026-08-21

Erstes versioniertes Release. Schließt die bekannten Schwächen des Setups:

### Added
- `.githooks/pre-push`: gitleaks-Scan über die exakten Commit-Ranges aus dem
  Push-Protokoll — fängt auch git-Aliasse, Skript-Pushes und
  `--no-verify`-Commits, die an der Claude-Schicht vorbeigehen.
- `setup.sh --doctor`: prüft alle Schutzschichten in einem Lauf (gitleaks,
  `core.hooksPath`, Hook-Verdrahtung, CLAUDE.md-Platzhalter, ci.yml,
  Lint-Gate, Kern-Deckung) und nennt je Befund den Behebungsbefehl.
- Verwaisten-Erkennung: `--diff`/`--update` melden Dateien in
  Kern-Verzeichnissen des Ziels, die das Template nicht kennt (ohne zu
  löschen, ohne den Exit-Code zu ändern).
- Template-Versionierung: `VERSION` + dieses Changelog; `setup.sh` stempelt
  `.claude/TEMPLATE_VERSION` ins Ziel, `--diff` meldet Template- vs.
  Projekt-Version.
- `.github/pull_request_template.md` mit dem MC-Checkbox-Gerüst.
- `session-start.sh` warnt beim Session-Start, wenn gitleaks fehlt.

### Changed
- `secret-scan.yml` ist jetzt KERN: der stack-unabhängige gitleaks-Backstop
  wird von `--update` aktualisiert statt still zu veralten.
- `core-drift.yml.example` klont das Template am letzten Release-Tag statt
  an `main` und zeigt die Versionsdifferenz in der Job-Zusammenfassung.
- `/feature`-Pipeline: maximal 3 Review-Zyklen, danach Eskalation an den
  User statt unbegrenztem Fix/Re-Review-Kreisen.
- `code-reviewer`/`qa-engineer` diffen gegen den erkannten Default-Branch
  statt hart gegen `main`.
- `verify.sh`: `ruff format --check` auch im pip-Pfad (Gleichstand mit uv).
- `session-start.sh`: Install-Output in Logdatei statt `/dev/null`; im
  Fehlerfall wird der Pfad genannt.
- `setup.sh` weist bei erkanntem Stack auf den auskommentierten
  Dependabot-Block (npm/pip/uv) hin.
