#!/usr/bin/env bash
#
# hook-selftest.sh — Selbsttest für die Schutzmechanismen dieses Template-Repos.
#
# Prüft die Exit-Code-Verträge der Hooks gegen Wegwerf-Fixtures:
#   * protect-secrets.sh  -> blockt Write/Edit auf .env-/Key-Dateien (exit 2)
#   * verify.sh           -> Stop-Gate: rot blockt (exit 2), grün/leer erlaubt
#   * secret-scan.sh      -> blockt commit mit gestagtem Secret (exit 2)
#   * .githooks/pre-commit-> blockt gestagtes Secret lokal (exit 1)
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
  # die Testdatei selbst nicht als Fund werten.
  AWS_FAKE="AKIA""Q3J7X9FQ2P5W8N4Z"

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

# --- Ergebnis --------------------------------------------------------------------
echo
echo "Ergebnis: $PASS bestanden, $FAIL fehlgeschlagen, $SKIP übersprungen."
[ "$FAIL" -eq 0 ] || exit 1
exit 0
