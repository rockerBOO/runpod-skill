#!/usr/bin/env bash
# Symlink each skill into ~/.claude/skills (or $1) so edits here are live. Re-run after adding a skill.
set -euo pipefail
src=$(dirname "$(realpath "$0")")/skills; dst=${1:-$HOME/.claude/skills}; mkdir -p "$dst"
for s in "$src"/*/; do
  n=$(basename "$s"); t=$dst/$n
  if [ -e "$t" ] && [ ! -L "$t" ]; then echo "skip $n: $t exists and is not a symlink"; continue; fi
  ln -sfn "${s%/}" "$t"; echo "linked $t -> ${s%/}"
done
