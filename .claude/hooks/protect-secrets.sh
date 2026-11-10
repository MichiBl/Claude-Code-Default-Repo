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

# classify <pfad> -> stdout: allow | secret | allowlist
#
# Verglichen wird kleingeschrieben: macOS-Dateisysteme unterscheiden Groß-
# und Kleinschreibung nicht — ein Schreibzugriff auf `.ENV` trifft dort die
# echte `.env`. (`tr` statt `${var,,}`: Bash 3.2.)
classify() {
  local path base
  path="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  base="$(basename "$path")"

  # Vorlagen ohne echte Werte bleiben editierbar — bewusst nur .env.example.
  # .env.dist/.env.template standen hier ebenfalls, waren aber weder in
  # .gitignore negiert noch in der .gitleaks.toml-Allowlist: Claude durfte sie
  # pflegen, committet wurden sie nie. Jeder zusätzliche Vorlagenname
  # vergrößert außerdem den in .gitleaks.toml dokumentierten blinden Fleck
  # (Vorlagen sind von allen gitleaks-Schichten ausgenommen). Wer .env.dist
  # braucht, ergänzt ihn hier UND in .gitignore UND in .gitleaks.toml.
  case "$base" in
    .env.example) echo allow; return ;;
  esac

  # Die gitleaks-Allowlist entscheidet, was die Scan-Schichten durchlassen. Darf
  # Claude sie ändern, kann es einen Fund "als Falsch-Positiv" freigeben, und
  # pre-commit, pre-push und secret-scan.sh lassen das Secret bis ins Remote
  # durch. Allowlist-Einträge sind deshalb Sache des Menschen.
  # .gitleaksignore ist derselbe Hebel in anderer Form: ein Fingerprint dort
  # unterdrückt den Fund, und gitleaks kennt keinen Schalter, die Datei zu
  # ignorieren.
  case "$base" in
    .gitleaks.toml|.gitleaksignore) echo allowlist; return ;;
  esac

  # Gleiche Abdeckung wie die deny-Regeln in settings.json. Der Selbsttest
  # gleicht die drei Aufzählungen (settings.json, dieser Hook, .gitignore)
  # gegeneinander ab — Ergänzungen gehören in alle drei.
  case "$base" in
    .env|.env.*|*.pem|*.key|*.p12|*.pfx|id_rsa*|id_ed25519*) echo secret; return ;;
    credentials*.json|service-account*.json) echo secret; return ;;
    .npmrc|.pypirc|.netrc) echo secret; return ;;
  esac
  case "$path" in
    secrets/*|*/secrets/*) echo secret; return ;;
  esac
  echo allow
}

VERDICT="$(classify "$FILE")"

# Ein Symlink mit harmlosem Namen sagt nichts über sein Ziel: geschrieben wird
# dorthin. Deshalb zusätzlich das Ziel prüfen; es gilt das strengere Urteil
# (auch für einen Link namens .env.example, der auf .env zeigt). Nur die erste
# Ebene — Ketten und Symlinks in Elternverzeichnissen bleiben Best-Effort.
if [ -L "$FILE" ]; then
  LINK_VERDICT="$(classify "$(readlink "$FILE" 2>/dev/null || true)")"
  [ "$LINK_VERDICT" = "allow" ] || VERDICT="$LINK_VERDICT"
fi

if [ "$VERDICT" = "allowlist" ]; then
  {
    echo "🔒 protect-secrets: '$FILE' ist die Allowlist der Secret-Scans und wird nicht von Claude bearbeitet."
    echo "Falsch-Positiv? Dem Nutzer Eintrag und Begründung vorschlagen — er trägt ihn selbst ein."
  } >&2
  exit 2
fi

if [ "$VERDICT" = "secret" ]; then
  {
    echo "🔒 protect-secrets: '$FILE' kann Credentials enthalten und wird nicht von Claude bearbeitet."
    echo "Ist die Änderung wirklich nötig, muss der Nutzer sie manuell vornehmen."
  } >&2
  exit 2
fi

exit 0
