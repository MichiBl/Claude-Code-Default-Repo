#!/usr/bin/env bash
#
# session-start.sh — SessionStart-Hook (matcher "startup").
#
# Installiert fehlende Dependencies, damit die verify.sh-Gates (Lint,
# Typecheck, Tests) auch in frisch geklonten Sessions greifen — v. a. in
# Claude Code on the Web, wo der Container ohne node_modules/.venv startet.
# Lokal ist der Hook ein No-op, sobald die Deps einmal installiert sind.
#
# Verhalten:
#   * package.json + fehlende node_modules  -> npm ci (bzw. npm install ohne Lockfile)
#   * uv.lock + nicht-synctes Env           -> uv sync --locked
#     (Braucht das Projekt Dev-Extras für die Gates: hier auf
#      `uv sync --locked --extra dev` anpassen.)
#
# Blockiert NIE die Session: immer exit 0, Meldungen auf stderr.

set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" || exit 0

# --- Node ----------------------------------------------------------------------
if [ -f package.json ] && [ ! -d node_modules ] && command -v npm >/dev/null 2>&1; then
  echo "session-start: node_modules fehlt — installiere Dependencies …" >&2
  if [ -f package-lock.json ]; then
    npm ci --no-audit --no-fund >/dev/null 2>&1 \
      || echo "session-start: 'npm ci' fehlgeschlagen — Gates laufen ggf. nicht (manuell 'npm install' ausführen)." >&2
  else
    npm install --no-audit --no-fund >/dev/null 2>&1 \
      || echo "session-start: 'npm install' fehlgeschlagen — Gates laufen ggf. nicht." >&2
  fi
fi

# --- Python (uv) ----------------------------------------------------------------
if [ -f uv.lock ] && command -v uv >/dev/null 2>&1; then
  # Nur syncen, wenn das Env die Gates noch nicht bedienen kann.
  if ! uv run --no-sync ruff --version >/dev/null 2>&1; then
    echo "session-start: uv-Env fehlt/unvollständig — 'uv sync --locked' …" >&2
    uv sync --locked >/dev/null 2>&1 \
      || echo "session-start: 'uv sync --locked' fehlgeschlagen — Gates laufen ggf. nicht." >&2
  fi
fi

exit 0
