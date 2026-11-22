#!/usr/bin/env bash
# install.sh — copy the Discord skill pack into an agent's skills directory.
#
# Usage:
#   ./scripts/install.sh                  # -> ~/.hermes/skills/devops
#   ./scripts/install.sh ~/.claude/skills
#   ./scripts/install.sh /path/to/skills discord-platform-api
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/skills"
DEST="${1:-$HOME/.hermes/skills/devops}"
ONLY="${2:-}"

if [ ! -d "$SRC" ]; then
  echo "error: skills source not found at $SRC" >&2
  exit 1
fi

mkdir -p "$DEST"

installed=0
for dir in "$SRC"/*/; do
  name="$(basename "$dir")"

  if [ -n "$ONLY" ] && [ "$name" != "$ONLY" ]; then
    continue
  fi

  if [ ! -f "$dir/SKILL.md" ]; then
    echo "skip $name (no SKILL.md)"
    continue
  fi

  rm -rf "$DEST/$name"
  cp -r "$dir" "$DEST/$name"
  refs=$([ -d "$DEST/$name/references" ] && ls "$DEST/$name/references"/*.md 2>/dev/null | wc -l || echo 0)
  echo "installed $name  (SKILL.md + ${refs} reference(s))"
  installed=$((installed + 1))
done

if [ "$installed" -eq 0 ]; then
  echo "error: nothing installed (check destination: $DEST)" >&2
  exit 1
fi

echo
echo "Done. Load with:"
echo "  skill_view(name='discord-platform-api')"
echo "  skill_view(name='discord-platform-api', file_path='references/gateway.md')"
