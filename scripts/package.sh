#!/usr/bin/env bash
#
# Build a WoW-ready release zip for Long Live Pets.
#
# WoW only loads an addon when AddOns/<Folder>/<Folder>.toc exists, i.e. the
# folder name must match the .toc name exactly. GitHub's auto-generated
# "Source code (zip)" names its top folder "LongLivePets-<tag>" and nests the
# bundled tdBattlePetScript addon *inside* it, so neither addon loads. This
# script produces the layout the README promises instead:
#
#   LongLivePets-<version>.zip
#   ├── LongLivePets/        (this addon — no dev files, no nested td)
#   └── tdBattlePetScript/   (the bundled standalone addon, as a sibling)
#
# Usage: scripts/package.sh [version]
#   version defaults to the "## Version:" line in LongLivePets.toc
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-$(grep -m1 '^## Version:' LongLivePets.toc | sed 's/^## Version:[[:space:]]*//' | tr -d '\r')}"
if [ -z "$VERSION" ]; then
  echo "error: could not determine version (pass it as an argument)" >&2
  exit 1
fi

OUT="$ROOT/dist"
ZIP="$OUT/LongLivePets-$VERSION.zip"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# --- Stage the LongLivePets addon (exclude dev files + the sibling addon) ---
mkdir -p "$STAGE/LongLivePets"
rsync -a \
  --exclude '.git' \
  --exclude '.github' \
  --exclude '.gitignore' \
  --exclude 'scripts' \
  --exclude 'dist' \
  --exclude 'release' \
  --exclude 'Tests' \
  --exclude 'TEST_LOG.md' \
  --exclude 'docs' \
  --exclude 'tdBattlePetScript' \
  --exclude '.DS_Store' \
  --exclude '*.zip' \
  ./ "$STAGE/LongLivePets/"

# --- Stage tdBattlePetScript as a SIBLING addon (its own AddOns/ folder) ---
rsync -a --exclude '.git' --exclude '.DS_Store' \
  "$ROOT/tdBattlePetScript/" "$STAGE/tdBattlePetScript/"

# --- Sanity checks: both addons must load (folder name == toc name) ---
test -f "$STAGE/LongLivePets/LongLivePets.toc" \
  || { echo "error: LongLivePets/LongLivePets.toc missing in package" >&2; exit 1; }
test -f "$STAGE/tdBattlePetScript/tdBattlePetScript.toc" \
  || { echo "error: tdBattlePetScript/tdBattlePetScript.toc missing in package" >&2; exit 1; }

mkdir -p "$OUT"
rm -f "$ZIP"
( cd "$STAGE" && zip -rqX "$ZIP" LongLivePets tdBattlePetScript )

echo "Built $ZIP"
echo "---"
unzip -l "$ZIP" | sed -n '1,4p;$p'
