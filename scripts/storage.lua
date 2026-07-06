-- =============================================================================
-- Quick Mall — scripts/storage.lua
-- =============================================================================
-- Persistent-state helpers (Factorio 1.1 `global` / 2.0 `storage`). No deps.
-- =============================================================================

-- === Storage / global state ===

-- Returns the mod's persistent root table, creating its `quick_mall.options`
-- substructure (per-player options keyed by player index). Uses `storage` on
-- 2.0 and `global` on 1.1; returns nil if neither exists.
local function get_storage_root()
  -- Factorio 2.0 uses 'storage', 1.1 uses 'global'
  local root = nil
  if storage then
    root = storage
  elseif global then
    root = global
  end

  if not root then
    return nil
  end

  root.quick_mall = root.quick_mall or {}
  root.quick_mall.options = root.quick_mall.options or {}
  return root.quick_mall
end

-- Ensures the storage root/substructure exists (side-effect of get_storage_root).
local function ensure_global()
  get_storage_root()
end

return {
  get_storage_root = get_storage_root,
  ensure_global = ensure_global,
}
