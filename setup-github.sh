#!/usr/bin/env bash
#
# setup-github.sh — aktiviert die serverseitigen GitHub-Schutzschalter für ein
# Zielprojekt, die nicht als Datei im Repo leben können:
#
#   * Dependabot alerts + automatische Security-Fixes
#   * Secret scanning + Push protection (bei privaten Repos ggf. nur mit
#     Advanced-Security-Add-on — wird dann übersprungen, nicht abgebrochen)
#   * Branch-Ruleset(s) aus .github/rulesets/*.json (Import, nie überschreiben)
#
# Verwendung:
#   ./setup-github.sh /pfad/zum/projekt [--check "<Status-Check-Name>"]...
#
#   --check fügt dem Ruleset zusätzliche Required Status Checks hinzu
#   (der gitleaks-Check ist in der Vorlage schon enthalten), z. B.:
#   ./setup-github.sh ../mein-projekt --check "lint • typecheck • test (uv)"
#
# Voraussetzungen: gh (GitHub CLI, eingeloggt via 'gh auth login'), git, python3.
# Das Skript ist idempotent: Vorhandene Rulesets gleichen Namens werden
# übersprungen (Konflikt wird gemeldet, Entscheidung bleibt beim Nutzer) —
# gleiches Prinzip wie setup.sh.
#
# Hinweis: Auf privaten Repos im Free-Plan speichert GitHub Rulesets, setzt
# sie aber NICHT durch (Enforcement erst mit Pro/Team oder public Repo).
# Der Import lohnt trotzdem — die Regeln greifen, sobald der Plan es hergibt.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TARGET="${1:-}"
if [ -z "$TARGET" ] || [ ! -d "$TARGET" ]; then
  echo "Verwendung: ./setup-github.sh /pfad/zum/projekt [--check \"<Name>\"]..." >&2
  exit 1
fi
shift
TARGET="$(cd "$TARGET" && pwd)"

EXTRA_CHECKS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --check)
      [ -n "${2:-}" ] || { echo "--check braucht ein Argument." >&2; exit 1; }
      EXTRA_CHECKS+=("$2")
      shift 2
      ;;
    *)
      echo "Unbekanntes Argument: $1" >&2
      exit 1
      ;;
  esac
done

for tool in gh git python3; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "✗ '$tool' fehlt — bitte installieren (gh: 'brew install gh' + 'gh auth login')." >&2
    exit 1
  }
done

REPO="$(cd "$TARGET" && gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
if [ -z "$REPO" ]; then
  echo "✗ Kein GitHub-Repo in $TARGET erkennbar (git remote fehlt oder gh nicht eingeloggt)." >&2
  exit 1
fi

echo "GitHub-Schutzschalter für $REPO"
echo

# --- Dependabot ------------------------------------------------------------
if gh api -X PUT "repos/$REPO/vulnerability-alerts" --silent 2>/dev/null; then
  echo "  ✓  Dependabot alerts aktiviert"
else
  echo "  ⚠  Dependabot alerts konnten nicht aktiviert werden (Rechte/Plan prüfen)"
fi
if gh api -X PUT "repos/$REPO/automated-security-fixes" --silent 2>/dev/null; then
  echo "  ✓  Dependabot security updates (Auto-Fix-PRs) aktiviert"
else
  echo "  ⚠  Dependabot security updates konnten nicht aktiviert werden"
fi

# --- Secret scanning + Push protection -------------------------------------
# Bei privaten Repos ohne Advanced Security lehnt die API das ab — das ist
# okay: gitleaks (Hook + CI) übernimmt diese Rolle dann allein.
if printf '%s' '{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}}' \
  | gh api -X PATCH "repos/$REPO" --input - --silent 2>/dev/null; then
  echo "  ✓  Secret scanning + Push protection aktiviert"
else
  echo "  ⚠  Secret scanning/Push protection nicht verfügbar (privates Repo ohne"
  echo "     Advanced Security?) — gitleaks-Hook und -CI decken das weiter ab."
fi

# --- Branch-Rulesets --------------------------------------------------------
# Vorlagen aus dem Zielprojekt (von setup.sh dorthin kopiert), sonst aus
# diesem Repo. --check-Namen werden vor dem Import ergänzt.
RULESET_DIR="$TARGET/.github/rulesets"
[ -d "$RULESET_DIR" ] || RULESET_DIR="$SRC/.github/rulesets"

existing="$(gh api "repos/$REPO/rulesets" --jq '.[].name' 2>/dev/null || true)"

found_any=0
for file in "$RULESET_DIR"/*.json; do
  [ -e "$file" ] || continue
  found_any=1
  name="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$file")"
  if printf '%s\n' "$existing" | grep -Fxq "$name"; then
    echo "  ⏭  Ruleset übersprungen (existiert schon): $name"
    continue
  fi
  # Zusätzliche Required Status Checks aus --check einfügen (dedupliziert).
  payload="$(python3 - "$file" "${EXTRA_CHECKS[@]+"${EXTRA_CHECKS[@]}"}" <<'PYEOF'
import json, sys

ruleset = json.load(open(sys.argv[1]))
extra = sys.argv[2:]
for rule in ruleset.get("rules", []):
    if rule.get("type") == "required_status_checks":
        checks = rule["parameters"]["required_status_checks"]
        have = {c["context"] for c in checks}
        checks.extend({"context": c} for c in extra if c not in have)
print(json.dumps(ruleset))
PYEOF
)"
  if printf '%s' "$payload" | gh api -X POST "repos/$REPO/rulesets" --input - --silent 2>/dev/null; then
    echo "  ✓  Ruleset importiert: $name"
  else
    echo "  ⚠  Ruleset '$name' konnte nicht importiert werden — alternativ von Hand:"
    echo "     Settings -> Rules -> Rulesets -> 'Import a ruleset' -> $file"
  fi
done
[ "$found_any" = 1 ] || echo "  ℹ  Keine Ruleset-Vorlagen unter $RULESET_DIR gefunden."

echo
echo "Fertig. Kontrolle im Browser: https://github.com/$REPO/settings/rules"
echo "Hinweis: Auf privaten Free-Plan-Repos werden Rulesets gespeichert, aber"
echo "nicht durchgesetzt — die CI-Gates auf jedem PR gelten trotzdem."
