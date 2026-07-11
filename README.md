# Quick Mall

Quick Mall places a small, configurable ghost build: an assembler plus input/output
logistic chests and inserters. Use the shortcut (or `Ctrl+Q`) to open the menu,
select the item and preferred building/chest/inserter types, then place ghosts
near your character.

## How it works
- The input chest requests 1 full stack of each ingredient.
- The assembler ghost stores the chosen recipe and applies it when built.
- The output chest is placed as the selected provider type.
- Supports quality selection for the target item's ingredients (requires Space Age or a quality mod).

## Controls
- `Ctrl+Q`: Open Quick Mall
- Shortcut bar icon: Open Quick Mall

## Releasing

Releases are automated by GitHub Actions (`.github/workflows/release.yml`).

One-time setup: create a **"ModPortal: Upload Mods"** API key at
https://factorio.com/create-api-key and add it as the repository secret
`FACTORIO_TOKEN` (Settings → Secrets and variables → Actions). The key lives only
on GitHub — never locally.

To cut a release:
1. Update `version` in `info.json` and add a matching entry at the top of
   `changelog.txt`.
2. Commit, then push a tag matching that version, e.g. `git tag v1.2.0 && git push origin v1.2.0`.
3. The workflow verifies the tag matches `info.json`, builds `quick-mall_<version>.zip`
   (via `scripts/build_release.sh`), and uploads it to the mod portal.

To inspect the exact release artifact locally without publishing, run
`scripts/build_release.sh` and check it with `unzip -l quick-mall_<version>.zip`.
