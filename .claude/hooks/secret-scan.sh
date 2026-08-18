#!/usr/bin/env bash
#
# secret-scan.sh — generischer PreToolUse-Hook (matcher "Bash"), der Secrets
# blockt, BEVOR sie via `git commit` / `git push` in die Historie gelangen.
#
# Mechanik: erkennt selbst, ob der auszuführende Befehl ein commit/push ist
# (alles andere wird sofort durchgewunken), und scannt dann mit gitleaks:
#   * commit -> die gestagten Änderungen (gitleaks git --staged)
#   * push   -> die Commits, die der Remote noch nicht hat
#
# Exit-Code-Vertrag (PreToolUse):
#   0 -> Tool-Call erlauben
#   2 -> Tool-Call blockieren; stderr geht als Begründung an Claude zurück
#
# Schutzmechanismen:
#   (a) kein git commit/push im Befehl -> exit 0
#   (b) gitleaks nicht installiert    -> exit 0 mit Hinweis (CI ist Backstop)
#
# Bekannte Lücken (Best-Effort, die Backstops tragen): git-Aliasse (`git ci`),
# Commits aus Skripten/eval heraus, und der Push-Zweig scannt upstream..HEAD —
# `git push origin <anderer-branch>` trifft also den falschen Bereich.
#
# Ein Secret, das im Remote landet, gilt als kompromittiert — rotieren,
# nicht nur den Commit entfernen.

set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" || exit 0

# --- PreToolUse-Payload lesen; Bash-Befehl extrahieren ------------------------
STDIN_JSON="$(cat 2>/dev/null || true)"

# Interpreter suchen statt python3 vorauszusetzen: fehlte er, blieb CMD leer,
# die commit/push-Erkennung unten matchte nie und der Scan wurde still
# übersprungen — der Hook lag da und tat nichts, ohne es zu sagen.
PY=""
for c in python3 python; do
  if command -v "$c" >/dev/null 2>&1; then PY="$c"; break; fi
done

if [ -n "$PY" ]; then
  CMD="$(printf '%s' "$STDIN_JSON" | "$PY" -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print(""); sys.exit(0)
ti = d.get("tool_input") or {}
print(ti.get("command", "") if isinstance(ti, dict) else "")
' 2>/dev/null || true)"
else
  # Fallback ohne Interpreter: gar nicht dekodieren. Für die Erkennung unten
  # genügt die Roh-Payload — sie enthält den Befehl als Teilstring. Das
  # triggert eher zu oft (ein "git commit" in einem anderen Feld), und einmal
  # zu viel scannen ist die sichere Richtung; ein leeres CMD würde dagegen
  # jeden Scan überspringen.
  CMD="$STDIN_JSON"
  {
    echo "⚠  secret-scan: kein python3/python gefunden — commit/push-Erkennung"
    echo "   läuft auf der Roh-Payload statt auf dem dekodierten Befehl."
    echo "   Backstops bleiben .githooks/pre-commit und die CI (gitleaks)."
  } >&2
fi

# (a) Nur bei git commit / git push aktiv werden.
if ! printf '%s' "$CMD" | grep -Eq 'git[[:space:]]+([^|;&]*[[:space:]])?(commit|push)'; then
  exit 0
fi

# (b) Toolchain vorhanden?
if ! command -v gitleaks >/dev/null 2>&1; then
  echo "secret-scan: gitleaks nicht installiert — Scan übersprungen (brew install gitleaks). CI erzwingt ihn trotzdem." >&2
  exit 0
fi

# Projekt-Config nutzen, falls vorhanden (sonst gitleaks-Defaults).
# (Kein leeres Array: macOS-Bash 3.2 + set -u vertragen keine leere
# Array-Expansion.)
CONFIG_OPT=""
[ -f .gitleaks.toml ] && CONFIG_OPT="--config=.gitleaks.toml"

# --- Scan ----------------------------------------------------------------------
STATUS=0
RESULT=""

# Erst auf commit prüfen, dann auf push. Andersherum gewann "push" jeden
# Befehl, der das Wort irgendwo enthält — `git commit -m "erklaere git push"`
# landete im Push-Zweig, der die gestagten Änderungen gar nicht ansieht, und
# ein gestagtes Secret kam durch. Ein commit-mit-push (`git commit && git
# push`) gehört ebenfalls hierher: gescannt werden muss der neue Inhalt, und
# den sieht --staged.
if printf '%s' "$CMD" | grep -Eq 'git[[:space:]]+([^|;&]*[[:space:]])?commit'; then
  # Commit: gestagte Änderungen scannen.
  RESULT="$(gitleaks git --staged --no-banner --redact ${CONFIG_OPT:+"$CONFIG_OPT"} . 2>&1)" || STATUS=$?
else
  # Push: die Commits scannen, die upstream noch fehlen.
  RANGE=""
  if UPSTREAM="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"; then
    RANGE="${UPSTREAM}..HEAD"
  elif git rev-parse --verify origin/main >/dev/null 2>&1; then
    RANGE="origin/main..HEAD"
  fi
  if [ -n "$RANGE" ] && [ -n "$(git rev-list "$RANGE" 2>/dev/null | head -1)" ]; then
    RESULT="$(gitleaks git --no-banner --redact ${CONFIG_OPT:+"$CONFIG_OPT"} --log-opts "$RANGE" . 2>&1)" || STATUS=$?
  elif [ -z "$RANGE" ]; then
    # Kein Upstream und kein origin/main (typisch: allererster Push eines
    # frischen Repos) -> gesamte lokale Historie scannen statt gar nicht.
    RESULT="$(gitleaks git --no-banner --redact ${CONFIG_OPT:+"$CONFIG_OPT"} . 2>&1)" || STATUS=$?
  fi
fi

if [ "$STATUS" -ne 0 ]; then
  {
    echo "🔒 Secret-Scan blockiert diesen Befehl: potenzielle Secrets/Keys gefunden."
    echo
    printf '%s\n' "$RESULT" | tail -n 40
    echo
    echo "Optionen:"
    echo "  - Echtes Secret? Entfernen und über .env / Umgebungsvariable laden."
    echo "  - Bereits committet? Commit amenden/entfernen UND das Secret rotieren."
    echo "  - Falsch-positiv? Allowlist-Eintrag in .gitleaks.toml ergänzen."
  } >&2
  exit 2
fi

exit 0
