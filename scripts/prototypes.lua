-- =============================================================================
-- Quick Mall — scripts/prototypes.lua
-- =============================================================================
-- Prototype-resolution helpers (Factorio 1.1 / 2.0 compatible), option-list
-- builders, and the module-local candidate-building memo cache.
-- =============================================================================

-- Read-only derived cache of candidate crafting buildings (placeable + has
-- crafting_categories + not hidden + not recycler). This depends only on the
-- entity prototypes, NOT on the selected item, so it is computed once and
-- memoized here. It must NEVER be stored in `storage`/`global` (not part of the
-- save file). It is invalidated on init/configuration changes.
local building_candidates_cache = nil

-- === Prototype resolution helpers (1.1 / 2.0 compatible) ===

-- Returns the table of all entity prototypes (keyed by name), trying the
-- standard game API, then the 2.0 `prototypes.entity` global, then a filtered
-- query. Returns {} if none is available.
local function get_entity_prototypes()
  -- Factorio 1.1/2.0 Standard API
  local ok, res = pcall(function()
    return game.entity_prototypes
  end)
  if ok and res then
    return res
  end

  -- Fallback to Factorio 2.0+ global if available
  if prototypes and prototypes.entity then
    return prototypes.entity
  end

  ok, res = pcall(function()
    if game.get_filtered_entity_prototypes then
      return game.get_filtered_entity_prototypes({})
    end
    return nil
  end)
  if ok and res then
    return res
  end

  return {}
end

-- Resolves a single entity prototype by name, or nil if unknown/unavailable.
-- Tries the direct getter, then the 2.0 global, then the full-table lookup.
local function resolve_entity_prototype(entity_name)
  if not entity_name then return nil end

  -- Factorio 1.1/2.0 Standard API
  local ok, proto = pcall(function()
    if game.get_entity_prototype then
      return game.get_entity_prototype(entity_name)
    end
    return nil
  end)
  if ok and proto then
    return proto
  end

  -- Fallback to Factorio 2.0+ global if available
  if prototypes and prototypes.entity then
    return prototypes.entity[entity_name]
  end

  local prototypes_list = get_entity_prototypes()
  if prototypes_list then
    return prototypes_list[entity_name]
  end

  return nil
end

-- Returns the table of all item prototypes (keyed by name), or {} if none is
-- available. Same version-fallback approach as get_entity_prototypes.
local function get_item_prototypes()
  -- Factorio 1.1/2.0 Standard API
  local ok, res = pcall(function()
    return game.item_prototypes
  end)
  if ok and res then
    return res
  end

  -- Fallback to Factorio 2.0+ global if available
  if prototypes and prototypes.item then
    return prototypes.item
  end

  return {}
end

-- Resolves a single item prototype by name, or nil if unknown/unavailable.
local function resolve_item_prototype(item_name)
  if not item_name then return nil end

  -- Factorio 1.1/2.0 Standard API
  local ok, proto = pcall(function()
    if game.get_item_prototype then
      return game.get_item_prototype(item_name)
    end
    return nil
  end)
  if ok and proto then
    return proto
  end

  -- Fallback to Factorio 2.0+ global if available
  if prototypes and prototypes.item then
    return prototypes.item[item_name]
  end

  local prototypes_list = get_item_prototypes()
  if prototypes_list then
    return prototypes_list[item_name]
  end

  return nil
end

-- True when prototype lookups appear to be working (probes the vanilla
-- "inserter"). Used to decide whether option lists can be filtered confidently.
local function can_resolve_prototypes()
  return resolve_entity_prototype("inserter") ~= nil
end

-- Returns the first resolvable prototype name for a candidate: its `name`, else
-- one of its `aliases`, else nil. Lets a candidate map to whichever naming the
-- current game/mods use.
local function resolve_candidate_name(candidate)
  if resolve_entity_prototype(candidate.name) then
    return candidate.name
  end
  if candidate.aliases then
    for _, alias in ipairs(candidate.aliases) do
      if resolve_entity_prototype(alias) then
        return alias
      end
    end
  end
  return nil
end

-- === Option-list builders ===

-- Turns a candidate table into a { names, labels, uncertain } option list for
-- the GUI. When prototypes resolve, keeps only candidates that actually exist
-- (mapped through aliases); otherwise falls back to listing all candidates and
-- flags `uncertain = true`. Guarantees at least one entry.
local function build_option_list(candidates)
  local names = {}
  local labels = {}
  local can_resolve = can_resolve_prototypes()
  local uncertain = false

  if not can_resolve then
    for _, option in ipairs(candidates) do
      table.insert(names, option.name)
      table.insert(labels, option.label)
    end
    uncertain = true
  else
    for _, option in ipairs(candidates) do
      local resolved = resolve_candidate_name(option)
      if resolved then
        table.insert(names, resolved)
        table.insert(labels, option.label)
      end
    end
  end

  if #names == 0 then
    for _, option in ipairs(candidates) do
      table.insert(names, option.name)
      table.insert(labels, option.label)
    end
    uncertain = true
  end

  if #names == 0 then
    return { names = { nil }, labels = { "Unavailable" }, uncertain = true }
  end

  return { names = names, labels = labels, uncertain = uncertain }
end

-- === Misc GUI / recipe helpers ===

-- Returns an entity's localised_name (for tooltips), falling back to the raw
-- name when the prototype cannot be resolved.
local function get_localised_entity_name(entity_name)
  local prototype = resolve_entity_prototype(entity_name)
  return prototype and prototype.localised_name or entity_name
end

-- === Candidate building option builder ===

-- Build (once) and memoize the set of "candidate crafting buildings". This scan
-- (placeable + has crafting_categories + not hidden + not recycler) does NOT
-- depend on the selected item, so it is safe to compute a single time and reuse
-- across item changes. Only the per-item recipe-category filter varies.
-- The cache is invalidated on init/configuration changes.
local function get_candidate_buildings()
  if building_candidates_cache then
    return building_candidates_cache
  end

  local candidates = {}
  local entity_prototypes = get_entity_prototypes()

  if entity_prototypes then
    for name, prototype in pairs(entity_prototypes) do
      local is_valid = false
      pcall(function()
        local placeable = prototype.items_to_place_this and #prototype.items_to_place_this > 0
        local has_categories = prototype.crafting_categories and next(prototype.crafting_categories) ~= nil

        local is_hidden = false
        pcall(function()
          if prototype.has_flag("hidden") then
            is_hidden = true
          end
        end)

        if placeable and has_categories and not is_hidden then
          is_valid = true
        end
      end)

      if is_valid then
        -- Exclude recyclers and other non-production buildings
        if name:find("recycler", 1, true) then
          is_valid = false
        end
      end

      if is_valid then
        table.insert(candidates, {
          name = name,
          label = prototype.localised_name or name,
          order = prototype.order or "z",
          -- Reference to the prototype's crafting_categories table (used as a
          -- set: categories[recipe.category]) so the per-item filter can test
          -- categories without re-reading the prototype.
          crafting_categories = prototype.crafting_categories or {},
        })
      end
    end
  end

  building_candidates_cache = candidates
  return candidates
end

-- Returns the building's footprint as (tile_width, tile_height), using the
-- prototype's tile size when present, else deriving it from the selection or
-- collision box; defaults to 1x1. Used to place chests/inserters clear of the
-- building.
local function get_entity_tile_size(prototype)
  if prototype.tile_width and prototype.tile_height then
    return prototype.tile_width, prototype.tile_height
  end

  local box = prototype.selection_box or prototype.collision_box
  if not box then
    return 1, 1
  end

  local width = box.right_bottom.x - box.left_top.x
  local height = box.right_bottom.y - box.left_top.y
  return math.ceil(width), math.ceil(height)
end

-- Invalidates the derived candidate-building memo (module local, never saved).
-- Called from control.lua's init / configuration / research event handlers.
local function invalidate_candidate_cache()
  building_candidates_cache = nil
end

return {
  get_entity_prototypes = get_entity_prototypes,
  resolve_entity_prototype = resolve_entity_prototype,
  get_item_prototypes = get_item_prototypes,
  resolve_item_prototype = resolve_item_prototype,
  can_resolve_prototypes = can_resolve_prototypes,
  resolve_candidate_name = resolve_candidate_name,
  build_option_list = build_option_list,
  get_localised_entity_name = get_localised_entity_name,
  get_candidate_buildings = get_candidate_buildings,
  get_entity_tile_size = get_entity_tile_size,
  invalidate_candidate_cache = invalidate_candidate_cache,
}
