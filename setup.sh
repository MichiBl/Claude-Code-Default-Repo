#!/usr/bin/env bash
#
# setup.sh — kopiert das Claude-Code-Default-Setup in ein Zielprojekt.
#
# Verwendung:
#   ./setup.sh /pfad/zum/projekt
#
# Die Vorlagen liegen im Repo bereits unter ihren verbindlichen Punkt-Namen
# und werden 1:1 ins Zielprojekt kopiert:
#
#   .claude/        (Agents, Skill, Hooks, Settings)
#   .githooks/      (Pre-Commit-Secret-Scan)
#   .github/        (CI- und Secret-Scan-Workflows)
#   .gitleaks.toml
#   .gitignore      (Secrets, Deps, Build-Artefakte)
#   CLAUDE.md
#
# Existierende Dateien werden NIE überschrieben — der Konflikt wird gemeldet,
# Entscheidung bleibt beim Nutzer.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-}"

if [ -z "$TARGET" ] || [ ! -d "$TARGET" ]; then
  echo "Verwendung: ./setup.sh /pfad/zum/projekt  (Verzeichnis muss existieren)" >&2
  exit 1
fi
TARGET="$(cd "$TARGET" && pwd)"

copied=0
skipped=0

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

# Vorlagen-Ordner rekursiv ins Zielprojekt kopieren (gleicher Name).
copy_tree() {
  local dir="$1"
  while IFS= read -r -d '' f; do
    local rel="${f#"$SRC/$dir"/}"
    copy_file "$dir/$rel" "$dir/$rel"
  done < <(find "$SRC/$dir" -type f ! -name '.DS_Store' -print0)
}

echo "Claude Code Default Setup -> $TARGET"
echo

copy_tree ".claude"
copy_tree ".githooks"
copy_tree ".github"
copy_file ".gitleaks.toml" ".gitleaks.toml"
copy_file ".gitignore"     ".gitignore"
copy_file "CLAUDE.md"      "CLAUDE.md"

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

# Stack-Hinweis für die CI-Vorlage.
echo
if [ -f "$TARGET/package.json" ]; then
  echo "  ℹ  Node-Projekt erkannt -> .github/workflows/ci-node.yml.example nach ci.yml umbenennen und anpassen."
elif [ -f "$TARGET/pyproject.toml" ] || [ -f "$TARGET/requirements.txt" ]; then
  echo "  ℹ  Python-Projekt erkannt -> .github/workflows/ci-python.yml.example nach ci.yml umbenennen, EINEN Job (uv|pip) behalten."
else
  echo "  ℹ  Stack nicht erkannt -> passende ci-*.yml.example nach ci.yml umbenennen und anpassen."
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
