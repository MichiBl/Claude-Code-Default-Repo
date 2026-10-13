# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/de/1.1.0/), Versionen
nach [SemVer](https://semver.org/lang/de/). Ein Release = Versions-Bump in
`VERSION` + Eintrag hier + Git-Tag (`vX.Y.Z`).

## [Unreleased]

### Security

- `secret-scan.yml`: auf PRs gilt die `.gitleaks.toml` des Base-Branches.
  Vorher konnte ein PR sein eigenes Secret per Allowlist-Eintrag freigeben.
- `core-drift.yml.example`: `persist-credentials: false` — der Job führt
  `setup.sh` aus dem Template-Repo aus, das den Token sonst lesen könnte.
- `protect-secrets.sh` blockt Schreibzugriffe von Claude auf `.gitleaks.toml`:
  sonst konnte Claude einen Fund selbst als Falsch-Positiv freigeben.

### Fixed

- `secret-scan.sh`: scannt bei `git commit` auch nicht gestagte Änderungen an
  getrackten Dateien — `git commit -a` und Pfad-Commits kamen mit einem
  Secret an der Claude-Schicht vorbei.
- `setup.sh` (Kopier-Modus): überschreibt eine bestehende `core.hooksPath`
  (z. B. `.husky`) nicht mehr, sondern meldet sie — wie `--update` und
  `session-start.sh`.
- `setup.sh --doctor`: meldete falschen Kern-Verfall, wenn `setup.sh` kein
  Ausführungsbit hatte (interner Aufruf über `$0`).
- `session-start.sh` / `verify.sh`: prüfen das uv-Env per `python -m ruff`
  statt nacktem `ruff`. Ein global installiertes ruff täuschte ein
  vollständiges Env vor: session-start syncte nicht, verify.sh ließ die Gates
  gegen ein Env ohne Projekt-Dependencies laufen.
- `session-start.sh`: erkennt ein Dev-Extra (`[project.optional-dependencies]
  dev`) und synct mit `--extra dev`. Vorher fehlten ruff/pytest nach dem Sync,
  und verify.sh übersprang still alle Python-Gates.
- `secret-scan.yml`: `# pragma: allowlist secret` an `GITLEAKS_SHA256` —
  Zielprojekte mit detect-secrets wurden mit dem Kern-Update rot.

### Changed

- `ci-python-uv.yml.example`: `astral-sh/setup-uv` v10.0.1 -> v10.2.0 -> v10.3.0.
- `ci-node.yml.example`: `actions/setup-node` v7.0.0 -> v7.1.0.
- `/feature` ist mit der Roadmap `docs/requirements-status.md` verdrahtet:
  die AK des passenden Punkts gehen wörtlich an den `requirements-engineer`,
  der sie in einer Tabelle "Roadmap-Bezug" auf ACs abbildet, und der Punkt
  wird im PR abgehakt. Vorher konnte ein Roadmap-AK unbemerkt wegfallen, und
  der Punkt blieb nach dem Merge offen.
- Feature-Specs (`requirements.md`, `architecture.md`) beginnen mit einem
  Planungsstand-Vermerk: nicht nachgepflegt, maßgeblich ist der Code. `/fix`
  hängt bei geändertem, spezifiziertem Verhalten einen Einzeiler unter
  „Nachträge" an die Spec. Vorher hielt eine spätere Session eine veraltete
  Spec für den Ist-Zustand.

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
