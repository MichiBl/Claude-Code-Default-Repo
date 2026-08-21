#!/usr/bin/env bash
#
# verify-project.sh — Projekt-Gate DIESES Template-Repos.
#
# verify.sh führt nur dieses Skript aus, wenn es ausführbar ist, und
# überspringt dann seine Stack-Autoerkennung. Nötig, weil das Produkt hier
# Bash und Markdown ist: verify.sh findet weder package.json noch
# pyproject.toml und terminiert deshalb IMMER mit exit 0 — Änderungen an den
# Hooks wurden lokal von nichts geprüft, Regressionen fielen erst nach dem
# Push in der CI auf.
#
# Exit-Code-Vertrag (identisch zu verify.sh):
#   0 -> Stop erlauben
#   2 -> Stop blockieren; stderr geht als Begründung an Claude zurück
#
# ACHTUNG: Diese Datei ist template-eigen und darf NICHT in Zielprojekte
# kopiert werden — dort würde sie die Stack-Autoerkennung von verify.sh
# abschalten und einen Selbsttest suchen, den es nicht gibt. setup.sh schließt
# sie deshalb namentlich vom Kopieren aus (process_tree), und der Selbsttest
# sichert das ab.

set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$ROOT" || exit 0

FAILED=""
OUT=""

# --- Gate 1: Selbsttest der Hooks (das verbindliche Gate dieses Repos) --------
if ! RESULT="$(./tests/hook-selftest.sh 2>&1)"; then
  FAILED="${FAILED}hook-selftest; "
  # Nur die fehlgeschlagenen Assertions plus die Ergebniszeile — die
  # vollständige Ausgabe sind >70 grüne Zeilen, in denen der Befund untergeht.
  OUT="${OUT}
=== tests/hook-selftest.sh (fehlgeschlagen) ===
$(printf '%s\n' "$RESULT" | grep -E '✗|Ergebnis:')"
fi

# --- Gate 2: shellcheck, falls vorhanden -------------------------------------
# Wie bei gitleaks in secret-scan.sh: fehlt das Tool, wird übersprungen statt
# hart zu scheitern (frischer Klon, macOS ohne brew-Paket). Die CI führt es
# unabhängig davon aus — dort ist es nicht überspringbar.
if command -v shellcheck >/dev/null 2>&1; then
  # -s bash, weil die Skripte bash-Features nutzen (der Shebang ist
  # /usr/bin/env bash, den shellcheck bei .sh nicht immer sicher auflöst).
  if ! RESULT="$(shellcheck -s bash -S warning \
      .claude/hooks/*.sh .githooks/pre-commit .githooks/pre-push \
      setup.sh setup-github.sh \
      tests/hook-selftest.sh 2>&1)"; then
    FAILED="${FAILED}shellcheck; "
    OUT="${OUT}
=== shellcheck (fehlgeschlagen) ===
${RESULT}"
  fi
else
  echo "verify-project: shellcheck nicht installiert — übersprungen (brew install shellcheck). Die CI führt es trotzdem aus." >&2
fi

if [ -n "$FAILED" ]; then
  {
    echo "❌ Projekt-Gates fehlgeschlagen: ${FAILED%; }"
    printf '%s\n' "$OUT" | tail -n 120
    echo
    echo "Erst beheben, dann erneut stoppen."
  } >&2
  exit 2
fi

exit 0
