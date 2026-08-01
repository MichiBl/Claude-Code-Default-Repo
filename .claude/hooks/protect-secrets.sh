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

# Interpreter suchen statt python3 vorauszusetzen: fehlt er, lieferte das alte
# `python3 -c … 2>/dev/null || true` eine leere Variable, der Hook beendete mit
# 0 und erlaubte ALLES — ohne eine Zeile auf stderr. Genau der Zustand "sieht
# geschützt aus, ist es nicht", gegen den das ganze Setup gebaut ist.
PY=""
for c in python3 python; do
  if command -v "$c" >/dev/null 2>&1; then PY="$c"; break; fi
done

if [ -n "$PY" ]; then
  FILE="$(printf '%s' "$STDIN_JSON" | "$PY" -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print(""); sys.exit(0)
ti = d.get("tool_input") or {}
print(ti.get("file_path", "") if isinstance(ti, dict) else "")
' 2>/dev/null || true)"
else
  # Fallback ohne Interpreter: erstes "file_path" aus dem Roh-JSON schneiden.
  # Dekodiert keine JSON-Escapes (\" oder \uXXXX im Pfad) — für reale Pfade
  # reicht es, und ein eingeschränkt arbeitender Hook schlägt einen aus, der
  # gar nichts tut.
  FILE="$(printf '%s' "$STDIN_JSON" \
    | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -n 1)"
  {
    echo "⚠  protect-secrets: kein python3/python gefunden — Pfad-Extraktion läuft"
    echo "   im sed-Fallback (JSON-Escapes werden nicht dekodiert). Diese Schicht"
    echo "   ist eingeschränkt; es tragen weiter .githooks/pre-commit und die CI."
  } >&2
fi

# Bewusst fail-open, wenn kein Pfad erkennbar ist: welche Datei betroffen ist,
# steht dann nicht fest — blockieren hieße hier JEDES Edit/Write blockieren,
# nicht einen Fehlalarm erzeugen. Die harten Garantien liegen ohnehin bei den
# Scan-Schichten (gitleaks, CI, Push Protection).
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
