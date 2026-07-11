#!/usr/bin/env bash
# =============================================================================
# Quick Mall — build the mod-portal release zip
# =============================================================================
# Produces quick-mall_<version>.zip with the exact layout the Factorio mod portal
# requires: a single top-level folder `quick-mall_<version>/` with info.json at
# its root. Used by .github/workflows/release.yml and runnable locally to inspect
# the artifact before releasing.
#
# Packaging uses an explicit ALLOWLIST of ship files (not copy-all-then-delete),
# so dev-only files (docs/, tests/, factorio-test*, run_tests.sh, link_mod.sh,
# .git, etc.) can never leak into a release.
#
# Usage:  scripts/build_release.sh [output_dir]
#   output_dir defaults to the repo root. The zip path is printed on the last line.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_DIR="$(cd "${1:-${REPO_ROOT}}" && pwd)"

# --- Read mod name + version from info.json (source of truth) ---------------
read_json() { python3 -c "import json,sys;print(json.load(open('${REPO_ROOT}/info.json'))['$1'])"; }
MOD_NAME="$(read_json name)"
VERSION="$(read_json version)"
FOLDER="${MOD_NAME}_${VERSION}"           # e.g. quick-mall_1.2.0
ZIP_PATH="${OUT_DIR}/${FOLDER}.zip"

# --- Files/dirs that ship in the release (relative to repo root) ------------
# NOTE: control.lua does an unconditional require("tests"), so tests.lua MUST
# ship. The tests/ dir (factorio-test spec) is dev-only and loaded only when the
# factorio-test mod is active, so it is intentionally excluded.
SHIP_PATHS=(
  "info.json"
  "control.lua"
  "data.lua"
  "tests.lua"
  "scripts/constants.lua"
  "scripts/prototypes.lua"
  "scripts/storage.lua"
  "scripts/recipes.lua"
  "scripts/blueprint.lua"
  "scripts/gui.lua"
  "locale/en/quick-mall.cfg"
  "thumbnail.png"
  "changelog.txt"
  "README.md"
  "LICENSE"
)

# --- Stage into a clean temp dir, then zip ----------------------------------
STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT
DEST="${STAGE}/${FOLDER}"
mkdir -p "${DEST}"

for rel in "${SHIP_PATHS[@]}"; do
  src="${REPO_ROOT}/${rel}"
  if [ ! -e "${src}" ]; then
    echo "Error: expected ship file missing: ${rel}" >&2
    exit 1
  fi
  mkdir -p "${DEST}/$(dirname "${rel}")"
  cp "${src}" "${DEST}/${rel}"
done

rm -f "${ZIP_PATH}"
( cd "${STAGE}" && zip -r -q "${ZIP_PATH}" "${FOLDER}" )

echo "Built ${FOLDER}.zip (${MOD_NAME} ${VERSION})" >&2
echo "${ZIP_PATH}"
