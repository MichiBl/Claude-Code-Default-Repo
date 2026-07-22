#!/usr/bin/env bash
#
# protect-secrets.sh — generischer PreToolUse-Hook (matcher "Edit|Write"), der
# Schreibzugriffe von Claude auf .env-/Secret-Dateien blockt.
#
# Gegenstück zu den permissions.deny-Regeln in settings.json: die decken nur
# Lesezugriffe (Read) ab — dieser Hook blockt das Anlegen/Ändern derselben
# Dateien. Vorlagen ohne echte Werte (.env.example etc.) bleiben bewusst
# editierbar, damit Claude sie pflegen kann.
#
# Exit-Code-Vertrag (PreToolUse):
#   0 -> Tool-Call erlauben
#   2 -> Tool-Call blockieren; stderr geht als Begründung an Claude zurück
#
# Wie die deny-Regeln Best-Effort: gefangen werden direkte Edit/Write-Aufrufe.
# Indirekte Wege (z. B. Shell-Redirects) sieht dieser Hook nicht — die harten
# Garantien liefern die Scan-Schichten (gitleaks, CI, Push Protection).

set -uo pipefail

# --- PreToolUse-Payload lesen; Dateipfad extrahieren --------------------------
STDIN_JSON="$(cat 2>/dev/null || true)"
FILE="$(printf '%s' "$STDIN_JSON" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print(""); sys.exit(0)
ti = d.get("tool_input") or {}
print(ti.get("file_path", "") if isinstance(ti, dict) else "")
' 2>/dev/null || true)"
[ -n "$FILE" ] || exit 0

BASE="$(basename "$FILE")"

# Vorlagen ohne echte Werte bleiben editierbar.
case "$BASE" in
  .env.example|.env.dist|.env.template) exit 0 ;;
esac

# Gleiche Abdeckung wie die deny-Regeln in settings.json.
BLOCKED=""
case "$BASE" in
  .env|.env.*|*.pem|*.key|id_rsa*|id_ed25519*|credentials*.json) BLOCKED=1 ;;
esac
case "$FILE" in
  secrets/*|*/secrets/*) BLOCKED=1 ;;
esac

if [ -n "$BLOCKED" ]; then
  {
    echo "🔒 protect-secrets: '$FILE' kann Credentials enthalten und wird nicht von Claude bearbeitet."
    echo "Ist die Änderung wirklich nötig, muss der Nutzer sie manuell vornehmen."
  } >&2
  exit 2
fi

exit 0
