#!/usr/bin/env bash
#
# setup.sh — kopiert das Claude-Code-Default-Setup in ein Zielprojekt.
#
# Verwendung:
#   ./setup.sh /pfad/zum/projekt           # Dateien kopieren (nie überschreiben)
#   ./setup.sh --diff /pfad/zum/projekt    # nur vergleichen: fehlt/identisch/weicht ab
#   ./setup.sh --update /pfad/zum/projekt  # NUR den Werkzeug-Kern überschreiben
#
# Zwei Sorten Dateien, und der Unterschied ist der Kern des Skripts:
#
#   KERN    — der gemeinsame Werkzeugkasten (Agents, Skills, Hooks, .githooks).
#             Er MUSS in allen Projekten identisch sein: hier gelernte
#             Verbesserungen sollen überall ankommen. Abweichung = Verfall.
#             --update überschreibt genau diese Dateien.
#   PROJEKT — Inhalt, der pro Projekt anders sein MUSS (CLAUDE.md, .gitignore,
#             settings.json, ci.yml, dependabot.yml, .gitleaks.toml,
#             requirements-status.md, .env.example). Abweichung ist hier normal
#             und wird nie überschrieben.
#
# Warum die Trennung: Ohne sie meldet --diff bei jedem Projekt Abweichungen in
# CLAUDE.md & Co. — Rauschen, in dem echter Verfall des Werkzeugkastens
# untergeht. Genau so sind hier fünf auseinandergelaufene Kopien entstanden.
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
#   CLAUDE.md       (aus templates/CLAUDE.md — die Vorlage mit <PLATZHALTERN>;
#                    die CLAUDE.md im Root ist der Kontext DIESES Repos)
#   docs/requirements-status.md   (zentrale Roadmap: Punkte mit Status + AK)
#
# Im Kopier-Modus werden existierende Dateien NIE überschrieben — der Konflikt
# wird gemeldet, die Entscheidung bleibt beim Nutzer.
#
# Exit-Codes von --diff (damit der Modus als Prüfung taugt):
#   0 = Werkzeug-Kern deckungsgleich   1 = Kern weicht ab oder fehlt
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODE="copy"
case "${1:-}" in
  --diff)   MODE="diff";   shift ;;
  --update) MODE="update"; shift ;;
esac
TARGET="${1:-}"

if [ -z "$TARGET" ] || [ ! -d "$TARGET" ]; then
  echo "Verwendung: ./setup.sh [--diff|--update] /pfad/zum/projekt  (Verzeichnis muss existieren)" >&2
  exit 1
fi
TARGET="$(cd "$TARGET" && pwd)"

copied=0
skipped=0
missing=0
identical=0
differs=0
updated=0
core_drift=0   # Kern-Dateien, die abweichen oder fehlen (Exit-Code von --diff)
hooks_inert=0  # .githooks/pre-commit liegt da, ist aber nicht aktiviert

# is_core <dest_rel> -> 0 = Werkzeug-Kern (muss überall identisch sein).
# Bewusst NICHT im Kern: .claude/settings.json (Projekte ergänzen eigene
# Permissions/Env), .github/** (ci.yml und dependabot.yml hängen am Stack),
# .gitleaks.toml (projekteigene Allowlist).
is_core() {
  case "$1" in
    .claude/agents/*|.claude/skills/*|.claude/hooks/*|.githooks/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Hooks sind KERN, ihre Verdrahtung steht aber in .claude/settings.json — einer
# PROJEKT-Datei, die --update bewusst nicht anfasst. Ein neu dazugekommener Hook
# liegt sonst still im Verzeichnis und wird nie aufgerufen: der gefährlichste
# Fehlmodus, weil das Projekt geschützt AUSSIEHT. Deshalb hier explizit melden.
warn_unwired_hooks() {
  local settings="$TARGET/.claude/settings.json" hook name unwired=""
  [ -f "$settings" ] || return 0
  for hook in "$TARGET/.claude/hooks/"*.sh; do
    [ -e "$hook" ] || continue
    name="$(basename "$hook")"
    [ "$name" = "verify-project.sh" ] && continue   # projekteigenes Gate, wird von verify.sh aufgerufen
    if ! grep -qF "$name" "$settings"; then
      unwired="${unwired}${name} "
    fi
  done
  [ -z "$unwired" ] && return 0
  echo
  echo "⚠  Nicht verdrahtete Hooks: $unwired"
  echo "   Die Dateien liegen jetzt in .claude/hooks/, werden aber von"
  echo "   .claude/settings.json nicht aufgerufen — sie tun also NICHTS."
  echo "   settings.json ist eine PROJEKT-Datei; Verdrahtung von Hand ergänzen"
  echo "   (Vorlage: $SRC/.claude/settings.json)."
  return 0
}

# Zweiter Fall derselben Sorte: .githooks/pre-commit ist KERN und wird kopiert,
# aber Git ruft ihn nur auf, wenn core.hooksPath darauf zeigt. Ohne das liegt die
# Secret-Schranke da und tut nichts — Schicht 2 der Defense-in-Depth fehlt still.
# check_only=1 (für --diff) meldet nur; sonst wird die Verdrahtung gesetzt.
git_hooks_path() { # git_hooks_path [check_only] -> 0 = aktiv/nichts zu tun, 1 = inaktiv
  local check_only="${1:-0}" current
  [ -f "$TARGET/.githooks/pre-commit" ] || return 0
  if ! git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Kein Befund, sondern ein noch nicht initialisiertes Projekt: hinweisen,
    # aber nicht als Verfall werten (sonst ist --diff auf frischen Ordnern rot).
    echo
    echo "ℹ  Kein Git-Repo — .githooks/pre-commit bleibt inaktiv. Nach 'git init':"
    echo "   git -C \"$TARGET\" config core.hooksPath .githooks"
    return 0
  fi
  current="$(git -C "$TARGET" config --get core.hooksPath 2>/dev/null || true)"
  [ "$current" = ".githooks" ] && return 0
  if [ -n "$current" ]; then
    # Eigene Hook-Verdrahtung des Projekts nie überschreiben — nur melden.
    echo
    echo "⚠  core.hooksPath zeigt auf '$current', nicht auf .githooks."
    echo "   .githooks/pre-commit (gitleaks) läuft dadurch NICHT. Unangetastet"
    echo "   gelassen, weil das eine bewusste Projektentscheidung sein kann."
    return 1
  fi
  if [ "$check_only" = "1" ]; then
    echo
    echo "⚠  core.hooksPath ist nicht gesetzt — .githooks/pre-commit (gitleaks)"
    echo "   liegt im Repo, wird von Git aber nie aufgerufen."
    echo "   Aktivieren mit: ./setup.sh --update $TARGET"
    return 1
  fi
  git -C "$TARGET" config core.hooksPath .githooks
  echo "  ✓  git core.hooksPath -> .githooks (Pre-Commit-Secret-Scan jetzt aktiv)"
  return 0
}

update_file() {
  local src_rel="$1" dest_rel="$2"
  local dest="$TARGET/$dest_rel"
  if ! is_core "$dest_rel"; then
    return 0   # Projekt-Datei: im Update-Modus grundsätzlich unangetastet.
  fi
  if cmp -s "$SRC/$src_rel" "$dest" 2>/dev/null; then
    identical=$((identical + 1))
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  if [ -e "$dest" ]; then
    cp "$SRC/$src_rel" "$dest"
    echo "  ↑  aktualisiert: $dest_rel"
  else
    cp "$SRC/$src_rel" "$dest"
    echo "  +  ergänzt:      $dest_rel"
  fi
  updated=$((updated + 1))
}

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
  # (Kein "is_core X && …" am Zeilen-/Funktionsende: ein fehlschlagender
  # &&-Ausdruck als letzter Befehl liefert Exit 1 und beendet unter `set -e`
  # das ganze Skript bei der ersten PROJEKT-Datei.)
  local tag="PROJEKT" core=1
  if is_core "$dest_rel"; then tag="KERN   "; core=0; fi
  if [ ! -e "$dest" ]; then
    echo "  ✗  $tag fehlt:      $dest_rel"
    missing=$((missing + 1))
    if [ "$core" -eq 0 ]; then core_drift=$((core_drift + 1)); fi
  elif cmp -s "$SRC/$src_rel" "$dest"; then
    echo "  =  $tag identisch:  $dest_rel"
    identical=$((identical + 1))
  else
    echo "  ~  $tag weicht ab:  $dest_rel"
    # Projekt-Dateien weichen erwartungsgemäß ab — der Diff dazu wäre nur
    # Rauschen. Nur den Kern im Detail zeigen, denn nur der ist Verfall.
    if is_core "$dest_rel"; then
      # (|| true: diff meldet Abweichung per Exit-Code 1 — kein Fehler unter pipefail.)
      diff -u "$SRC/$src_rel" "$dest" 2>/dev/null | sed -n '3,20p' | sed 's/^/       /' || true
      core_drift=$((core_drift + 1))
    fi
    differs=$((differs + 1))
  fi
  return 0   # Abweichung ist ein Befund, kein Fehler — sonst killt `set -e` den Lauf.
}

process_file() {
  case "$MODE" in
    diff)   diff_file   "$1" "$2" ;;
    update) update_file "$1" "$2" ;;
    *)      copy_file   "$1" "$2" ;;
  esac
}

# Vorlagen-Ordner rekursiv verarbeiten (gleicher Name im Zielprojekt).
# Zwei template-eigene Dateien bleiben bewusst hier:
#   * hook-selftest.yml   — CI, die die Hooks DIESES Repos testet; im
#                           Zielprojekt toter Ballast.
#   * verify-project.sh   — Gate DIESES Repos; im Zielprojekt würde es die
#                           Stack-Autoerkennung von verify.sh abschalten und
#                           einen Selbsttest suchen, den es dort nicht gibt.
process_tree() {
  local dir="$1"
  while IFS= read -r -d '' f; do
    local rel="${f#"$SRC/$dir"/}"
    process_file "$dir/$rel" "$dir/$rel"
  done < <(find "$SRC/$dir" -type f ! -name '.DS_Store' \
    ! -name 'hook-selftest.yml' ! -name 'verify-project.sh' -print0)
}

case "$MODE" in
  diff)   echo "Claude Code Default Setup — Vergleich mit $TARGET" ;;
  update) echo "Claude Code Default Setup — Werkzeug-Kern aktualisieren in $TARGET" ;;
  *)      echo "Claude Code Default Setup -> $TARGET" ;;
esac
echo

process_tree ".claude"
process_tree ".githooks"
process_tree ".github"
process_file ".gitleaks.toml" ".gitleaks.toml"
process_file ".gitignore"     ".gitignore"
process_file ".env.example"   ".env.example"
process_file "templates/CLAUDE.md" "CLAUDE.md"
process_file "docs/requirements-status.md" "docs/requirements-status.md"

if [ "$MODE" = "diff" ]; then
  echo
  echo "Ergebnis: $identical identisch, $differs abweichend, $missing fehlend."
  git_hooks_path 1 || hooks_inert=1
  if [ "$core_drift" -gt 0 ]; then
    echo
    echo "⚠  $core_drift Kern-Datei(en) weichen ab oder fehlen — der Werkzeugkasten"
    echo "   dieses Projekts ist nicht auf dem Stand des Templates."
    echo "   Übernehmen mit: ./setup.sh --update $TARGET"
    exit 1
  fi
  # Ein inaktiver Secret-Hook ist genauso ein Befund wie eine veraltete Datei:
  # der Werkzeugkasten ist dann nicht in dem Zustand, den er vorgibt zu haben.
  [ "$hooks_inert" -eq 1 ] && exit 1
  echo "Werkzeug-Kern ist deckungsgleich. Abweichungen bei PROJEKT-Dateien sind normal."
  exit 0
fi

if [ "$MODE" = "update" ]; then
  chmod +x "$TARGET/.claude/hooks/"*.sh "$TARGET/.githooks/pre-commit" 2>/dev/null || true
  echo
  echo "Fertig: $updated Kern-Datei(en) aktualisiert, $identical bereits aktuell."
  echo "PROJEKT-Dateien (CLAUDE.md, settings.json, ci.yml, …) blieben unangetastet."
  git_hooks_path || true
  warn_unwired_hooks
  if [ "$updated" -gt 0 ]; then
    echo
    echo "Änderungen vor dem Commit durchsehen: git -C $TARGET diff"
  fi
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

# CI-Aktivierung: bei erkanntem Stack wird die passende Vorlage direkt als
# ci.yml geschrieben (statt nur auf das Umbenennen hinzuweisen) — der Fehlmodus
# "CI vergessen, gar kein Gate" entfällt. Existierende ci.yml wird NIE
# angetastet. Dazu Lint-Gate-Check: ohne Linter im Zielprojekt laufen
# verify.sh, CI und QA still leer (falsche Sicherheit).
activate_ci() { # activate_ci <example-datei> [drop-job]
  local example="$1" drop="${2:-}"
  local dest="$TARGET/.github/workflows/ci.yml"
  mkdir -p "$(dirname "$dest")"
  {
    echo "# Aktiviert durch setup.sh aus ${example} — Schritte/Versionen/Pfade"
    echo "# bei Bedarf an das Projekt anpassen."
    # Führenden Kommentarblock der Vorlage ("Aktivieren: …") überspringen;
    # bei Python zusätzlich den nicht passenden Job (uv|pip) entfernen.
    awk -v drop="$drop" '
      body == 0 { if ($0 ~ /^#/ || $0 ~ /^[[:space:]]*$/) next; body = 1 }
      /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { injob = (drop != "" && $0 == "  " drop ":") }
      injob { next }
      { print }
    ' "$SRC/.github/workflows/$example"
  } > "$dest"
}

echo
CI_DEST="$TARGET/.github/workflows/ci.yml"
if [ -f "$TARGET/package.json" ]; then
  if [ -e "$CI_DEST" ]; then
    echo "  ℹ  Node-Projekt erkannt — .github/workflows/ci.yml existiert bereits (unverändert)."
  else
    activate_ci "ci-node.yml.example"
    echo "  ✓  Node-Projekt erkannt -> CI aktiviert: .github/workflows/ci.yml (aus ci-node.yml.example)."
  fi
  if ! grep -q '"lint"' "$TARGET/package.json"; then
    echo "  ⚠  Kein \"lint\"-Script in package.json — verify.sh/CI/QA linten sonst NICHT (z. B. ESLint einrichten)."
  fi
elif [ -f "$TARGET/pyproject.toml" ] || [ -f "$TARGET/requirements.txt" ]; then
  if [ -e "$CI_DEST" ]; then
    echo "  ℹ  Python-Projekt erkannt — .github/workflows/ci.yml existiert bereits (unverändert)."
  elif [ -f "$TARGET/uv.lock" ]; then
    activate_ci "ci-python.yml.example" "pip"
    echo "  ✓  Python-Projekt (uv) erkannt -> CI aktiviert: .github/workflows/ci.yml (uv-Job)."
  else
    activate_ci "ci-python.yml.example" "uv"
    echo "  ✓  Python-Projekt (pip) erkannt -> CI aktiviert: .github/workflows/ci.yml (pip-Job)."
  fi
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
echo "  3. CI prüfen: ci.yml wurde nach Stack-Erkennung automatisch aktiviert —"
echo "     Schritte/Versionen ans Projekt anpassen (siehe Hinweis oben)."
echo "  4. Serverseitige GitHub-Schalter aktivieren (Dependabot, Secret scanning,"
echo "     Branch-Ruleset): ./setup-github.sh $TARGET --check \"<CI-Job-Name>\""
echo "     (braucht 'gh auth login'; Details im README, Abschnitt setup-github.sh)."
echo
echo "Update-Check später: ./setup.sh --diff $TARGET"
