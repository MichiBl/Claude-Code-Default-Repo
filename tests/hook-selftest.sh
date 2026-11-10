#!/usr/bin/env bash
#
# hook-selftest.sh — Selbsttest für die Schutzmechanismen dieses Template-Repos.
#
# Prüft die Exit-Code-Verträge der Hooks gegen Wegwerf-Fixtures:
#   * protect-secrets.sh  -> blockt Write/Edit auf .env-/Key-Dateien (exit 2)
#   * verify.sh           -> Stop-Gate: rot blockt (exit 2), grün/leer erlaubt
#   * secret-scan.sh      -> blockt commit mit gestagtem Secret (exit 2)
#   * .githooks/pre-commit-> blockt gestagtes Secret lokal (exit 1)
#   * .githooks/pre-push  -> blockt Secrets in den Push-Ranges (exit 1)
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

# PATH-Stub ohne python/python3. Belegt, dass die Hooks in einer Umgebung ohne
# Interpreter (z. B. Node-only-Container) nicht still durchfallen — CI-Runner
# haben python3, deshalb fiele genau dieser Fall sonst nie auf.
# gitleaks fehlt hier bewusst: secret-scan.sh läuft damit deterministisch in
# seinen dokumentierten (b)-Zweig, egal was auf dem Host installiert ist.
NOPY_BIN="$TMP/nopy-bin"; mkdir -p "$NOPY_BIN"
for t in bash cat sed head basename grep git; do
  p="$(command -v "$t" 2>/dev/null || true)"
  [ -n "$p" ] && ln -sf "$p" "$NOPY_BIN/$t"
done

hook_run_nopy() { # hook_run_nopy <projektdir> <hook> <payload> — setzt RC und ERR
  RC=0
  printf '%s' "$3" \
    | env -i PATH="$NOPY_BIN" CLAUDE_PROJECT_DIR="$1" bash "$2" \
      >/dev/null 2>"$TMP/stderr.txt" || RC=$?
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

# uv-Stub: bildet ein Projekt-Env OHNE Gate-Tools nach, während ein global
# installiertes ruff/pytest im PATH liegt. `uv run --no-sync python -m …`
# scheitert (Tool fehlt im Env), `uv run --no-sync <tool>` gelingt (globales
# Binary). Genau diese Lage täuschte den Hooks ein vollständiges Env vor.
# Jeder Aufruf landet in $UV_LOG, damit die Tests die Sync-Argumente sehen.
UVSTUB_BIN="$TMP/uvstub-bin"; mkdir -p "$UVSTUB_BIN"
cat > "$UVSTUB_BIN/uv" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$UV_LOG"
case "$*" in
  "run --no-sync python -m "*) exit 1 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$UVSTUB_BIN/uv"

hook_run_uvstub() { # hook_run_uvstub <projektdir> <hook> <payload> — setzt RC, ERR, UVCALLS
  RC=0; : > "$TMP/uv.log"
  printf '%s' "$3" \
    | env PATH="$UVSTUB_BIN:$PATH" UV_LOG="$TMP/uv.log" CLAUDE_PROJECT_DIR="$1" bash "$2" \
      >/dev/null 2>"$TMP/stderr.txt" || RC=$?
  ERR="$(cat "$TMP/stderr.txt" 2>/dev/null || true)"
  UVCALLS="$(cat "$TMP/uv.log")"
}

# --- protect-secrets.sh --------------------------------------------------------
echo "== protect-secrets.sh =="
PS="$HOOKS/protect-secrets.sh"

check ".env wird geblockt"                 2 "$(hook_exit "$PS" "$(payload_write /proj/.env)")"
check ".env.production wird geblockt"      2 "$(hook_exit "$PS" "$(payload_write /proj/.env.production)")"
check "Key-Datei (*.pem) wird geblockt"    2 "$(hook_exit "$PS" "$(payload_write /proj/certs/server.pem)")"
check "secrets/-Pfad wird geblockt"        2 "$(hook_exit "$PS" "$(payload_write /proj/secrets/sa.json)")"
check ".env.example bleibt editierbar"     0 "$(hook_exit "$PS" "$(payload_write /proj/.env.example)")"
check ".env.dist wird geblockt"            2 "$(hook_exit "$PS" "$(payload_write /proj/.env.dist)")"
check ".env.template wird geblockt"        2 "$(hook_exit "$PS" "$(payload_write /proj/.env.template)")"
check ".npmrc wird geblockt"               2 "$(hook_exit "$PS" "$(payload_write /proj/.npmrc)")"
check ".netrc wird geblockt"               2 "$(hook_exit "$PS" "$(payload_write /proj/.netrc)")"
check "Keystore (*.p12) wird geblockt"     2 "$(hook_exit "$PS" "$(payload_write /proj/certs/keystore.p12)")"
check "service-account*.json wird geblockt" 2 "$(hook_exit "$PS" "$(payload_write /proj/service-account-prod.json)")"
check "SSH-Key (id_rsa) wird geblockt"     2 "$(hook_exit "$PS" "$(payload_write /proj/id_rsa)")"
check "normale Quelldatei bleibt erlaubt"  0 "$(hook_exit "$PS" "$(payload_write /proj/src/app.ts)")"
check "kaputte Payload fällt offen durch"  0 "$(hook_exit "$PS" 'kein json')"
# Die Allowlist steuert, was alle gitleaks-Schichten durchlassen — Claude
# könnte sonst einen Fund selbst "als Falsch-Positiv" freigeben.
check ".gitleaks.toml wird geblockt"       2 "$(hook_exit "$PS" "$(payload_write /proj/.gitleaks.toml)")"
# .gitleaksignore ist der zweite Hebel derselben Sorte: ein Fingerprint dort
# gibt einen Fund genauso frei wie ein Allowlist-Eintrag.
check ".gitleaksignore wird geblockt"      2 "$(hook_exit "$PS" "$(payload_write /proj/.gitleaksignore)")"

# Ohne Interpreter muss der Hook weiter blocken UND es sagen — vorher fiel er
# hier lautlos mit exit 0 durch.
hook_run_nopy "$TMP" "$PS" "$(payload_write /proj/.env)"
check "ohne python3: .env wird weiter geblockt" 2 "$RC"
check_contains "ohne python3: Ausfall wird gemeldet" "kein python3/python gefunden" "$ERR"
check_contains "ohne python3: Backstop wird benannt" "pre-commit" "$ERR"

hook_run_nopy "$TMP" "$PS" "$(payload_write /proj/src/app.ts)"
check "ohne python3: normale Datei bleibt erlaubt" 0 "$RC"

# --- verify.sh -------------------------------------------------------------------
echo "== verify.sh =="
V="$HOOKS/verify.sh"

d="$(mkfix stopactive)"
check "stop_hook_active beendet sofort (Schleifen-Schutz)" 0 \
  "$(hook_exit_in "$d" "$V" '{"stop_hook_active":true}')"

d="$(mkfix clean)"
check "keine geänderten Dateien -> Stop erlaubt" 0 \
  "$(hook_exit_in "$d" "$V" '{}')"

# Gleichstand der Python-Pfade: `ruff format --check` lief nur im uv-Zweig —
# pip-Projekte bekamen still kein Format-Gate. (Struktur-Check: der pip-Pfad
# ist ohne installiertes pip-ruff nicht deterministisch ausführbar.)
rc=0; [ "$(grep -c 'ruff format --check' "$V")" -eq 2 ] || rc=1
check "ruff format --check in beiden Python-Pfaden (uv + pip)" 0 "$rc"

d="$(mkfix override)"
echo "x" > "$d/foo.js"
mkdir -p "$d/.claude/hooks"
printf '#!/usr/bin/env bash\nexit 2\n' > "$d/.claude/hooks/verify-project.sh"
chmod +x "$d/.claude/hooks/verify-project.sh"
check "Projekt-Override (verify-project.sh) greift" 2 \
  "$(hook_exit_in "$d" "$V" '{}')"

# Ein global installiertes ruff darf kein vollständiges uv-Env vortäuschen:
# sonst liefen die Gates gegen ein Env ohne Projekt-Dependencies, und pytest
# scheiterte an Importen statt am Code. Erwartet: Gates übersprungen, mit
# Hinweis — nicht still gegen das falsche Env gelaufen.
d="$(mkfix uv-global-ruff)"
printf '[project]\nname = "x"\n' > "$d/pyproject.toml"; touch "$d/uv.lock"
echo "x = 1" > "$d/app.py"
hook_run_uvstub "$d" "$V" '{}'
check "uv: globales ruff täuscht kein Env vor (Stop erlaubt)" 0 "$RC"
check_contains "uv: fehlende Dev-Deps werden gemeldet" "dev-Deps fehlen" "$ERR"
check_absent "uv: keine Gates gegen globales ruff" "run --no-sync ruff" "$UVCALLS"

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

# Ohne Interpreter blieb CMD leer, die Erkennung matchte nie und der Scan
# entfiel still. Der (b)-Hinweis auf fehlendes gitleaks belegt, dass der Hook
# den commit jetzt trotzdem erkennt und bis zum Scan durchläuft.
hook_run_nopy "$d" "$SS" "$(payload_bash 'git commit -m test')"
check "ohne python3: Hook blockiert nichts fälschlich" 0 "$RC"
check_contains "ohne python3: Ausfall wird gemeldet" "kein python3/python gefunden" "$ERR"
check_contains "ohne python3: commit wird trotzdem erkannt" "gitleaks nicht installiert" "$ERR"

hook_run_nopy "$d" "$SS" "$(payload_bash 'ls -la')"
check_absent "ohne python3: Nicht-Git-Befehl löst keinen Scan aus" "gitleaks nicht installiert" "$ERR"

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

  # Regression: das Wort "push" in der Commit-Message darf den Befehl nicht in
  # den Push-Zweig schieben — der sieht die gestagten Aenderungen nicht an.
  check "Commit-Message mit 'git push' wird trotzdem als Commit gescannt" 2 \
    "$(hook_exit_in "$HOT" "$SS" \
       '{"tool_input":{"command":"git commit -m \"docs: erklaere git push flow\""}}')"

  OK="$(mkfix scanok)"
  git_t -C "$OK" commit -q --allow-empty -m init
  echo "nur text" > "$OK/notes.txt"
  git -C "$OK" add notes.txt
  check "Commit ohne Secret bleibt erlaubt" 0 \
    "$(hook_exit_in "$OK" "$SS" "$(payload_bash 'git commit -m test')")"

  # Regression: `git commit -a` (und Pfad-Commits) holen den Inhalt erst beim
  # Commit aus dem Arbeitsbaum — --staged allein sah das Secret nicht.
  AM="$(mkfix scanam)"
  echo "harmlos" > "$AM/config.txt"
  git -C "$AM" add config.txt
  git_t -C "$AM" commit -q -m init
  printf 'aws_access_key_id = %s\n' "$AWS_FAKE" > "$AM/config.txt"
  check "git commit -am mit nicht gestagtem Fake-Key wird geblockt" 2 \
    "$(hook_exit_in "$AM" "$SS" "$(payload_bash 'git commit -am wip')")"

  # Regression: `git add x && git commit` in EINEM Befehl. Der Hook läuft vor
  # dem Befehl — die Datei ist dann weder gestagt noch getrackt, --staged und
  # --pre-commit sahen sie beide nicht. Die üblichste Art, wie Claude committet.
  ADD="$(mkfix scanadd)"
  git_t -C "$ADD" commit -q --allow-empty -m init
  printf 'aws_access_key_id = %s\n' "$AWS_FAKE" > "$ADD/config.txt"
  check "git add && git commit mit ungetracktem Fake-Key wird geblockt" 2 \
    "$(hook_exit_in "$ADD" "$SS" "$(payload_bash 'git add config.txt && git commit -m wip')")"
  # Der Scan läuft über einen Wegwerf-Index — der echte darf danach nichts
  # gestagt haben, sonst committete der nächste Befehl mehr als verlangt.
  rc=0; [ -z "$(git -C "$ADD" diff --cached --name-only)" ] || rc=1
  check "Scan der ungetrackten Dateien lässt den echten Index unberührt" 0 "$rc"
  ADDOK="$(mkfix scanaddok)"
  git_t -C "$ADDOK" commit -q --allow-empty -m init
  echo "nur text" > "$ADDOK/notes.txt"
  check "git add && git commit ohne Secret bleibt erlaubt" 0 \
    "$(hook_exit_in "$ADDOK" "$SS" "$(payload_bash 'git add notes.txt && git commit -m wip')")"

  # Regression: ein `gitleaks:allow`-Kommentar auf der Secret-Zeile gab den
  # Fund in ALLEN Schichten frei — an der .gitleaks.toml-Sperre vorbei.
  ALLOW="$(mkfix scanallow)"
  echo "nur text" > "$ALLOW/notes.txt"
  git -C "$ALLOW" add notes.txt
  git_t -C "$ALLOW" commit -q -m init
  ALLOW_BASE="$(git -C "$ALLOW" rev-parse HEAD)"
  printf 'aws_access_key_id = %s  # gitleaks:allow\n' "$AWS_FAKE" > "$ALLOW/config.txt"
  git -C "$ALLOW" add config.txt
  check "secret-scan.sh ignoriert gitleaks:allow" 2 \
    "$(hook_exit_in "$ALLOW" "$SS" "$(payload_bash 'git commit -m test')")"
  rc=0; (cd "$ALLOW" && bash "$ROOT/.githooks/pre-commit") >/dev/null 2>&1 || rc=$?
  check "pre-commit ignoriert gitleaks:allow" 1 "$rc"
  git_t -C "$ALLOW" commit -q -m leak
  rc=0
  printf 'refs/heads/main %s refs/heads/main %s\n' "$(git -C "$ALLOW" rev-parse HEAD)" "$ALLOW_BASE" \
    | (cd "$ALLOW" && bash "$ROOT/.githooks/pre-push" origin dummy-url) >/dev/null 2>&1 || rc=$?
  check "pre-push ignoriert gitleaks:allow" 1 "$rc"

  echo "== .githooks/pre-commit =="
  rc=0; (cd "$HOT" && bash "$ROOT/.githooks/pre-commit") >/dev/null 2>&1 || rc=$?
  check "pre-commit blockt gestagtes Secret" 1 "$rc"
  rc=0; (cd "$OK" && bash "$ROOT/.githooks/pre-commit") >/dev/null 2>&1 || rc=$?
  check "pre-commit lässt sauberen Commit durch" 0 "$rc"

  # pre-push bekommt von Git die Push-Ranges per stdin (Format:
  # "<local_ref> <local_sha> <remote_ref> <remote_sha>"). Die Fixtures
  # simulieren genau diese Zeilen — ein echter Remote ist dafür nicht nötig.
  echo "== .githooks/pre-push =="
  PP="$ROOT/.githooks/pre-push"
  Z40="0000000000000000000000000000000000000000"

  # Historie: 1. Commit sauber, 2. Commit enthält das Fake-Secret. Damit lässt
  # sich derselbe Stand als "alles neu" (remote_sha = 0…0) und als
  # Delta-Push (remote_sha = 1. Commit) prüfen.
  PUSHFIX="$(mkfix pushhot)"
  echo "nur text" > "$PUSHFIX/notes.txt"
  git -C "$PUSHFIX" add notes.txt
  git_t -C "$PUSHFIX" commit -q -m "sauber"
  BASE_SHA="$(git -C "$PUSHFIX" rev-parse HEAD)"
  printf 'aws_access_key_id = %s\n' "$AWS_FAKE" > "$PUSHFIX/config.txt"
  git -C "$PUSHFIX" add config.txt
  git_t -C "$PUSHFIX" commit -q -m "leak"
  HEAD_SHA="$(git -C "$PUSHFIX" rev-parse HEAD)"

  rc=0
  printf 'refs/heads/main %s refs/heads/main %s\n' "$HEAD_SHA" "$Z40" \
    | (cd "$PUSHFIX" && bash "$PP" origin dummy-url) >/dev/null 2>&1 || rc=$?
  check "pre-push blockt Secret beim Erst-Push (neuer Branch)" 1 "$rc"

  rc=0
  printf 'refs/heads/main %s refs/heads/main %s\n' "$HEAD_SHA" "$BASE_SHA" \
    | (cd "$PUSHFIX" && bash "$PP" origin dummy-url) >/dev/null 2>&1 || rc=$?
  check "pre-push blockt Secret im Delta-Range" 1 "$rc"

  # Range remote==local: der Remote hat schon alles — auch mit Secret in der
  # Historie darf der (leere) Push nicht blockiert werden.
  rc=0
  printf 'refs/heads/main %s refs/heads/main %s\n' "$HEAD_SHA" "$HEAD_SHA" \
    | (cd "$PUSHFIX" && bash "$PP" origin dummy-url) >/dev/null 2>&1 || rc=$?
  check "pre-push lässt leeren Range durch (Remote aktuell)" 0 "$rc"

  # Branch-Löschung (local_sha = 0…0): es geht nichts zum Remote.
  rc=0
  printf '(delete) %s refs/heads/alt %s\n' "$Z40" "$HEAD_SHA" \
    | (cd "$PUSHFIX" && bash "$PP" origin dummy-url) >/dev/null 2>&1 || rc=$?
  check "pre-push lässt Branch-Löschung durch" 0 "$rc"

  PUSHOK="$(mkfix pushok)"
  echo "nur text" > "$PUSHOK/notes.txt"
  git -C "$PUSHOK" add notes.txt
  git_t -C "$PUSHOK" commit -q -m "sauber"
  OK_SHA="$(git -C "$PUSHOK" rev-parse HEAD)"
  rc=0
  printf 'refs/heads/main %s refs/heads/main %s\n' "$OK_SHA" "$Z40" \
    | (cd "$PUSHOK" && bash "$PP" origin dummy-url) >/dev/null 2>&1 || rc=$?
  check "pre-push lässt sauberen Push durch" 0 "$rc"
else
  skip "gitleaks nicht installiert — Scan-Tests übersprungen (CI führt sie aus)."
fi

# Ohne gitleaks muss pre-push durchwinken UND den tragenden Backstop nennen —
# derselbe Vertrag wie bei pre-commit (Graceful Degradation, nie still).
rc=0
out="$(printf 'refs/heads/main 1111111111111111111111111111111111111111 refs/heads/main 0000000000000000000000000000000000000000\n' \
  | env -i PATH="$NOPY_BIN" bash "$ROOT/.githooks/pre-push" origin dummy-url 2>&1)" || rc=$?
check "pre-push ohne gitleaks winkt durch (exit 0)" 0 "$rc"
check_contains "pre-push ohne gitleaks nennt den CI-Backstop" "CI erzwingt ihn trotzdem" "$out"

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
  # Der Install-Output ging früher nach /dev/null — der Grund des Fehlschlags
  # war damit unauffindbar. Jetzt muss die Meldung die Logdatei nennen.
  check_contains "Fehlschlag nennt die Logdatei" "session-start-install.log" "$ERR"
else
  skip "npm nicht installiert — session-start-Tests übersprungen."
fi

# npm-Stub: protokolliert die Argumente und scheitert. Ohne Lockfile löst
# `npm install` die neuesten Versionen auf und führte deren Install-Skripte
# ungefragt aus — der Fall, gegen den der Dependabot-Cooldown gebaut ist.
NPMSTUB_BIN="$TMP/npmstub-bin"; mkdir -p "$NPMSTUB_BIN"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$NPM_LOG"\nexit 1\n' > "$NPMSTUB_BIN/npm"
chmod +x "$NPMSTUB_BIN/npm"
d="$TMP/ss-nolock"; mkdir -p "$d" "$TMP/ss-tmp"
printf '{}' > "$d/package.json"
: > "$TMP/npm.log"; RC=0
env PATH="$NPMSTUB_BIN:$PATH" NPM_LOG="$TMP/npm.log" TMPDIR="$TMP/ss-tmp" CLAUDE_PROJECT_DIR="$d" \
  bash "$SST" >/dev/null 2>"$TMP/stderr.txt" </dev/null || RC=$?
ERR="$(cat "$TMP/stderr.txt")"
check "ohne Lockfile: session-start blockiert nie" 0 "$RC"
check_contains "ohne Lockfile: npm install läuft ohne Install-Skripte" "--ignore-scripts" "$(cat "$TMP/npm.log")"
check_contains "ohne Lockfile: die Einschränkung wird gemeldet" "ohne Install-Skripte" "$ERR"
# Fester Name in /tmp: auf einem Mehrbenutzer-System kann ein anderer Nutzer
# dort vorab einen Symlink ablegen, den der Hook dann überschreibt.
rc=0; [ ! -e "$TMP/ss-tmp/claude-session-start-install.log" ] || rc=1
check "Install-Log liegt nicht unter einem vorhersagbaren Namen" 0 "$rc"
d="$TMP/ss-lock"; mkdir -p "$d"
printf '{}' > "$d/package.json"; printf '{}' > "$d/package-lock.json"
: > "$TMP/npm.log"
env PATH="$NPMSTUB_BIN:$PATH" NPM_LOG="$TMP/npm.log" CLAUDE_PROJECT_DIR="$d" \
  bash "$SST" >/dev/null 2>&1 </dev/null || true
check_absent "mit Lockfile: npm ci behält die Install-Skripte" "--ignore-scripts" "$(cat "$TMP/npm.log")"

# core.hooksPath steht in .git/config und wird nicht mitversioniert — nach jedem
# frischen Klon muss der Hook sich selbst verdrahten, sonst läuft der
# Pre-Commit-Secret-Scan nie.
d="$(mkfix ss-hookspath)"
mkdir -p "$d/.githooks"; touch "$d/.githooks/pre-commit"
hook_run_in "$d" "$SST"
check "session-start blockiert nie (hooksPath-Zweig)" 0 "$RC"
rc=0; [ "$(git -C "$d" config --get core.hooksPath)" = ".githooks" ] || rc=1
check "session-start verdrahtet core.hooksPath im frischen Klon" 0 "$rc"

git -C "$d" config core.hooksPath .myhooks
hook_run_in "$d" "$SST"
rc=0; [ "$(git -C "$d" config --get core.hooksPath)" = ".myhooks" ] || rc=1
check "session-start überschreibt eigene hooksPath-Wahl nicht" 0 "$rc"

d="$(mkfix ss-ohne-githooks)"
hook_run_in "$d" "$SST"
rc=0; [ -z "$(git -C "$d" config --get core.hooksPath || true)" ] || rc=1
check "ohne .githooks/pre-commit wird nichts gesetzt" 0 "$rc"

# Ohne gitleaks muss der Session-Start warnen (nie blockieren) — sonst fällt
# das Fehlen der lokalen Secret-Schichten erst beim ersten Commit auf.
# (NOPY_BIN enthält kein gitleaks, egal was auf dem Host installiert ist.)
d="$(mkfix ss-ohne-gitleaks)"
hook_run_nopy "$d" "$SST" ""
check "ohne gitleaks: session-start blockiert nicht" 0 "$RC"
check_contains "ohne gitleaks: Warnung auf stderr" "gitleaks nicht installiert" "$ERR"

# uv-Env-Prüfung: ein global installiertes ruff verhinderte den Sync, und
# Dev-Extras ([project.optional-dependencies] dev) kamen ohne --extra dev
# nie ins Env — verify.sh übersprang danach still alle Python-Gates.
d="$TMP/ss-uv-extra"; mkdir -p "$d"
printf '[project]\nname = "x"\n\n[project.optional-dependencies]\ndev = ["ruff", "pytest"]\n' > "$d/pyproject.toml"
touch "$d/uv.lock"
hook_run_uvstub "$d" "$SST" ""
check "uv: session-start blockiert nie" 0 "$RC"
check_contains "uv: globales ruff verhindert den Sync nicht" "sync --locked" "$UVCALLS"
check_contains "uv: Dev-Extra wird erkannt und mitinstalliert" "sync --locked --extra dev" "$UVCALLS"

# dependency-groups "dev" installiert uv per Default — dort wäre --extra dev
# ein Fehler (uv bricht bei unbekanntem Extra ab).
d="$TMP/ss-uv-group"; mkdir -p "$d"
printf '[project]\nname = "x"\n\n[dependency-groups]\ndev = ["ruff", "pytest"]\n' > "$d/pyproject.toml"
touch "$d/uv.lock"
hook_run_uvstub "$d" "$SST" ""
check_contains "uv: ohne Dev-Extra wird trotzdem gesynct" "sync --locked" "$UVCALLS"
check_absent "uv: kein --extra dev ohne optional-dependencies.dev" "--extra dev" "$UVCALLS"

# --- setup.sh: CI-Aktivierung ------------------------------------------------------
echo "== setup.sh: CI-Aktivierung =="
run_setup() { # run_setup <targetdir> — setup.sh still ausführen
  bash "$ROOT/setup.sh" "$1" >/dev/null 2>&1 || true
}

# Prüft, dass die aktivierte ci.yml die gewählte Vorlage VOLLSTÄNDIG enthält.
# Früher schnitt setup.sh den nicht passenden Job per awk aus einer gemeinsamen
# Python-Vorlage; eine geänderte Einrückung hätte still eine halbe ci.yml
# erzeugt, die die Job-Namen-Checks unten trotzdem bestanden hätte.
check_ci_vollstaendig() { # check_ci_vollstaendig <label> <vorlage> <ci.yml>
  local want got rc=0
  want="$(grep -c '^      - name:' "$2" 2>/dev/null || echo 0)"
  got="$(grep -c '^      - name:' "$3" 2>/dev/null || echo 0)"
  { [ "$want" -gt 0 ] && [ "$want" -eq "$got" ]; } || rc=1
  check "$1 ($got/$want Steps)" 0 "$rc"
}

d="$TMP/ci-node"; mkdir -p "$d"; printf '{}' > "$d/package.json"
run_setup "$d"
rc=0; grep -q "npm ci" "$d/.github/workflows/ci.yml" 2>/dev/null || rc=1
check "Node-Stack -> ci.yml aktiviert (Node-Job)" 0 "$rc"
check_ci_vollstaendig "Node-Vorlage vollständig übernommen" \
  "$ROOT/.github/workflows/ci-node.yml.example" "$d/.github/workflows/ci.yml"

d="$TMP/ci-uv"; mkdir -p "$d"; touch "$d/pyproject.toml" "$d/uv.lock"
run_setup "$d"
rc=0
{ grep -q '^  uv:' "$d/.github/workflows/ci.yml" && \
  ! grep -q '^  pip:' "$d/.github/workflows/ci.yml"; } 2>/dev/null || rc=1
check "Python mit uv.lock -> nur uv-Job in ci.yml" 0 "$rc"
check_ci_vollstaendig "uv-Vorlage vollständig übernommen" \
  "$ROOT/.github/workflows/ci-python-uv.yml.example" "$d/.github/workflows/ci.yml"

d="$TMP/ci-pip"; mkdir -p "$d"; touch "$d/requirements.txt"
run_setup "$d"
rc=0
{ grep -q '^  pip:' "$d/.github/workflows/ci.yml" && \
  ! grep -q '^  uv:' "$d/.github/workflows/ci.yml"; } 2>/dev/null || rc=1
check "Python ohne uv.lock -> nur pip-Job in ci.yml" 0 "$rc"
check_ci_vollstaendig "pip-Vorlage vollständig übernommen" \
  "$ROOT/.github/workflows/ci-python-pip.yml.example" "$d/.github/workflows/ci.yml"

# Dependabot-Hinweis: die npm-/pip-Blöcke der Vorlage sind auskommentiert —
# bei erkanntem Stack muss setup.sh darauf hinweisen (und schweigen, sobald
# das Projekt den Block aktiviert hat).
d="$TMP/ci-dbot"; mkdir -p "$d"; printf '{}' > "$d/package.json"
out="$(bash "$ROOT/setup.sh" "$d" 2>&1)"
check_contains "Node-Stack -> Hinweis auf auskommentierten Dependabot-Block" "dependabot.yml einkommentieren" "$out"
printf 'version: 2\nupdates:\n  - package-ecosystem: npm\n' > "$d/.github/dependabot.yml"
out="$(bash "$ROOT/setup.sh" "$d" 2>&1)"
check_absent "aktivierter npm-Block -> kein Hinweis mehr" "dependabot.yml einkommentieren" "$out"

d="$TMP/ci-dbot-py"; mkdir -p "$d"; touch "$d/pyproject.toml" "$d/uv.lock"
out="$(bash "$ROOT/setup.sh" "$d" 2>&1)"
check_contains "Python-Stack -> Hinweis auf auskommentierten Dependabot-Block" "dependabot.yml einkommentieren" "$out"

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

# Template-eigene Dateien duerfen nicht in Zielprojekte wandern: verify-project.sh
# wuerde dort die Stack-Autoerkennung von verify.sh abschalten und diesen
# Selbsttest suchen, hook-selftest.yml wuerde als CI die Template-Hooks testen.
rc=0; [ ! -e "$d/.claude/hooks/verify-project.sh" ] || rc=1
check "verify-project.sh wandert nicht ins Zielprojekt" 0 "$rc"
rc=0; [ ! -e "$d/.github/workflows/hook-selftest.yml" ] || rc=1
check "hook-selftest.yml wandert nicht ins Zielprojekt" 0 "$rc"
rc=0; [ ! -e "$d/.github/workflows/template-pin-check.yml" ] || rc=1
check "template-pin-check.yml wandert nicht ins Zielprojekt" 0 "$rc"
rc=0; [ -e "$d/.claude/hooks/verify.sh" ] || rc=1
check "verify.sh (KERN) wird weiterhin kopiert" 0 "$rc"

# Die CLAUDE.md im Repo-Root ist der Kontext DIESES Repos; ins Zielprojekt
# gehoert weiterhin die unveraenderte Platzhalter-Vorlage aus templates/.
rc=0; grep -q '<install>' "$d/CLAUDE.md" 2>/dev/null || rc=1
check "Zielprojekt bekommt die Platzhalter-Vorlage, nicht diesen Kontext" 0 "$rc"
rc=0; cmp -s "$ROOT/templates/CLAUDE.md" "$d/CLAUDE.md" || rc=1
check "kopierte CLAUDE.md ist byte-identisch zu templates/CLAUDE.md" 0 "$rc"

# Die Drift-Vorlage nuetzt nur im Zielprojekt — sie muss dort ankommen.
rc=0; [ -e "$d/.github/workflows/core-drift.yml.example" ] || rc=1
check "core-drift.yml.example wandert ins Zielprojekt" 0 "$rc"

# Die LICENSE deckt DIESES Repo ab. Ein Zielprojekt waehlt seine Lizenz selbst —
# ihm eine fremde ins Wurzelverzeichnis zu legen waere eine Rechtsaussage, die
# setup.sh nicht treffen darf.
rc=0; [ ! -e "$d/LICENSE" ] || rc=1
check "LICENSE wandert nicht ins Zielprojekt" 0 "$rc"

# --- setup.sh: --diff / --update (Werkzeug-Kern) ------------------------------------
# Der Kern (Agents/Skills/Hooks) muss in allen Projekten identisch sein;
# PROJEKT-Dateien (CLAUDE.md & Co.) dürfen und sollen abweichen.
echo "== setup.sh: --diff / --update =="

d="$TMP/sync-clean"; mkdir -p "$d"
run_setup "$d"
bash "$ROOT/setup.sh" --diff "$d" >/dev/null 2>&1; rc=$?
check "frisch aufgesetzt -> --diff meldet keinen Kern-Verfall" 0 "$rc"

# Regression: eine FEHLENDE PROJEKT-Datei darf den Lauf nicht abbrechen.
# (Ein "is_core X && …" am Funktionsende lieferte Exit 1 und beendete unter
# `set -e` das Skript beim ersten solchen Treffer — halber Report, Exit 0.)
d="$TMP/sync-projektluecke"; mkdir -p "$d"
run_setup "$d"
rm -f "$d/CLAUDE.md" "$d/.gitignore"
out="$(bash "$ROOT/setup.sh" --diff "$d" 2>&1)"; rc=$?
check "fehlende PROJEKT-Datei bricht --diff nicht ab" 0 "$rc"
check_contains "--diff läuft bis zur Zusammenfassung durch" "Ergebnis:" "$out"

# Kern-Verfall: erkennen, dann per --update heilen.
d="$TMP/sync-kernverfall"; mkdir -p "$d"
run_setup "$d"
echo "# lokal verbogen" >> "$d/.claude/agents/code-reviewer.md"
rm -f "$d/.claude/hooks/verify.sh"
echo "eigener Inhalt" > "$d/CLAUDE.md"
bash "$ROOT/setup.sh" --diff "$d" >/dev/null 2>&1; rc=$?
check "Kern-Abweichung -> --diff meldet Exit 1" 1 "$rc"

bash "$ROOT/setup.sh" --update "$d" >/dev/null 2>&1; rc=$?
check "--update läuft durch" 0 "$rc"
rc=0; cmp -s "$ROOT/.claude/agents/code-reviewer.md" "$d/.claude/agents/code-reviewer.md" || rc=1
check "--update stellt verbogene Kern-Datei her" 0 "$rc"
rc=0; cmp -s "$ROOT/.claude/hooks/verify.sh" "$d/.claude/hooks/verify.sh" || rc=1
check "--update ergänzt fehlende Kern-Datei" 0 "$rc"
rc=0; [ -x "$d/.claude/hooks/verify.sh" ] || rc=1
check "--update macht Hooks wieder ausführbar" 0 "$rc"
rc=0; [ -x "$d/.githooks/pre-push" ] || rc=1
check "--update macht auch pre-push ausführbar" 0 "$rc"
rc=0; grep -qx "eigener Inhalt" "$d/CLAUDE.md" || rc=1
check "--update lässt PROJEKT-Datei unangetastet" 0 "$rc"
bash "$ROOT/setup.sh" --diff "$d" >/dev/null 2>&1; rc=$?
check "nach --update ist der Kern wieder deckungsgleich" 0 "$rc"

# Versionierung: setup.sh stempelt die ausgelieferte Template-Version ins
# Ziel; --diff meldet beide Versionen, wertet den Stempel aber nicht als
# Verfalls-Kriterium (die Wahrheit bleibt der Datei-Vergleich).
rc=0; grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' "$ROOT/VERSION" || rc=1
check "VERSION ist SemVer" 0 "$rc"
rc=0; grep -qF "$(cat "$ROOT/VERSION")" "$ROOT/CHANGELOG.md" || rc=1
check "CHANGELOG hat einen Eintrag zur aktuellen VERSION" 0 "$rc"

d="$TMP/sync-version"; mkdir -p "$d"
run_setup "$d"
rc=0; [ "$(cat "$d/.claude/TEMPLATE_VERSION" 2>/dev/null)" = "$(cat "$ROOT/VERSION")" ] || rc=1
check "Kopieren stempelt .claude/TEMPLATE_VERSION" 0 "$rc"
out="$(bash "$ROOT/setup.sh" --diff "$d" 2>&1)"; rc=$?
check "Versionsstempel ist für --diff kein Verfall (Exit 0)" 0 "$rc"
check_contains "--diff meldet Template- und Projekt-Version" "Version: Template" "$out"
rm -f "$d/.claude/TEMPLATE_VERSION"
out="$(bash "$ROOT/setup.sh" --diff "$d" 2>&1)"; rc=$?
check "fehlender Versionsstempel ist kein Verfall (Exit 0)" 0 "$rc"
check_contains "--diff benennt den fehlenden Stempel" "nie gestempelt" "$out"
bash "$ROOT/setup.sh" --update "$d" >/dev/null 2>&1
rc=0; [ "$(cat "$d/.claude/TEMPLATE_VERSION" 2>/dev/null)" = "$(cat "$ROOT/VERSION")" ] || rc=1
check "--update stempelt die Version nach" 0 "$rc"

# Verwaiste Kern-Dateien: die Gegenrichtung des Vergleichs. Eine Datei, die
# nur im Ziel liegt, wird gemeldet (sie könnte verdrahteter Alt-Code sein),
# zählt aber nicht als Verfall und wird nie gelöscht.
d="$TMP/sync-verwaist"; mkdir -p "$d"
run_setup "$d"
echo "alt" > "$d/.claude/hooks/altlast.sh"
out="$(bash "$ROOT/setup.sh" --diff "$d" 2>&1)"; rc=$?
check "verwaiste Kern-Datei ändert den --diff-Exit nicht" 0 "$rc"
check_contains "--diff meldet die verwaiste Datei" "altlast.sh" "$out"
printf '#!/usr/bin/env bash\nexit 0\n' > "$d/.claude/hooks/verify-project.sh"
out="$(bash "$ROOT/setup.sh" --diff "$d" 2>&1)"
check_absent "verify-project.sh (projekteigenes Gate) gilt nicht als verwaist" "verify-project.sh" "$out"
# ("Template nicht kennt" statt Dateiname: altlast.sh taucht im
# --update-Output auch in der Unverdrahtet-Warnung auf — die Assertion muss
# den Verwaisten-Report treffen, nicht die.)
out="$(bash "$ROOT/setup.sh" --update "$d" 2>&1)"
check_contains "--update meldet die verwaiste Datei ebenfalls" "Template nicht kennt" "$out"
rc=0; [ -e "$d/.claude/hooks/altlast.sh" ] || rc=1
check "verwaiste Datei wird nicht gelöscht" 0 "$rc"

# secret-scan.yml ist der stack-unabhängige gitleaks-Backstop und deshalb die
# eine KERN-Datei unter .github/: eine verbogene Kopie ist Verfall und wird
# von --update geheilt. ci.yml direkt daneben bleibt PROJEKT — die Gegenprobe
# stellt sicher, dass die Hebung nicht versehentlich das ganze Verzeichnis
# erfasst hat.
d="$TMP/sync-secretscan"; mkdir -p "$d"
printf '{}' > "$d/package.json"
run_setup "$d"
echo "# lokal verbogen" >> "$d/.github/workflows/secret-scan.yml"
echo "# eigene ci" > "$d/.github/workflows/ci.yml"
bash "$ROOT/setup.sh" --diff "$d" >/dev/null 2>&1; rc=$?
check "verbogene secret-scan.yml -> --diff meldet Kern-Verfall" 1 "$rc"
bash "$ROOT/setup.sh" --update "$d" >/dev/null 2>&1
rc=0; cmp -s "$ROOT/.github/workflows/secret-scan.yml" "$d/.github/workflows/secret-scan.yml" || rc=1
check "--update stellt secret-scan.yml wieder her" 0 "$rc"
rc=0; grep -q "eigene ci" "$d/.github/workflows/ci.yml" || rc=1
check "--update lässt ci.yml (PROJEKT) unangetastet" 0 "$rc"

# Ein neu kopierter Hook, den settings.json nicht aufruft, tut nichts — das
# Projekt sieht aber geschützt aus. --update muss das melden.
d="$TMP/sync-hook-unverdrahtet"; mkdir -p "$d"
run_setup "$d"
python3 - "$d/.claude/settings.json" <<'PY' 2>/dev/null || sed -i.bak 's/protect-secrets\.sh/entfernt.sh/' "$d/.claude/settings.json"
import json, sys
p = sys.argv[1]
s = json.load(open(p))
s["hooks"]["PreToolUse"] = [h for h in s["hooks"]["PreToolUse"]
                            if "protect-secrets.sh" not in json.dumps(h)]
json.dump(s, open(p, "w"), indent=2)
PY
out="$(bash "$ROOT/setup.sh" --update "$d" 2>&1)"
check_contains "--update warnt vor nicht verdrahtetem Hook" "protect-secrets.sh" "$out"
check_contains "--update nennt settings.json als Ursache" "settings.json" "$out"

# .githooks/pre-commit wird kopiert, läuft aber nur bei gesetztem core.hooksPath.
# Ohne das fehlt Schicht 2 der Defense-in-Depth still.
d="$TMP/sync-hookspath"; mkdir -p "$d"; git_t init -q "$d" 2>/dev/null || git -C "$d" init -q
run_setup "$d"
git -C "$d" config --unset core.hooksPath 2>/dev/null || true
out="$(bash "$ROOT/setup.sh" --diff "$d" 2>&1)"; rc=$?
check "--diff meldet inaktiven pre-commit-Hook (Exit 1)" 1 "$rc"
check_contains "--diff nennt core.hooksPath" "core.hooksPath" "$out"

bash "$ROOT/setup.sh" --update "$d" >/dev/null 2>&1
rc=0; [ "$(git -C "$d" config --get core.hooksPath)" = ".githooks" ] || rc=1
check "--update aktiviert core.hooksPath" 0 "$rc"

# Eine eigene Hook-Verdrahtung des Projekts ist eine bewusste Entscheidung und
# darf nicht überschrieben werden.
git -C "$d" config core.hooksPath .myhooks
out="$(bash "$ROOT/setup.sh" --update "$d" 2>&1)"
rc=0; [ "$(git -C "$d" config --get core.hooksPath)" = ".myhooks" ] || rc=1
check "--update überschreibt eigene hooksPath-Wahl nicht" 0 "$rc"
check_contains "--update meldet die abweichende hooksPath" ".myhooks" "$out"

# Dasselbe im Kopier-Modus: der setzte core.hooksPath früher hart und legte
# damit z. B. eine bestehende .husky-Verdrahtung still.
d="$(mkfix copy-hookspath)"
git -C "$d" config core.hooksPath .myhooks
out="$(bash "$ROOT/setup.sh" "$d" 2>&1)"
rc=0; [ "$(git -C "$d" config --get core.hooksPath)" = ".myhooks" ] || rc=1
check "Kopier-Modus überschreibt eigene hooksPath-Wahl nicht" 0 "$rc"
check_contains "Kopier-Modus meldet die abweichende hooksPath" ".myhooks" "$out"

# --- setup.sh: --doctor --------------------------------------------------------------
# Der Doctor beantwortet "ist dieses Projekt wirklich geschützt?" in einem
# Lauf. Exit 1, sobald eine Schicht fehlt; jede Meldung trägt den
# Behebungsbefehl. Er verändert nichts.
echo "== setup.sh: --doctor =="

# Frisch kopiertes Ziel ohne Git-Repo, mit Platzhalter-CLAUDE.md, ohne
# Lint-Gate: mehrere Befunde auf einmal.
d="$TMP/doc-kaputt"; mkdir -p "$d"
run_setup "$d"
out="$(bash "$ROOT/setup.sh" --doctor "$d" 2>&1)"; rc=$?
check "--doctor meldet fehlende Schichten mit Exit 1" 1 "$rc"
check_contains "--doctor findet die Platzhalter-CLAUDE.md" "Platzhalter" "$out"
check_contains "--doctor findet das fehlende Git-Repo" "Git-Repo" "$out"
check_contains "--doctor findet das fehlende Lint-Gate" "Lint-Gate" "$out"
check_contains "--doctor nennt Behebungsbefehle" "->" "$out"

# Entdrahteter Hook: liegt in .claude/hooks/, wird von settings.json aber
# nicht aufgerufen — der gefährlichste Zustand, der Doctor muss ihn nennen.
python3 - "$d/.claude/settings.json" <<'PY' 2>/dev/null || sed -i.bak 's/protect-secrets\.sh/entfernt.sh/' "$d/.claude/settings.json"
import json, sys
p = sys.argv[1]
s = json.load(open(p))
s["hooks"]["PreToolUse"] = [h for h in s["hooks"]["PreToolUse"]
                            if "protect-secrets.sh" not in json.dumps(h)]
json.dump(s, open(p, "w"), indent=2)
PY
out="$(bash "$ROOT/setup.sh" --doctor "$d" 2>&1)"
check_contains "--doctor findet den entdrahteten Hook" "protect-secrets.sh" "$out"

# Ohne Ausführungsbit auf setup.sh (ZIP-Download, Aufruf per `bash setup.sh`)
# scheiterte der interne --diff-Aufruf an "$0" und der Doctor meldete einen
# Kern-Verfall, den es nicht gab.
TPL_NOX="$TMP/tpl-noexec"; mkdir -p "$TPL_NOX"
cp -R "$ROOT/." "$TPL_NOX/"
chmod -x "$TPL_NOX/setup.sh"
d="$(mkfix doc-noexec)"
bash "$TPL_NOX/setup.sh" "$d" >/dev/null 2>&1 || true
out="$(bash "$TPL_NOX/setup.sh" --doctor "$d" 2>&1)"
check_contains "--doctor ohne Ausführungsbit: Kern korrekt deckungsgleich" \
  "Werkzeug-Kern deckungsgleich" "$out"

# Gesundes Projekt: alle sieben Schichten aktiv -> Exit 0. (Braucht gitleaks
# auf dem Host — Schicht 1 ist sonst zu Recht rot.)
if command -v gitleaks >/dev/null 2>&1; then
  d="$(mkfix doc-gesund)"
  printf '{"scripts":{"lint":"exit 0"}}' > "$d/package.json"
  run_setup "$d"
  echo "Projektkontext, vollständig ausgefüllt." > "$d/CLAUDE.md"
  out="$(bash "$ROOT/setup.sh" --doctor "$d" 2>&1)"; rc=$?
  check "--doctor auf gesundem Projekt -> Exit 0" 0 "$rc"
  check_contains "--doctor meldet alle Schichten aktiv" "alle Schichten aktiv" "$out"
else
  skip "gitleaks nicht installiert — Doctor-Gesund-Test übersprungen (CI führt ihn aus)."
fi

# --- setup-github.sh: --dry-run ------------------------------------------------------
# Das Skript schaltet serverseitig (Dependabot, Secret scanning, Push protection,
# Rulesets) — alles unsichtbar, bis es passiert ist. --dry-run soll denselben
# Entscheidungsweg nehmen, aber keinen schreibenden Aufruf absetzen.
echo "== setup-github.sh: --dry-run =="
SGH="$ROOT/setup-github.sh"

# gh-Stub: bedient lesende Aufrufe und protokolliert jeden schreibenden in eine
# Datei. Die Datei ist der Beweis, nicht die Stub-Ausgabe — jeder gh-Aufruf in
# setup-github.sh schickt sein stderr nach /dev/null, eine Meldung des Stubs
# käme dort also nie an und die Assertion wäre immer grün.
GH_BIN="$TMP/gh-bin"; mkdir -p "$GH_BIN"
for t in bash git python3 grep sed cat printf basename dirname mktemp; do
  p="$(command -v "$t" 2>/dev/null || true)"
  [ -n "$p" ] && ln -sf "$p" "$GH_BIN/$t"
done
cat > "$GH_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in
    PUT|POST|PATCH|DELETE)
      echo "schreibender Aufruf: gh $*" >> "$GH_WRITE_LOG"
      exit 66 ;;
  esac
done
case "${1:-} ${2:-}" in
  "repo view") echo "MichiBl/dry-run-fixture" ;;
  *) ;;   # rulesets-Abfrage u. a.: leere Antwort = nichts vorhanden
esac
GHSTUB
chmod +x "$GH_BIN/gh"

d="$(mkfix dryrun)"
run_setup "$d"
GH_WRITE_LOG="$TMP/gh-writes.txt"; : > "$GH_WRITE_LOG"
rc=0
out="$(env PATH="$GH_BIN:$PATH" GH_WRITE_LOG="$GH_WRITE_LOG" \
        bash "$SGH" "$d" --dry-run 2>&1)" || rc=$?
check "--dry-run laeuft durch, ohne zu schreiben" 0 "$rc"
check_contains "--dry-run kuendigt Dependabot an"      "würde Dependabot alerts" "$out"
check_contains "--dry-run kuendigt Push protection an" "würde Secret scanning"   "$out"
check_contains "--dry-run kuendigt den Ruleset-Import an" "würde Ruleset importieren" "$out"
check_contains "--dry-run sagt, dass nichts geaendert wurde" "nichts geändert" "$out"
check_absent  "--dry-run behauptet nirgends 'aktiviert'" "✓  Dependabot alerts aktiviert" "$out"
rc=0; [ ! -s "$GH_WRITE_LOG" ] || rc=1
check "kein schreibender gh-Aufruf abgesetzt" 0 "$rc"
[ ! -s "$GH_WRITE_LOG" ] || sed 's/^/      /' "$GH_WRITE_LOG"

# Gegenprobe, dass der Stub ueberhaupt anschlaegt: derselbe Lauf OHNE --dry-run
# muss schreibende Aufrufe produzieren. Ohne diese Kontrolle waere die
# Assertion oben auch dann gruen, wenn der Stub gar nicht greift.
: > "$GH_WRITE_LOG"
env PATH="$GH_BIN:$PATH" GH_WRITE_LOG="$GH_WRITE_LOG" \
  bash "$SGH" "$d" >/dev/null 2>&1 || true
rc=0; [ -s "$GH_WRITE_LOG" ] || rc=1
check "ohne --dry-run schlaegt der Stub an (Kontrolle)" 0 "$rc"

# Die Voraussetzungspruefung darf --dry-run nicht durchwinken: ohne gh ist auch
# der Probelauf wertlos, weil er den Entscheidungsweg nicht nachvollziehen kann.
rc=0
env -i PATH="$NOPY_BIN" bash "$SGH" "$d" --dry-run >/dev/null 2>&1 || rc=$?
check "--dry-run ohne gh bricht weiterhin ab" 1 "$rc"

# --- .github/workflows: Action-Pins --------------------------------------------------
# Dependabot parst *.yml.example NICHT. Es hebt deshalb nur die beiden aktiven
# Workflows und lässt die CI-Vorlagen auf dem alten SHA stehen — genau so ist
# hier ein checkout-Pin zweier Versionen entstanden, mit falschem Kommentar.
# Diese Assertion macht den nächsten solchen Dependabot-PR rot, bis die
# Vorlagen nachgezogen sind.
echo "== .github/workflows: Action-Pins =="

pins="$(grep -rhoE 'uses:[[:space:]]+[^@[:space:]]+@[0-9a-f]{40}' "$ROOT/.github/workflows" \
  | sed 's/^uses:[[:space:]]*//' | sort -u)"

rc=0; [ -n "$pins" ] || rc=1
check "Action-Pins gefunden (Full-SHA, kein Tag)" 0 "$rc"

split="$(printf '%s\n' "$pins" | sed 's/@.*//' | uniq -d)"
rc=0; [ -z "$split" ] || rc=1
check "gleiche Action überall derselbe SHA" 0 "$rc"
[ -z "$split" ] || printf '      uneinheitlich gepinnt: %s\n' "$split"

# Der Versionskommentar ist die einzige menschenlesbare Audit-Fläche eines
# SHA-Pins. Fehlt er, ist der Pin nur noch eine Hex-Zeichenkette. Geprüft wird
# nur, DASS er da ist — ob die genannte Version zum SHA gehört, ließe sich nur
# gegen die GitHub-API klären, und der Selbsttest bleibt bewusst offline.
rc=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  n_uses="$(grep -cE '^[[:space:]]*uses:[[:space:]]+[^@[:space:]]+@[0-9a-f]{40}' "$f")"
  # Kommentarzeile direkt über jedem uses: (grep -B1 liefert sie mit).
  n_comment="$(grep -B1 -E '^[[:space:]]*uses:[[:space:]]+[^@[:space:]]+@[0-9a-f]{40}' "$f" \
    | grep -cE '^[[:space:]]*#[[:space:]]*[^[:space:]]+[[:space:]]+v[0-9]')"
  [ "$n_uses" -eq "$n_comment" ] || rc=1
done <<EOF
$(find "$ROOT/.github/workflows" -type f \( -name '*.yml' -o -name '*.yml.example' \))
EOF
check "jeder Pin trägt einen Versionskommentar" 0 "$rc"

# --- Secret-Dateitypen: drei Schichten, eine Aufzählung ----------------------------
# deny-Regeln (settings.json), protect-secrets.sh und .gitignore sind drei
# unabhängig gepflegte Listen derselben Muster. Wird ein Muster nur in einer
# ergänzt, fehlt es in den anderen still — genau so sind id_rsa & Co. anfangs
# nur im Hook gelandet. Der Abgleich läuft über eine Kanon-Liste.
echo "== Secret-Muster in allen drei Schichten =="
rc=0
for needle in .env .pem .key .p12 .pfx id_rsa id_ed25519 credentials service-account .npmrc .pypirc .netrc; do
  for f in .claude/settings.json .claude/hooks/protect-secrets.sh .gitignore; do
    if ! grep -qF -- "$needle" "$ROOT/$f"; then
      echo "      ✗ '$needle' fehlt in $f"; rc=1
    fi
  done
done
check "jedes Secret-Muster in deny + protect-secrets + .gitignore" 0 "$rc"

# Die Read-Sperre kann .env.* nicht pauschal sperren (.env.example muss lesbar
# bleiben, deny kennt keine Ausnahme) und ist deshalb eine Aufzählung. Die
# gängigen Kurznamen fehlten darin: .env.prod war lesbar, .env.production nicht.
rc=0
for v in prod dev stage preview backup bak; do
  grep -qF "Read(./**/.env.$v)" "$ROOT/.claude/settings.json" || { echo "      ✗ .env.$v fehlt in den deny-Regeln"; rc=1; }
done
check "deny-Regeln decken die gängigen .env-Kurznamen" 0 "$rc"

# --- gitleaks-Binary-Pin (Version + SHA-256) ---------------------------------------
# Der im Workflow gepinnte Hash ist die einzige Schicht, die ein
# kompromittiertes Release erkennt — die checksums.txt des Releases käme aus
# derselben Quelle wie das Binary. Laufen die Pins der beiden Workflows
# auseinander, testet der Selbsttest zudem eine andere gitleaks-Version als
# das harte Gate.
echo "== gitleaks-Binary-Pin =="
WF1="$ROOT/.github/workflows/secret-scan.yml"
WF2="$ROOT/.github/workflows/hook-selftest.yml"
rc=0
for var in GITLEAKS_VERSION GITLEAKS_SHA256; do
  n="$(grep -h "${var}:" "$WF1" "$WF2" | grep -c .)"
  u="$(grep -h "${var}:" "$WF1" "$WF2" | sed 's/.*"\([^"]*\)".*/\1/' | sort -u | grep -c .)"
  { [ "$n" -eq 2 ] && [ "$u" -eq 1 ]; } || { echo "      ✗ $var: $n Vorkommen, $u verschiedene Werte (soll: 2/1)"; rc=1; }
done
check "gitleaks-Pin (Version + SHA) in beiden Workflows identisch" 0 "$rc"

sha="$(grep -h 'GITLEAKS_SHA256:' "$WF1" | sed 's/.*"\([^"]*\)".*/\1/')"
rc=0; printf '%s' "$sha" | grep -Eq '^[0-9a-f]{64}$' || rc=1
check "GITLEAKS_SHA256 ist ein voller SHA-256" 0 "$rc"

# detect-secrets (in Zielprojekten oft per pre-commit) meldet den Hash als
# "Hex High Entropy String" und färbt deren CI rot. Ein Baseline-Eintrag
# hilft nicht: er speichert einen SHA-1, den gitleaks als generic-api-key
# meldet. Das Inline-Pragma ist der einzige Weg ohne Scanner-Konflikt.
rc=0; grep -q 'GITLEAKS_SHA256: ".*" *# pragma: allowlist secret' "$WF1" || rc=1
check "GITLEAKS_SHA256 in secret-scan.yml trägt das detect-secrets-Pragma" 0 "$rc"

# Auf PRs muss das harte Gate die Allowlist des Base-Branches nutzen. Mit der
# des PRs konnte ein PR sein eigenes Secret per .gitleaks.toml freigeben.
rc=0
grep -q 'BASE_REF: ${{ github.base_ref }}' "$WF1" || rc=1
grep -q 'git show "origin/${BASE_REF}:.gitleaks.toml"' "$WF1" || rc=1
check "secret-scan.yml nutzt auf PRs die .gitleaks.toml des Base-Branches" 0 "$rc"

# Drei weitere Wege an derselben Sperre vorbei, alle im selben Step:
# gitleaks:allow-Kommentare, die .gitleaksignore des PRs, und — hat die Basis
# keine .gitleaks.toml — die des PRs, die gitleaks ohne --config selbst lädt.
rc=0
grep -q -- '--ignore-gitleaks-allow' "$WF1" || rc=1
grep -q 'git show "origin/${BASE_REF}:.gitleaksignore"' "$WF1" || rc=1
grep -q 'useDefault = true' "$WF1" || rc=1
check "secret-scan.yml: kein Freigeben per gitleaks:allow, .gitleaksignore oder PR-Config" 0 "$rc"

# core-drift führt setup.sh aus einem fremden Repo aus. Ein in .git/config
# abgelegter GITHUB_TOKEN wäre für diesen Code lesbar.
rc=0
grep -q 'persist-credentials: false' "$ROOT/.github/workflows/core-drift.yml.example" || rc=1
check "core-drift.yml.example legt keinen Token in .git/config ab" 0 "$rc"

# Node 20 ist seit 2026-04-30 End-of-Life und bekommt keine Security-Releases
# mehr — ein Zielprojekt hätte mit der Vorlage dauerhaft offene Lücken gebaut.
# Die Schwelle 22 altert mit (EOL 2027-04) und muss dann mit der Vorlage
# steigen. check-latest, weil ein Security-Patch Tage vor dem nächsten
# Runner-Image im setup-node-Manifest liegt; ohne das Flag baut der Job still
# mit dem alten Patch-Stand aus dem Toolcache weiter.
WFN="$ROOT/.github/workflows/ci-node.yml.example"
nv="$(sed -n 's/^[[:space:]]*node-version:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$WFN" | head -1)"
rc=0; { [ -n "$nv" ] && [ "$nv" -ge 22 ]; } || rc=1
check "ci-node.yml.example: Node-Linie ist nicht End-of-Life (>= 22, ist: ${nv:-?})" 0 "$rc"
rc=0; grep -q '^[[:space:]]*check-latest: true' "$WFN" || rc=1
check "ci-node.yml.example: setup-node zieht den neuesten Patch (check-latest)" 0 "$rc"

# --- .github/dependabot.yml: cooldown ----------------------------------------------
# Ein kompromittiertes Release hat am Erscheinungstag noch keinen CVE-Eintrag:
# das Audit schweigt, die CI ist grün, und Dependabot macht brav einen PR darauf.
# `cooldown` ist die einzige Schicht, die diesen Fall abdeckt. Die Assertion hält
# ihn in der Vorlage fest, die jedes neue Projekt erbt — auch in den
# auskommentierten npm/pip-Blöcken, die beim Aktivieren sonst ohne Wartezeit
# starten. Sie prüft nur die Anwesenheit; die Zahl der Tage ist Projektsache.
echo "== .github/dependabot.yml: cooldown =="

dbot="$ROOT/.github/dependabot.yml"
n_eco="$(grep -cE '^[[:space:]]*#?[[:space:]]*- package-ecosystem:' "$dbot")"
n_cool="$(grep -cE '^[[:space:]]*#?[[:space:]]*cooldown:' "$dbot")"
rc=0; { [ "$n_eco" -gt 0 ] && [ "$n_eco" -eq "$n_cool" ]; } || rc=1
check "jeder package-ecosystem-Block hat cooldown" 0 "$rc"
[ "$rc" -eq 0 ] || printf '      %s Ökosystem-Blöcke, aber %s cooldown\n' "$n_eco" "$n_cool"

# --- template-pin-check.yml: Cooldown ----------------------------------------------
# Die Vorlagen-Pins sieht Dependabot nicht; der Pin-Check ist ihr Ersatz und
# muss denselben Cooldown einhalten — sonst drängt er dazu, ein Release am Tag
# seiner Veröffentlichung zu pinnen. Getestet wird der echte run:-Block aus
# dem YAML gegen einen gh-Stub, keine Kopie der Logik.
echo "== template-pin-check.yml: Cooldown =="
PCW="$ROOT/.github/workflows/template-pin-check.yml"

pc_days="$(sed -n 's/^[[:space:]]*COOLDOWN_DAYS:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$PCW")"
dbot_days="$(sed -n 's/^[[:space:]]*default-days:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$dbot" | head -1)"
rc=0; { [ -n "$pc_days" ] && [ "$pc_days" = "$dbot_days" ]; } || rc=1
check "Pin-Check-Cooldown = dependabot.yml (${pc_days:-?} / ${dbot_days:-?} Tage)" 0 "$rc"

# run:-Block ausschneiden und um seine Einrückung kürzen — so, wie Actions
# ihn an bash übergibt. Er endet an der ersten weniger eingerückten Zeile.
PC_SCRIPT="$TMP/pin-check.sh"
in_block=0; ind=""
while IFS= read -r line; do
  if [ "$in_block" -eq 0 ]; then
    case "$line" in *"run: |"*) in_block=1 ;; esac
    continue
  fi
  [ -n "$ind" ] || [ -z "$line" ] || ind="${line%%[! ]*}"
  case "$line" in
    "") echo ;;
    "$ind"*) echo "${line#"$ind"}" ;;
    *) break ;;
  esac
done < "$PCW" > "$PC_SCRIPT"

h40() { local s="$1$1$1$1$1$1$1$1$1$1"; printf '%s' "$s$s$s$s"; }

# Drei Actions, drei Fälle (veröffentlicht: 1 = uralt, FRESH = vor 1,5 Tagen):
#   fresh  — gepinnt v1.0.0, v1.1.0 im Cooldown          -> nichts fällig
#   behind — gepinnt v1.0.0, v1.1.0 alt, v1.2.0 frisch,
#            dazu ein später veröffentlichter Backport v0.9.1 -> v1.1.0 fällig
#   early  — gepinnt v1.1.0 (frisch), vorgezogen          -> kein Rückstand
pcd="$TMP/pincheck"; mkdir -p "$pcd/.github/workflows"
cat > "$pcd/.github/workflows/pins.yml.example" <<EOF
      # acme/fresh v1.0.0
      - uses: acme/fresh@$(h40 1)
      # acme/behind v1.0.0
      - uses: acme/behind@$(h40 3)
      # acme/early v1.1.0
      - uses: acme/early@$(h40 7)
EOF

# Der Stub ersetzt GitHub, nicht gojq: er antwortet so, wie `gh api --jq`
# NACH dem Filter ausgibt. Der Issue-Body landet in einer Datei — er ist der
# Befund, den ein Mensch zu sehen bekommt. FRESH liegt 1,5 Tage zurück, nicht
# genau einen: das Skript liest die Uhr vor dem Stub, ein Sekundensprung
# dazwischen ergäbe sonst "Tag 0".
PC_BIN="$TMP/pincheck-bin"; mkdir -p "$PC_BIN"
cat > "$PC_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
h40() { local s="$1$1$1$1$1$1$1$1$1$1"; printf '%s' "$s$s$s$s"; }
FRESH=$(( $(date +%s) - 129600 ))
case "$1 ${2:-}" in
  "api repos/acme/fresh/releases?per_page=100")  printf '%s\n' "1 v1.0.0" "$FRESH v1.1.0" ;;
  "api repos/acme/behind/releases?per_page=100") printf '%s\n' "2 v1.1.0" "$FRESH v1.2.0" "3 v0.9.1" "1 v1.0.0" ;;
  "api repos/acme/early/releases?per_page=100")  printf '%s\n' "1 v1.0.0" "$FRESH v1.1.0" ;;
  "api repos/acme/fresh/commits/v1.0.0")  h40 1 ;;
  "api repos/acme/behind/commits/v1.1.0") h40 4 ;;
  "api repos/acme/early/commits/v1.0.0")  h40 6 ;;
  "api repos/acme/early/compare/$(h40 6)...$(h40 7)") echo ahead ;;
  "api repos/acme/"*"/compare/"*) echo behind ;;
  "issue create"|"issue edit") cat > "$PC_BODY" ;;
  *) ;;   # issue list: kein offenes Issue; label create: still
esac
GHSTUB
chmod +x "$PC_BIN/gh"

PC_BODY="$TMP/pincheck-body.md"; PC_SUM="$TMP/pincheck-summary.md"
: > "$PC_BODY"; : > "$PC_SUM"
# Der Workflow läuft nur auf ubuntu-Runnern und darf GNU-`sort -V` nutzen. Ein
# sort ohne Versionssortierung (ältere macOS) ist kein Defekt des Workflows.
if printf '%s\n' "x v1.9.0" "x v1.10.0" | sort -t ' ' -k2,2Vr 2>/dev/null \
     | head -n1 | grep -qx 'x v1.10.0'; then
  rc=0
  if [ -s "$PC_SCRIPT" ]; then
    (cd "$pcd" && env PATH="$PC_BIN:$PATH" PC_BODY="$PC_BODY" GITHUB_STEP_SUMMARY="$PC_SUM" \
       ISSUE_TITLE="Pin-Check-Fixture" COOLDOWN_DAYS="${pc_days:-7}" \
       bash "$PC_SCRIPT") >/dev/null 2>&1 || rc=$?
  else
    rc=1
  fi
  check "Pin-Check: run:-Block läuft gegen den gh-Stub durch" 0 "$rc"
  body="$(cat "$PC_BODY")"; summary="$(cat "$PC_SUM")"
  check_contains "Pin-Check: Rückstand nennt das höchste Release jenseits des Cooldowns, nicht den Backport" \
    "\`acme/behind\` — gepinnt **v1.0.0** (\`$(h40 3)\`), faellig **v1.1.0**" "$body"
  check_contains "Pin-Check: das frischere Release steht als Cooldown dabei" \
    "v1.2.0 (Tag 1 von ${pc_days:-7}) noch im Cooldown" "$body"
  check_absent "Pin-Check: frisches Release ist noch nicht fällig" "acme/fresh" "$body"
  check_absent "Pin-Check: bewusst vorgezogener Pin ist kein Rückstand" "acme/early" "$body"
  check_contains "Pin-Check: Cooldown bleibt in der Step-Summary sichtbar" "\`acme/fresh\`: v1.1.0 (Tag 1" "$summary"
else
  skip "sort ohne -V — Pin-Check-Verhaltenstest übersprungen (CI führt ihn aus)."
fi

# Die Issue-Suche lief nur über den Titel: in einem öffentlichen Repo kann
# jeder ein Issue mit diesem Titel öffnen, das der Workflow dann überschreibt
# oder schließt. Den jq-Filter wertet gh selbst aus — der Stub kann ihn nicht
# nachbilden, deshalb nur die Anwesenheit.
rc=0; grep -q 'select(.author.is_bot)' "$PCW" || rc=1
check "Pin-Check: fasst nur von einem Bot angelegte Issues an" 0 "$rc"

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
# Diff-Basis ist der erkannte Default-Branch, kein hartes `main` — sonst
# reviewen die Agenten in master-/develop-Repos den falschen Diff.
marker .claude/agents/code-reviewer.md "symbolic-ref"
marker .claude/agents/qa-engineer.md "symbolic-ref"
marker .claude/agents/code-reviewer.md "Verantwortlichkeits-Schnitt (SRP)"
marker .claude/agents/code-reviewer.md "Harte Grenzen"
marker .claude/agents/code-reviewer.md "Reuse Check"
marker .claude/agents/solution-architect.md "Reused Utilities"
marker .claude/agents/solution-architect.md "Eine Datei, eine Kernverantwortung"
marker .claude/agents/requirements-engineer.md "Acceptance Criteria"
marker .claude/agents/qa-engineer.md "qa-plan.md"
marker .claude/agents/qa-engineer.md "Manuelle Verifikation (MC)"
marker .claude/agents/qa-engineer.md "Warum manuell"
marker .claude/skills/feature/SKILL.md "GATE 1"
# Konvergenz-Bremse: ohne das Limit kreist die Pipeline bei einem Review,
# das nicht konvergiert, unbegrenzt zwischen Fix und Re-Review.
marker .claude/skills/feature/SKILL.md "Maximal 3 Review-Zyklen"
marker .claude/skills/feature/SKILL.md "GATE 2"
marker .claude/skills/feature/SKILL.md "Selbst prüfen, bevor der PR aus dem Draft geht"
marker templates/CLAUDE.md "eine Kernverantwortung"
# Test-first-Ordnung der Pipeline: geht die RED-Phase verloren, schreibt die
# QA wieder Tests NACH der Implementierung — Tests, die nie rot waren und
# deshalb nicht belegen, dass sie das neue Verhalten prüfen.
marker .claude/agents/qa-engineer.md "RED-Phase"
marker .claude/agents/qa-engineer.md "GREEN-Phase"
marker .claude/skills/feature/SKILL.md "RED-Phase"
marker templates/CLAUDE.md "zuerst, RED"
# Roadmap-Verdrahtung: fehlt sie, formuliert die Pipeline die AK aus
# docs/requirements-status.md frei neu (ein AK verschwindet unbemerkt), und
# der Punkt bleibt nach dem Merge offen.
marker .claude/skills/feature/SKILL.md "## Roadmap-Bezug"
marker .claude/skills/feature/SKILL.md "Roadmap abhaken"
marker .claude/agents/requirements-engineer.md "## Roadmap-Bezug"
# Specs sind Planungsstände: ohne den Vermerk hält eine spätere Session eine
# veraltete Spec für das aktuelle Verhalten — gefährlicher als gar keine.
marker .claude/agents/requirements-engineer.md "> Planungsstand vom"
marker .claude/agents/solution-architect.md "> Planungsstand vom"
# /fix ändert Verhalten, das Specs beschreiben. Ohne Nachtrag fehlt in der
# Spec jeder Hinweis, dass sie an dieser Stelle nicht mehr stimmt.
marker .claude/skills/fix/SKILL.md "## Nachträge"

# --- Ergebnis --------------------------------------------------------------------
echo
echo "Ergebnis: $PASS bestanden, $FAIL fehlgeschlagen, $SKIP übersprungen."
[ "$FAIL" -eq 0 ] || exit 1
exit 0
