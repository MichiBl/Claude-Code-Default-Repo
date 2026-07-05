#!/usr/bin/env bash
#
# setup.sh — kopiert das Claude-Code-Default-Setup in ein Zielprojekt.
#
# Verwendung:
#   ./setup.sh /pfad/zum/projekt          # Dateien kopieren (nie überschreiben)
#   ./setup.sh --diff /pfad/zum/projekt   # nur vergleichen: fehlt/identisch/weicht ab
#
# Die Vorlagen liegen im Repo bereits unter ihren verbindlichen Punkt-Namen
# und werden 1:1 ins Zielprojekt kopiert:
#
#   .claude/        (Agents, Skill, Hooks, Settings)
#   .githooks/      (Pre-Commit-Secret-Scan)
#   .github/        (CI- und Secret-Scan-Workflows, Dependabot)
#   .gitleaks.toml
#   .gitignore      (Secrets, Deps, Build-Artefakte)
#   .env.example
#   CLAUDE.md
#
# Existierende Dateien werden NIE überschrieben — der Konflikt wird gemeldet,
# Entscheidung bleibt beim Nutzer. Der --diff-Modus ist der Update-Pfad:
# er zeigt, wo ein bestehendes Projekt vom aktuellen Template abweicht,
# ohne irgendetwas zu ändern.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODE="copy"
if [ "${1:-}" = "--diff" ]; then
  MODE="diff"
  shift
fi
TARGET="${1:-}"

if [ -z "$TARGET" ] || [ ! -d "$TARGET" ]; then
  echo "Verwendung: ./setup.sh [--diff] /pfad/zum/projekt  (Verzeichnis muss existieren)" >&2
  exit 1
fi
TARGET="$(cd "$TARGET" && pwd)"

copied=0
skipped=0
missing=0
identical=0
differs=0

copy_file() {
  local src_rel="$1" dest_rel="$2"
  local dest="$TARGET/$dest_rel"
  if [ -e "$dest" ]; then
    echo "  ⏭  übersprungen (existiert): $dest_rel"
    skipped=$((skipped + 1))
  else
    mkdir -p "$(dirname "$dest")"
    cp "$SRC/$src_rel" "$dest"
    echo "  ✓  $dest_rel"
    copied=$((copied + 1))
  fi
}

diff_file() {
  local src_rel="$1" dest_rel="$2"
  local dest="$TARGET/$dest_rel"
  if [ ! -e "$dest" ]; then
    echo "  ✗  fehlt:      $dest_rel"
    missing=$((missing + 1))
  elif cmp -s "$SRC/$src_rel" "$dest"; then
    echo "  =  identisch:  $dest_rel"
    identical=$((identical + 1))
  else
    echo "  ~  weicht ab:  $dest_rel"
    # (|| true: diff meldet Abweichung per Exit-Code 1 — kein Fehler unter pipefail.)
    diff -u "$SRC/$src_rel" "$dest" 2>/dev/null | sed -n '3,20p' | sed 's/^/       /' || true
    differs=$((differs + 1))
  fi
}

process_file() {
  if [ "$MODE" = "diff" ]; then
    diff_file "$1" "$2"
  else
    copy_file "$1" "$2"
  fi
}

# Vorlagen-Ordner rekursiv verarbeiten (gleicher Name im Zielprojekt).
process_tree() {
  local dir="$1"
  while IFS= read -r -d '' f; do
    local rel="${f#"$SRC/$dir"/}"
    process_file "$dir/$rel" "$dir/$rel"
  done < <(find "$SRC/$dir" -type f ! -name '.DS_Store' -print0)
}

if [ "$MODE" = "diff" ]; then
  echo "Claude Code Default Setup — Vergleich mit $TARGET"
else
  echo "Claude Code Default Setup -> $TARGET"
fi
echo

process_tree ".claude"
process_tree ".githooks"
process_tree ".github"
process_file ".gitleaks.toml" ".gitleaks.toml"
process_file ".gitignore"     ".gitignore"
process_file ".env.example"   ".env.example"
process_file "CLAUDE.md"      "CLAUDE.md"

if [ "$MODE" = "diff" ]; then
  echo
  echo "Ergebnis: $identical identisch, $differs abweichend, $missing fehlend."
  echo "Abweichungen prüfen und gezielt übernehmen — dieses Skript ändert nichts."
  exit 0
fi

# Hooks ausführbar machen.
chmod +x "$TARGET/.claude/hooks/"*.sh "$TARGET/.githooks/pre-commit" 2>/dev/null || true

# Git-Hooks aktivieren, wenn das Ziel ein Git-Repo ist.
if git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$TARGET" config core.hooksPath .githooks
  echo
  echo "  ✓  git core.hooksPath -> .githooks (Pre-Commit-Secret-Scan aktiv)"
else
  echo
  echo "  ⚠  Kein Git-Repo — nach 'git init' einmal ausführen:"
  echo "     git -C \"$TARGET\" config core.hooksPath .githooks"
fi

# Stack-Hinweis für die CI-Vorlage — plus Lint-Gate-Check: ohne Linter im
# Zielprojekt laufen verify.sh, CI und QA still leer (falsche Sicherheit).
echo
if [ -f "$TARGET/package.json" ]; then
  echo "  ℹ  Node-Projekt erkannt -> .github/workflows/ci-node.yml.example nach ci.yml umbenennen und anpassen."
  if ! grep -q '"lint"' "$TARGET/package.json"; then
    echo "  ⚠  Kein \"lint\"-Script in package.json — verify.sh/CI/QA linten sonst NICHT (z. B. ESLint einrichten)."
  fi
elif [ -f "$TARGET/pyproject.toml" ] || [ -f "$TARGET/requirements.txt" ]; then
  echo "  ℹ  Python-Projekt erkannt -> .github/workflows/ci-python.yml.example nach ci.yml umbenennen, EINEN Job (uv|pip) behalten."
  if ! grep -qs 'ruff' "$TARGET/pyproject.toml" "$TARGET"/requirements*.txt; then
    echo "  ⚠  ruff nicht in den Dependencies — verify.sh/CI/QA linten sonst NICHT (ruff als Dev-Dependency ergänzen)."
  fi
else
  echo "  ℹ  Stack nicht erkannt -> passende ci-*.yml.example nach ci.yml umbenennen und anpassen."
  echo "     Anderer Stack (Go, Rust, …)? Eigenes Gate als .claude/hooks/verify-project.sh hinterlegen."
fi

echo
echo "Fertig: $copied Datei(en) kopiert, $skipped übersprungen."
echo
echo "Nächste Schritte:"
echo "  1. CLAUDE.md ausfüllen (alle <PLATZHALTER>) — oder Claude machen lassen:"
echo "     \"Fülle die CLAUDE.md-Platzhalter anhand dieses Repos aus.\""
echo "  2. gitleaks installieren, falls nicht vorhanden (z. B. 'brew install gitleaks')."
echo "  3. CI-Vorlage aktivieren (siehe Hinweis oben)."
echo "  4. Auf GitHub: Settings -> Code security -> Secret scanning + Push protection aktivieren."
echo
echo "Update-Check später: ./setup.sh --diff $TARGET"
