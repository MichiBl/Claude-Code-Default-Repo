#!/usr/bin/env bash
#
# verify.sh — generischer Claude-Code-Stop-Hook (Hard-Gate).
#
# Führt am Ende jeder Antwort die Projekt-Gates aus (Lint, Typecheck, Tests)
# und spielt Fehler via stderr + exit 2 an Claude zurück, sodass der Loop
# weiterläuft, bis alles grün ist. Das macht die "verify"-Hälfte des
# Agent-Loops verpflichtend statt optional.
#
# Der Hook erkennt den Stack selbst:
#   * package.json                  -> npm-Gates (lint / tsc / test, soweit vorhanden)
#   * pyproject.toml + uv.lock      -> uv-Gates  (ruff / pytest)
#   * pyproject.toml|requirements.txt -> python -m Gates (ruff / mypy / pytest)
#
# Exit-Code-Vertrag mit Claude Code:
#   0 -> Stop erlauben (grün, oder nichts Relevantes zu prüfen)
#   2 -> Stop blockieren; stderr geht an Claude zurück
#
# Schutzmechanismen (jeder verhindert einen bekannten Fehlmodus):
#   (a) stop_hook_active == true  -> exit 0 (Endlosschleifen-Schutz)
#   (b) keine Quelldatei geändert -> exit 0 (Q&A-Turns bleiben schnell)
#   (c) Toolchain/Deps fehlen     -> exit 0 mit Hinweis (kein harter Fail
#       auf frischen Klonen)
#
# Optional: ONLY_LINT=1 (env in .claude/settings.json) -> nur Linter, keine Tests.
#
# Projekt-Override für andere Stacks (Go, Rust, Sonderfälle):
#   Existiert ein ausführbares .claude/hooks/verify-project.sh, wird NUR dieses
#   ausgeführt (gleicher Exit-Code-Vertrag: 0 = grün, 2 = blockieren mit
#   Begründung auf stderr). Die Stack-Autoerkennung unten entfällt dann.

set -uo pipefail

# --- Hook-Payload lesen; Endlosschleife verhindern ---------------------------
STDIN_JSON="$(cat 2>/dev/null || true)"
if printf '%s' "$STDIN_JSON" | grep -Eq '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
  exit 0
fi

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" || exit 0

# --- Geänderte Dateien ermitteln (Arbeitsbaum: tracked + untracked) ----------
# (git status --porcelain wäre kürzer, bricht aber bei Dateinamen mit
# Leerzeichen und bei Renames "R old -> new".)
CHANGED="$( { git diff --name-only HEAD 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } )"
[ -z "$CHANGED" ] && exit 0

# --- Projekt-Override: eigenes Gate-Skript ersetzt die Stack-Erkennung -------
if [ -x "$ROOT/.claude/hooks/verify-project.sh" ]; then
  exec "$ROOT/.claude/hooks/verify-project.sh"
fi

# --- Gate-Runner --------------------------------------------------------------
MAX_LINES=120
FAILED=""
OUT=""

run_gate() {
  local label="$1"; shift
  local result
  if ! result="$("$@" 2>&1)"; then
    FAILED="${FAILED}${label}; "
    OUT="${OUT}
=== ${label} (fehlgeschlagen) ===
${result}"
  fi
}

# --- Stack 1: Node / TypeScript ------------------------------------------------
if [ -f package.json ] && printf '%s\n' "$CHANGED" | grep -Eq '\.(ts|tsx|js|jsx|mjs|cjs)$'; then
  if [ ! -d node_modules ]; then
    echo "verify: node_modules fehlt — npm-Gates übersprungen ('npm install' aktiviert sie)." >&2
  else
    has_script() { node -e "process.exit(((require('./package.json').scripts||{})['$1'])?0:1)" 2>/dev/null; }
    has_script lint && run_gate "npm run lint" npm run lint
    if [ -f tsconfig.json ]; then
      # `tsc -b` folgt Project References (die `tsc --noEmit` allein ignoriert).
      run_gate "npx tsc -b --noEmit" npx tsc -b --noEmit
    fi
    if [ "${ONLY_LINT:-0}" != "1" ] && has_script test; then
      # CI=1 zwingt Vitest/Jest in den Single-Run-Modus (kein Watch-Mode).
      run_gate "npm test" env CI=1 npm test
    fi
  fi
fi

# --- Stack 2: Python -----------------------------------------------------------
if { [ -f pyproject.toml ] || [ -f requirements.txt ]; } && printf '%s\n' "$CHANGED" | grep -Eq '\.py$|pyproject\.toml$'; then
  if [ -f uv.lock ] && command -v uv >/dev/null 2>&1; then
    # uv-Projekt: Tools aus dem gepinnten Env, ohne implizites Sync.
    if uv run --no-sync ruff --version >/dev/null 2>&1; then
      run_gate "ruff check"        uv run --no-sync ruff check .
      run_gate "ruff format check" uv run --no-sync ruff format --check .
      if [ "${ONLY_LINT:-0}" != "1" ] && [ -d tests ]; then
        run_gate "pytest" uv run --no-sync pytest -q
      fi
    else
      echo "verify: dev-Deps fehlen — 'uv sync' ausführen. Python-Gates übersprungen." >&2
    fi
  else
    PY="python3"; command -v "$PY" >/dev/null 2>&1 || PY="python"
    have_module() { "$PY" -m "$1" --version >/dev/null 2>&1; }
    if have_module ruff; then
      run_gate "ruff check" "$PY" -m ruff check .
    else
      echo "verify: ruff nicht installiert — Lint übersprungen (pip install ruff)." >&2
    fi
    if have_module mypy && [ -d src ]; then
      run_gate "mypy src" "$PY" -m mypy src
    fi
    if [ "${ONLY_LINT:-0}" != "1" ] && have_module pytest && [ -d tests ]; then
      run_gate "pytest" env PYTHONPATH="src${PYTHONPATH:+:$PYTHONPATH}" "$PY" -m pytest -q
    fi
  fi
fi

# --- Ergebnis ------------------------------------------------------------------
if [ -n "$FAILED" ]; then
  {
    echo "Verifikation fehlgeschlagen: ${FAILED}"
    printf '%s\n' "$OUT" | tail -n "$MAX_LINES"
    echo ""
    echo "Bitte die obigen Gates fixen, dann abschließen."
  } >&2
  exit 2
fi

exit 0
