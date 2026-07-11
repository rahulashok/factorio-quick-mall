#!/usr/bin/env bash
# =============================================================================
# Quick Mall — link the working tree into the Factorio mods directory
# =============================================================================
# Symlinks this repo into Factorio's mods dir so the game loads the live working
# tree directly — no copy-pasting. Idempotent: safe to re-run. Replaces a stale
# copied folder or a wrong symlink with the correct one.
#
# After running: restart Factorio to pick up control.lua / data.lua changes.
#
# Usage:  scripts/link_mod.sh          # create/repair the symlink
#         scripts/link_mod.sh --unlink # remove the symlink
#
# The mod folder is named just "quick-mall" (no version): Factorio accepts an
# unpacked folder named {mod-name} or {mod-name}_{version}, and reads the real
# name/version from info.json — so the link never goes stale on version bumps.
# =============================================================================
set -euo pipefail

# Repo root = parent of this script's directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Factorio mods dir (macOS default). Override with FACTORIO_MODS_DIR if needed.
MODS_DIR="${FACTORIO_MODS_DIR:-${HOME}/Library/Application Support/factorio/mods}"

# Mod name from info.json (fallback to "quick-mall" if jq/python unavailable).
MOD_NAME="$(python3 -c "import json;print(json.load(open('${REPO_ROOT}/info.json'))['name'])" 2>/dev/null || echo "quick-mall")"
LINK_PATH="${MODS_DIR}/${MOD_NAME}"

if [ ! -d "${MODS_DIR}" ]; then
  echo "Error: Factorio mods dir not found: ${MODS_DIR}" >&2
  echo "       Set FACTORIO_MODS_DIR to the correct path and re-run." >&2
  exit 1
fi

# --unlink: remove the symlink (only if it IS a symlink) and exit.
if [ "${1:-}" = "--unlink" ]; then
  if [ -L "${LINK_PATH}" ]; then
    rm "${LINK_PATH}"
    echo "Removed symlink: ${LINK_PATH}"
  else
    echo "Nothing to unlink (no symlink at ${LINK_PATH})."
  fi
  exit 0
fi

# If a symlink already points at this repo, we're done.
if [ -L "${LINK_PATH}" ] && [ "$(readlink "${LINK_PATH}")" = "${REPO_ROOT}" ]; then
  echo "Already linked: ${LINK_PATH} -> ${REPO_ROOT}"
  exit 0
fi

# Remove a stale symlink (wrong target) — safe, it's just a link.
if [ -L "${LINK_PATH}" ]; then
  echo "Replacing stale symlink: ${LINK_PATH} -> $(readlink "${LINK_PATH}")"
  rm "${LINK_PATH}"
fi

# A REAL directory/file here is likely a manual copy. Don't delete silently —
# make the user confirm, since we can't be sure it isn't unsaved work.
if [ -e "${LINK_PATH}" ]; then
  echo "Error: ${LINK_PATH} exists and is not a symlink (a real copy?)." >&2
  echo "       Remove it yourself, then re-run:  rm -rf \"${LINK_PATH}\"" >&2
  exit 1
fi

ln -s "${REPO_ROOT}" "${LINK_PATH}"
echo "Linked: ${LINK_PATH} -> ${REPO_ROOT}"
echo "Restart Factorio to load the mod from the working tree."
