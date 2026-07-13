-- =============================================================================
-- Quick Mall — scripts/recipes.lua
-- =============================================================================
-- Recipe filtering, surface compatibility, and building/recipe option builders.
-- Depends on: prototypes (resolve_entity_prototype, get_candidate_buildings) and
-- constants (STATIC_BUILDING_CANDIDATES).
-- =============================================================================

local constants = require("scripts.constants")
local prototypes = require("scripts.prototypes")

-- Local aliases to cross-module helpers so the moved function bodies stay
-- byte-identical to their control.lua originals.
local resolve_entity_prototype = prototypes.resolve_entity_prototype
local get_item_prototypes = prototypes.get_item_prototypes
local get_candidate_buildings = prototypes.get_candidate_buildings
local STATIC_BUILDING_CANDIDATES = constants.STATIC_BUILDING_CANDIDATES

-- Derived, module-local memo of every module-type item prototype (name -> proto).
-- Like the candidate-building cache in prototypes.lua this depends only on the
-- item prototypes, NOT on the force/recipe/building, so it is computed once and
-- reused. It is NEVER stored in the save file. Invalidated on the same
-- init/configuration/research events as the building cache (see
-- invalidate_module_cache, wired from control.lua).
local module_item_cache = nil

-- True if the recipe has at least one solid (item, not fluid) ingredient.
-- Handles both the named-field and positional ingredient shapes.
local function has_solid_inputs(recipe)
  if not recipe then return false end
  for _, ingredient in pairs(recipe.ingredients or {}) do
    local name = ingredient.name or ingredient[1]
    local ingredient_type = ingredient.type or "item"
    if ingredient_type == "item" and name then
      return true
    end
  end
  return false
end

-- True if the recipe produces at least one solid (item) product.
local function has_solid_outputs(recipe)
  if not recipe then return false end
  local products = recipe.products or {}
  for _, product in pairs(products) do
    if product.type == "item" then
      return true
    end
  end
  return false
end

-- === Recipe filtering & surface compatibility ===

-- True if the recipe can be crafted on the given surface. Checks the recipe
-- prototype's surface_conditions (2.0 planet properties) against the surface's
-- properties; treats a missing property as 0. Recipes with no conditions (or
-- when recipe/surface is nil) are considered compatible.
local function is_recipe_compatible_with_surface(recipe, surface)
  if not (recipe and surface) then return true end

  local proto = recipe.prototype
  if not proto then return true end

  local conditions = proto.surface_conditions
  if not conditions or #conditions == 0 then return true end

  for _, condition in ipairs(conditions) do
    local property_value = surface.get_property(condition.property)

    if property_value == nil then
      -- If the surface doesn't define the property, we treat it as 0
      -- but only if that's valid for the condition.
      property_value = 0
    end

    if condition.min and property_value < condition.min then
      return false
    end
    if condition.max and property_value > condition.max then
      return false
    end
  end

  return true
end

-- Returns a list of recipe objects that are enabled for the force, compatible
-- with the surface, and produce the given item. `item_name` may be a plain name
-- or a signal/table with a `.name` field.
local function get_recipes_for_item(force, item_name, surface)
  local name_to_check = item_name
  if type(item_name) == "table" then
    name_to_check = item_name.name
  end
  if not name_to_check then return {} end

  local results = {}
  for _, recipe in pairs(force.recipes) do
    if recipe.enabled and is_recipe_compatible_with_surface(recipe, surface) then
      for _, product in pairs(recipe.products or {}) do
        if product.name == name_to_check then
          table.insert(results, recipe)
          break
        end
      end
    end
  end
  return results
end

-- Picks a single recipe producing the item. With no building prototype, returns
-- the first valid recipe; otherwise returns the first whose category the building
-- can craft. Returns nil if none qualify.
local function find_recipe_for_item(force, item_name, building_prototype, surface)
  local valid_recipes = get_recipes_for_item(force, item_name, surface)
  if #valid_recipes == 0 then return nil end

  if not building_prototype then return valid_recipes[1] end

  local categories = building_prototype.crafting_categories or {}
  for _, recipe in ipairs(valid_recipes) do
    if categories[recipe.category] then
      return recipe
    end
  end

  return nil
end

-- === Candidate building / recipe option builders ===

-- Builds the { names, labels } list of buildings that can craft `item_name` on
-- the surface. Pre-filters the item's recipes once, then keeps candidate
-- buildings whose crafting_categories cover any of those recipes; falls back to
-- STATIC_BUILDING_CANDIDATES if nothing matched. Result is sorted by prototype
-- order. Returns a single {nil} entry when there are no options.
local function build_building_options(player, force, item_name, surface)
  local name_to_check = item_name
  if type(item_name) == "table" then
    name_to_check = item_name.name
  end

  -- OPTIMIZATION: Find valid recipes for this item FIRST
  local valid_recipes = {}
  if name_to_check then
    valid_recipes = get_recipes_for_item(force, name_to_check, surface)
    if #valid_recipes == 0 then
      return { names = { nil }, labels = { "No options found for this surface" } }
    end
  end

  local candidates = get_candidate_buildings()
  local entries = {}
  local found_names = {}

  for _, candidate in ipairs(candidates) do
    local building_can_craft = false
    if not name_to_check then
      building_can_craft = true
    else
      -- EXTREMELY FAST CHECK: Does this building support ANY of the pre-filtered recipes?
      local building_categories = candidate.crafting_categories or {}
      for _, recipe in ipairs(valid_recipes) do
        if building_categories[recipe.category] then
          building_can_craft = true
          break
        end
      end
    end

    if building_can_craft then
      table.insert(entries, {
        name = candidate.name,
        label = candidate.label,
        order = candidate.order
      })
      found_names[candidate.name] = true
    end
  end

  if #entries == 0 then
    for _, option in ipairs(STATIC_BUILDING_CANDIDATES) do
      if not found_names[option.name] then
        local prototype = resolve_entity_prototype(option.name)
        if prototype then
          local building_can_craft = false
          if not name_to_check then
            building_can_craft = true
          else
            local building_categories = prototype.crafting_categories or {}
            for _, recipe in ipairs(valid_recipes) do
              if building_categories[recipe.category] then
                building_can_craft = true
                break
              end
            end
          end

          if building_can_craft then
            table.insert(entries, {
              name = option.name,
              label = prototype.localised_name or option.name,
              order = prototype.order or "z"
            })
            found_names[option.name] = true
          end
        end
      end
    end
  end

  table.sort(entries, function(a, b)
    return a.order < b.order
  end)

  local names = {}
  local labels = {}
  for _, entry in ipairs(entries) do
    table.insert(names, entry.name)
    table.insert(labels, entry.label)
  end

  if #names == 0 then
    return { names = { nil }, labels = { "No options found for this surface" } }
  end

  return { names = names, labels = labels }
end

-- True if the recipe is enabled and lists item_name among its products.
local function recipe_outputs_item(recipe, item_name)
  if not recipe or not recipe.enabled then
    return false
  end

  for _, product in pairs(recipe.products or {}) do
    if product.name == item_name then
      return true
    end
  end

  return false
end

-- True if the building's crafting_categories include the recipe's category.
local function recipe_usable_in_building(recipe, building_prototype)
  if not (recipe and building_prototype) then
    return false
  end

  local categories = building_prototype.crafting_categories or {}
  return categories[recipe.category] == true
end

-- Builds the { names, labels } list of recipes producing `item_name` that the
-- named building can craft on the surface (names sorted, labels localised).
-- Returns a single {nil} entry when the item/building is missing or nothing
-- matches.
local function build_recipe_options(force, item_name, building_name, surface)
  local name_to_check = item_name
  if type(item_name) == "table" then
    name_to_check = item_name.name
  end

  if not (name_to_check and building_name) then
    return { names = { nil }, labels = { "No options found for this surface" } }
  end

  local building_prototype = resolve_entity_prototype(building_name)
  if not building_prototype then
    return { names = { nil }, labels = { "No options found for this surface" } }
  end

  -- OPTIMIZATION: reuse get_recipes_for_item (enabled + surface-compatible +
  -- outputs item) instead of re-scanning force.recipes from scratch. The set
  -- build_recipe_options needs is exactly that result further filtered by the
  -- building's crafting categories, so we only apply recipe_usable_in_building
  -- here. This removes one full force.recipes walk per GUI build/refresh.
  local names = {}
  for _, recipe in ipairs(get_recipes_for_item(force, name_to_check, surface)) do
    if recipe_usable_in_building(recipe, building_prototype) then
      table.insert(names, recipe.name)
    end
  end

  table.sort(names)

  if #names == 0 then
    return { names = { nil }, labels = { "No options found for this surface" } }
  end

  local labels = {}
  for _, recipe_name in ipairs(names) do
    local recipe = force.recipes[recipe_name]
    local localized = recipe
      and (recipe.localised_name or (recipe.prototype and recipe.prototype.localised_name) or recipe.name)
    table.insert(labels, localized or recipe_name)
  end

  return { names = names, labels = labels }
end

-- === Module support (workitem-14) ===

-- Returns the number of module slots on a building prototype (0 if none / not
-- resolvable). Access is pcall-guarded because module_inventory_size may be
-- absent on non-crafting prototypes.
local function get_module_slot_count(building_prototype)
  if not building_prototype then return 0 end
  local count = 0
  pcall(function()
    count = building_prototype.module_inventory_size or 0
  end)
  return count or 0
end

-- True if the module item is allowed in this building for this recipe. Rules:
--   1. If the module's `.limitations` recipe allow-list is non-empty, the recipe
--      MUST be in it (strict). Empty/nil = no recipe restriction.
--   2. If the building exposes `allowed_module_categories`, the module's
--      `.category` must be permitted (when both are known). If the building does
--      not expose it, allow.
--   3. If the building exposes `allowed_effects`, at least one of the module's
--      effects must be permitted (when determinable). If not determinable, allow.
-- All prototype fields are read via pcall; the default is permissive-but-safe
-- EXCEPT the non-empty limitations list, which is respected strictly.
local function is_module_allowed(module_item_prototype, building_prototype, recipe)
  if not module_item_prototype then return false end

  -- (1) recipe limitations (strict when present)
  local limitations = nil
  pcall(function()
    limitations = module_item_prototype.limitations
  end)
  if limitations and #limitations > 0 then
    if not (recipe and recipe.name) then
      return false
    end
    local ok = false
    for _, recipe_name in ipairs(limitations) do
      if recipe_name == recipe.name then
        ok = true
        break
      end
    end
    if not ok then
      return false
    end
  end

  if building_prototype then
    -- (2) module category allowed by the building
    local allowed_categories = nil
    pcall(function()
      allowed_categories = building_prototype.allowed_module_categories
    end)
    if allowed_categories and next(allowed_categories) ~= nil then
      local category = nil
      pcall(function()
        category = module_item_prototype.category
      end)
      if category and allowed_categories[category] ~= true then
        return false
      end
    end

    -- (3) module effects allowed by the building
    local allowed_effects = nil
    pcall(function()
      allowed_effects = building_prototype.allowed_effects
    end)
    if allowed_effects and next(allowed_effects) ~= nil then
      local effects = nil
      pcall(function()
        effects = module_item_prototype.module_effects
      end)
      if effects and next(effects) ~= nil then
        local any_allowed = false
        for effect_name, _ in pairs(effects) do
          if allowed_effects[effect_name] == true then
            any_allowed = true
            break
          end
        end
        if not any_allowed then
          return false
        end
      end
    end
  end

  return true
end

-- Discovers (once) and memoizes all module-type item prototypes. A prototype is
-- treated as a module when its type is "module" or it exposes a module category
-- / module_effects. The scan is pcall-guarded per prototype so a hostile modded
-- field cannot abort discovery.
local function get_module_item_prototypes()
  if module_item_cache then
    return module_item_cache
  end

  local modules = {}
  local item_prototypes = get_item_prototypes()
  if item_prototypes then
    for name, prototype in pairs(item_prototypes) do
      local is_module = false
      pcall(function()
        if prototype.type == "module" then
          is_module = true
        elseif prototype.category ~= nil or prototype.module_effects ~= nil then
          is_module = true
        end
      end)
      if is_module then
        modules[name] = prototype
      end
    end
  end

  module_item_cache = modules
  return modules
end

-- Returns the sorted list of module item names allowed for this building+recipe.
-- Buildings with 0 module slots return an empty list. Per-force unlocked state is
-- not reliably determinable for items, so all discovered modules passing
-- is_module_allowed are included (see report note).
local function get_allowed_modules(force, building_prototype, recipe)
  if get_module_slot_count(building_prototype) <= 0 then
    return {}
  end

  local names = {}
  for name, module_prototype in pairs(get_module_item_prototypes()) do
    if is_module_allowed(module_prototype, building_prototype, recipe) then
      table.insert(names, name)
    end
  end
  table.sort(names)
  return names
end

-- Invalidates the derived module-item memo (module local, never saved).
local function invalidate_module_cache()
  module_item_cache = nil
end

return {
  is_recipe_compatible_with_surface = is_recipe_compatible_with_surface,
  get_recipes_for_item = get_recipes_for_item,
  find_recipe_for_item = find_recipe_for_item,
  recipe_outputs_item = recipe_outputs_item,
  recipe_usable_in_building = recipe_usable_in_building,
  build_building_options = build_building_options,
  build_recipe_options = build_recipe_options,
  has_solid_inputs = has_solid_inputs,
  has_solid_outputs = has_solid_outputs,
  get_module_slot_count = get_module_slot_count,
  is_module_allowed = is_module_allowed,
  get_module_item_prototypes = get_module_item_prototypes,
  get_allowed_modules = get_allowed_modules,
  invalidate_module_cache = invalidate_module_cache,
}
