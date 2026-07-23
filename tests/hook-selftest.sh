#!/usr/bin/env bash
#
# hook-selftest.sh — Selbsttest für die Schutzmechanismen dieses Template-Repos.
#
# Prüft die Exit-Code-Verträge der Hooks gegen Wegwerf-Fixtures:
#   * protect-secrets.sh  -> blockt Write/Edit auf .env-/Key-Dateien (exit 2)
#   * verify.sh           -> Stop-Gate: rot blockt (exit 2), grün/leer erlaubt
#   * secret-scan.sh      -> blockt commit mit gestagtem Secret (exit 2)
#   * .githooks/pre-commit-> blockt gestagtes Secret lokal (exit 1)
#   * session-start.sh    -> installiert Deps, blockiert die Session NIE (exit 0)
#   * setup.sh            -> aktiviert ci.yml nach Stack, überschreibt nie
#   * Agenten-Regeln      -> Struktur-Check: tragende Abschnitte/Regeln der
#                            Agenten-Dateien sind nicht wegeditiert worden
#                            (das VERHALTEN der Agenten ist nicht testbar)
#
# Motivation: Die Hooks SIND das Produkt dieses Repos, und Shellskripte gehen
# leise kaputt — ein defektes Gate blockt nichts mehr, meldet sich aber auch
# nicht. Dieser Test macht Regressionen sichtbar, bevor Klone sie erben.
#
# Läuft nur im Template-Repo (CI: hook-selftest.yml mit Repo-Guard) und wird
# von setup.sh NICHT in Zielprojekte kopiert.
#
# Lokal ausführen: ./tests/hook-selftest.sh
# (gitleaks-abhängige Tests werden ohne gitleaks übersprungen — CI führt sie aus.)

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS="$ROOT/.claude/hooks"
PASS=0; FAIL=0; SKIP=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

check() { # check <label> <erwarteter-exit> <tatsächlicher-exit>
  local label="$1" want="$2" got="$3"
  if [ "$got" -eq "$want" ]; then
    echo "  ✓ $label (exit $got)"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $label — erwartet exit $want, bekommen exit $got"
    FAIL=$((FAIL + 1))
  fi
}

skip() {
  echo "  ⏭ $1"
  SKIP=$((SKIP + 1))
}

payload_write() { printf '{"tool_input":{"file_path":"%s"}}' "$1"; }
payload_bash()  { printf '{"tool_input":{"command":"%s"}}' "$1"; }

hook_exit() { # hook_exit <hook> <payload>  — Ausgabe verworfen, Exit-Code auf stdout
  local rc=0
  printf '%s' "$2" | bash "$1" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}

hook_exit_in() { # hook_exit_in <projektdir> <hook> <payload>
  local rc=0
  printf '%s' "$3" | env CLAUDE_PROJECT_DIR="$1" bash "$2" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}

hook_run_in() { # hook_run_in <projektdir> <hook> — setzt RC (Exit) und ERR (stderr)
  RC=0
  env CLAUDE_PROJECT_DIR="$1" bash "$2" >/dev/null 2>"$TMP/stderr.txt" </dev/null || RC=$?
  ERR="$(cat "$TMP/stderr.txt" 2>/dev/null || true)"
}

check_contains() { # check_contains <label> <needle> <text>
  local label="$1" needle="$2" text="$3"
  if printf '%s' "$text" | grep -qF -- "$needle"; then
    echo "  ✓ $label"; PASS=$((PASS + 1))
  else
    echo "  ✗ $label — '$needle' nicht gefunden"; FAIL=$((FAIL + 1))
  fi
}

check_absent() { # check_absent <label> <needle> <text>
  local label="$1" needle="$2" text="$3"
  if printf '%s' "$text" | grep -qF -- "$needle"; then
    echo "  ✗ $label — '$needle' unerwartet gefunden"; FAIL=$((FAIL + 1))
  else
    echo "  ✓ $label"; PASS=$((PASS + 1))
  fi
}

mkfix() { # mkfix <name> — frisches Git-Repo als Fixture, Pfad auf stdout
  local d="$TMP/$1"
  mkdir -p "$d"
  git -C "$d" init -q
  echo "$d"
}

git_t() { # git mit Wegwerf-Identität (Fixtures haben keine globale Config)
  git -c user.email=selftest@invalid -c user.name=selftest "$@"
}

# --- protect-secrets.sh --------------------------------------------------------
echo "== protect-secrets.sh =="
PS="$HOOKS/protect-secrets.sh"

check ".env wird geblockt"                 2 "$(hook_exit "$PS" "$(payload_write /proj/.env)")"
check ".env.production wird geblockt"      2 "$(hook_exit "$PS" "$(payload_write /proj/.env.production)")"
check "Key-Datei (*.pem) wird geblockt"    2 "$(hook_exit "$PS" "$(payload_write /proj/certs/server.pem)")"
check "secrets/-Pfad wird geblockt"        2 "$(hook_exit "$PS" "$(payload_write /proj/secrets/sa.json)")"
check ".env.example bleibt editierbar"     0 "$(hook_exit "$PS" "$(payload_write /proj/.env.example)")"
check "normale Quelldatei bleibt erlaubt"  0 "$(hook_exit "$PS" "$(payload_write /proj/src/app.ts)")"
check "kaputte Payload fällt offen durch"  0 "$(hook_exit "$PS" 'kein json')"

# --- verify.sh -------------------------------------------------------------------
echo "== verify.sh =="
V="$HOOKS/verify.sh"

d="$(mkfix stopactive)"
check "stop_hook_active beendet sofort (Schleifen-Schutz)" 0 \
  "$(hook_exit_in "$d" "$V" '{"stop_hook_active":true}')"

d="$(mkfix clean)"
check "keine geänderten Dateien -> Stop erlaubt" 0 \
  "$(hook_exit_in "$d" "$V" '{}')"

d="$(mkfix override)"
echo "x" > "$d/foo.js"
mkdir -p "$d/.claude/hooks"
printf '#!/usr/bin/env bash\nexit 2\n' > "$d/.claude/hooks/verify-project.sh"
chmod +x "$d/.claude/hooks/verify-project.sh"
check "Projekt-Override (verify-project.sh) greift" 2 \
  "$(hook_exit_in "$d" "$V" '{}')"

if command -v npm >/dev/null 2>&1; then
  d="$(mkfix nodered)"
  printf '{"scripts":{"lint":"exit 1"}}' > "$d/package.json"
  mkdir "$d/node_modules"
  echo "x" > "$d/foo.js"
  check "Node: rotes Lint blockiert den Stop" 2 \
    "$(hook_exit_in "$d" "$V" '{}')"

  d="$(mkfix nodegreen)"
  printf '{"scripts":{"lint":"exit 0"}}' > "$d/package.json"
  mkdir "$d/node_modules"
  echo "x" > "$d/foo.js"
  check "Node: grünes Lint erlaubt den Stop" 0 \
    "$(hook_exit_in "$d" "$V" '{}')"
else
  skip "npm nicht installiert — Node-Gate-Tests übersprungen."
fi

# --- secret-scan.sh & .githooks/pre-commit --------------------------------------
echo "== secret-scan.sh =="
SS="$HOOKS/secret-scan.sh"

d="$(mkfix scanidle)"
check "Nicht-Git-Befehl wird durchgewunken" 0 \
  "$(hook_exit_in "$d" "$SS" "$(payload_bash 'ls -la')")"

if command -v gitleaks >/dev/null 2>&1; then
  # Fake-Key zur Laufzeit zusammensetzen, damit die Secret-Scans dieses Repos
  # die Testdatei selbst nicht als Fund werten. Der Suffix muss Base32 sein
  # ([A-Z2-7], wie echte AWS-Keys — gitleaks >= 8.28 matcht nur noch das),
  # Entropie >= 3 haben und darf nicht auf EXAMPLE enden (Default-Allowlist).
  AWS_FAKE="AKIA""W7Q2X5J3ZP4TN6FR"

  HOT="$(mkfix scanhot)"
  git_t -C "$HOT" commit -q --allow-empty -m init
  printf 'aws_access_key_id = %s\n' "$AWS_FAKE" > "$HOT/config.txt"
  git -C "$HOT" add config.txt
  check "Commit mit gestagtem Fake-Key wird geblockt" 2 \
    "$(hook_exit_in "$HOT" "$SS" "$(payload_bash 'git commit -m test')")"

  OK="$(mkfix scanok)"
  git_t -C "$OK" commit -q --allow-empty -m init
  echo "nur text" > "$OK/notes.txt"
  git -C "$OK" add notes.txt
  check "Commit ohne Secret bleibt erlaubt" 0 \
    "$(hook_exit_in "$OK" "$SS" "$(payload_bash 'git commit -m test')")"

  echo "== .githooks/pre-commit =="
  rc=0; (cd "$HOT" && bash "$ROOT/.githooks/pre-commit") >/dev/null 2>&1 || rc=$?
  check "pre-commit blockt gestagtes Secret" 1 "$rc"
  rc=0; (cd "$OK" && bash "$ROOT/.githooks/pre-commit") >/dev/null 2>&1 || rc=$?
  check "pre-commit lässt sauberen Commit durch" 0 "$rc"
else
  skip "gitleaks nicht installiert — Scan-Tests übersprungen (CI führt sie aus)."
fi

# --- session-start.sh ------------------------------------------------------------
echo "== session-start.sh =="
SST="$HOOKS/session-start.sh"

d="$TMP/ss-leer"; mkdir -p "$d"
hook_run_in "$d" "$SST"
check "leeres Projekt -> No-op, blockiert nie" 0 "$RC"

if command -v npm >/dev/null 2>&1; then
  d="$TMP/ss-install"; mkdir -p "$d"
  printf '{}' > "$d/package.json"
  hook_run_in "$d" "$SST"
  check "fehlende node_modules lösen Install aus (exit 0)" 0 "$RC"
  check_contains "Install-Zweig meldet sich auf stderr" "node_modules fehlt" "$ERR"

  d="$TMP/ss-noop"; mkdir -p "$d/node_modules"
  printf '{}' > "$d/package.json"
  hook_run_in "$d" "$SST"
  check "vorhandene node_modules -> No-op" 0 "$RC"
  check_absent "No-op installiert nicht erneut" "node_modules fehlt" "$ERR"

  d="$TMP/ss-kaputt"; mkdir -p "$d"
  printf '{kaputt' > "$d/package.json"
  hook_run_in "$d" "$SST"
  check "fehlgeschlagener Install blockiert die Session nicht" 0 "$RC"
  check_contains "Fehlschlag wird gemeldet" "fehlgeschlagen" "$ERR"
else
  skip "npm nicht installiert — session-start-Tests übersprungen."
fi

# --- setup.sh: CI-Aktivierung ------------------------------------------------------
echo "== setup.sh: CI-Aktivierung =="
run_setup() { # run_setup <targetdir> — setup.sh still ausführen
  bash "$ROOT/setup.sh" "$1" >/dev/null 2>&1 || true
}

d="$TMP/ci-node"; mkdir -p "$d"; printf '{}' > "$d/package.json"
run_setup "$d"
rc=0; grep -q "npm ci" "$d/.github/workflows/ci.yml" 2>/dev/null || rc=1
check "Node-Stack -> ci.yml aktiviert (Node-Job)" 0 "$rc"

d="$TMP/ci-uv"; mkdir -p "$d"; touch "$d/pyproject.toml" "$d/uv.lock"
run_setup "$d"
rc=0
{ grep -q '^  uv:' "$d/.github/workflows/ci.yml" && \
  ! grep -q '^  pip:' "$d/.github/workflows/ci.yml"; } 2>/dev/null || rc=1
check "Python mit uv.lock -> nur uv-Job in ci.yml" 0 "$rc"

d="$TMP/ci-pip"; mkdir -p "$d"; touch "$d/requirements.txt"
run_setup "$d"
rc=0
{ grep -q '^  pip:' "$d/.github/workflows/ci.yml" && \
  ! grep -q '^  uv:' "$d/.github/workflows/ci.yml"; } 2>/dev/null || rc=1
check "Python ohne uv.lock -> nur pip-Job in ci.yml" 0 "$rc"

d="$TMP/ci-exist"; mkdir -p "$d/.github/workflows"
echo "# eigene CI" > "$d/.github/workflows/ci.yml"
printf '{}' > "$d/package.json"
run_setup "$d"
rc=0; grep -q "eigene CI" "$d/.github/workflows/ci.yml" || rc=1
check "existierende ci.yml bleibt unangetastet" 0 "$rc"

d="$TMP/ci-none"; mkdir -p "$d"
run_setup "$d"
rc=0; [ ! -e "$d/.github/workflows/ci.yml" ] || rc=1
check "unbekannter Stack -> keine ci.yml angelegt" 0 "$rc"

# --- Agenten-Regeln (Struktur) -----------------------------------------------------
# Testet nicht das VERHALTEN der Agenten (LLM — deterministisch nicht prüfbar),
# sondern dass ihre tragenden Regeln/Schema-Abschnitte bei späteren Edits
# nicht versehentlich verloren gehen.
echo "== Agenten-Regeln (Struktur) =="
marker() { # marker <datei> <text>
  if grep -qF -- "$2" "$ROOT/$1"; then
    echo "  ✓ $1: '$2' vorhanden"; PASS=$((PASS + 1))
  else
    echo "  ✗ $1 — Marker '$2' fehlt"; FAIL=$((FAIL + 1))
  fi
}
marker .claude/agents/code-reviewer.md "Verdict"
marker .claude/agents/code-reviewer.md "Verantwortlichkeits-Schnitt (SRP)"
marker .claude/agents/code-reviewer.md "Harte Grenzen"
marker .claude/agents/code-reviewer.md "Reuse Check"
marker .claude/agents/solution-architect.md "Reused Utilities"
marker .claude/agents/solution-architect.md "Eine Datei, eine Kernverantwortung"
marker .claude/agents/requirements-engineer.md "Acceptance Criteria"
marker .claude/agents/qa-engineer.md "qa-plan.md"
marker .claude/skills/feature/SKILL.md "GATE 1"
marker .claude/skills/feature/SKILL.md "GATE 2"
marker CLAUDE.md "eine Kernverantwortung"

# --- Ergebnis --------------------------------------------------------------------
echo
echo "Ergebnis: $PASS bestanden, $FAIL fehlgeschlagen, $SKIP übersprungen."
[ "$FAIL" -eq 0 ] || exit 1
exit 0
