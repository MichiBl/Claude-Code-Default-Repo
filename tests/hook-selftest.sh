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

# --- Ergebnis --------------------------------------------------------------------
echo
echo "Ergebnis: $PASS bestanden, $FAIL fehlgeschlagen, $SKIP übersprungen."
[ "$FAIL" -eq 0 ] || exit 1
exit 0
