-- =============================================================================
-- Quick Mall — FactorioTest in-game test spec
-- =============================================================================
--
-- Unlike the legacy tests.lua harness (which re-implemented logic inline against
-- mocks and therefore exercised NONE of the shipped code), this spec runs inside
-- a real Factorio instance under the `factorio-test` framework and calls the
-- ACTUAL scripts/* modules. It is loaded from control.lua via
--   require("__factorio-test__/init")({ "tests.qm-blueprint-tests" }, {})
-- only when the optional factorio-test mod is active.
--
-- API: `describe`/`it`/`test` and `assert` (luassert) are globals injected by
-- factorio-test. `game`, `defines`, and `require` resolve as normal in-game.
--
-- Coverage note: Factorio has no in-VM line-coverage tool, so we track FUNCTIONAL
-- coverage — each real module function below is genuinely invoked. See
-- docs/workitems/13-automated-test-schedule.md and docs/test-results/latest.md.
-- =============================================================================

local recipes = require("scripts.recipes")
local blueprint = require("scripts.blueprint")

-- A recipe that produces a solid item (electronic-circuit) from a solid
-- ingredient (iron-plate) — present in base Factorio.
local SOLID_RECIPE = "electronic-circuit"
-- A recipe with no solid outputs — pick one whose products are all fluids.
-- "light-oil-cracking" outputs only light-oil/petroleum-gas (fluids) in base.
local FLUID_RECIPE = "light-oil-cracking"

describe("recipes module (real source)", function()
  it("has_solid_outputs is true for an item-producing recipe", function()
    local recipe = game.forces.player.recipes[SOLID_RECIPE]
    assert.is_truthy(recipe)
    assert.is_true(recipes.has_solid_outputs(recipe))
  end)

  it("has_solid_outputs is false for a fluid-only recipe", function()
    local recipe = game.forces.player.recipes[FLUID_RECIPE]
    if recipe then
      assert.is_false(recipes.has_solid_outputs(recipe))
    end
  end)

  it("has_solid_inputs is true for a recipe with an item ingredient", function()
    local recipe = game.forces.player.recipes[SOLID_RECIPE]
    assert.is_true(recipes.has_solid_inputs(recipe))
  end)

  it("has_solid_outputs / has_solid_inputs are false for nil", function()
    assert.is_false(recipes.has_solid_outputs(nil))
    assert.is_false(recipes.has_solid_inputs(nil))
  end)

  it("get_recipes_for_item returns only enabled recipes producing the item", function()
    -- On a fresh save electronic-circuit is not yet researched (enabled=false),
    -- and get_recipes_for_item filters disabled recipes out — assert that first,
    -- then enable it and confirm it now appears. Returns recipe OBJECTS, not names.
    local force = game.forces.player
    local before = recipes.get_recipes_for_item(force, "electronic-circuit")
    local function contains(list, name)
      for _, recipe in pairs(list) do
        if recipe.name == name then return true end
      end
      return false
    end
    if not force.recipes[SOLID_RECIPE].enabled then
      assert.is_false(contains(before, SOLID_RECIPE))
    end

    force.recipes[SOLID_RECIPE].enabled = true
    local after = recipes.get_recipes_for_item(force, "electronic-circuit")
    assert.is_true(contains(after, SOLID_RECIPE))
  end)
end)

describe("module restrictions (real source)", function()
  -- Resolve item prototypes the same way the mod does (game.item_prototypes with
  -- a fallback to the 2.0 prototypes.item global).
  local function item_prototypes()
    local ok, res = pcall(function() return game.item_prototypes end)
    if ok and res then return res end
    if prototypes and prototypes.item then return prototypes.item end
    return {}
  end

  -- Find a real module item whose module_effects include "productivity".
  local function find_productivity_module()
    for name, proto in pairs(item_prototypes()) do
      local effects
      pcall(function() effects = proto.module_effects end)
      if effects then
        for effect_name in pairs(effects) do
          if effect_name == "productivity" then
            return proto
          end
        end
      end
      -- Fallback: name-based heuristic if module_effects unreadable.
      if not effects and type(name) == "string" and name:find("productivity%-module") then
        return proto
      end
    end
    return nil
  end

  local function entity_prototypes()
    local ok, res = pcall(function() return game.entity_prototypes end)
    if ok and res then return res end
    if prototypes and prototypes.entity then return prototypes.entity end
    return {}
  end

  -- An assembling machine (or any crafting machine) with >0 module slots.
  local function find_assembler_with_slots()
    local all = entity_prototypes()
    for _, candidate in ipairs({ "assembling-machine-3", "assembling-machine-2" }) do
      local proto = all[candidate]
      if proto and recipes.get_module_slot_count(proto) > 0 then
        return proto
      end
    end
    -- Generic scan as a fallback.
    for _, proto in pairs(all) do
      if recipes.get_module_slot_count(proto) > 0 then
        return proto
      end
    end
    return nil
  end

  -- Does a recipe (LuaRecipe) permit the productivity effect? Reads static data
  -- from recipe.prototype.allowed_effects (fallback recipe.allowed_effects).
  local function recipe_permits_productivity(recipe)
    if not recipe then return nil end
    local allowed
    pcall(function() allowed = recipe.prototype.allowed_effects end)
    if allowed == nil then
      pcall(function() allowed = recipe.allowed_effects end)
    end
    if allowed == nil or next(allowed) == nil then
      -- No restriction expressed => productivity is permitted.
      return true
    end
    return allowed.productivity == true
  end

  it("productivity module rejected on forbidding recipe, allowed on intermediate", function()
    local force = game.forces.player
    local prod_module = find_productivity_module()
    if not prod_module then
      log("SKIP module-restriction test: no productivity module in prototypes")
      return
    end
    local assembler = find_assembler_with_slots()
    if not assembler then
      log("SKIP module-restriction test: no assembler with module slots")
      return
    end

    -- Verify at runtime which recipe forbids vs permits productivity, rather
    -- than assuming, so the assertion is meaningful.
    local forbidden_recipe, allowed_recipe
    for _, name in ipairs({ "inserter", "transport-belt" }) do
      local r = force.recipes[name]
      if r and recipe_permits_productivity(r) == false then
        forbidden_recipe = r
        break
      end
    end
    for _, name in ipairs({ "electronic-circuit", "iron-gear-wheel" }) do
      local r = force.recipes[name]
      if r and recipe_permits_productivity(r) == true then
        allowed_recipe = r
        break
      end
    end

    if not forbidden_recipe then
      log("SKIP module-restriction test: no end-product recipe forbidding productivity found")
      return
    end
    if not allowed_recipe then
      log("SKIP module-restriction test: no intermediate recipe permitting productivity found")
      return
    end

    assert.is_false(recipes.is_module_allowed(prod_module, assembler, forbidden_recipe))
    assert.is_true(recipes.is_module_allowed(prod_module, assembler, allowed_recipe))
  end)
end)

describe("blueprint module (real source)", function()
  -- Drives build_blueprint_entities exactly as handle_create_click does, then
  -- inspects the returned entity table (no game surface mutation required).
  local base = { x = 0, y = 0 }
  local request_list = { { name = "iron-plate", count = 100 } }

  it("builds building + input chest/inserter + output chest/inserter", function()
    local entities = blueprint.build_blueprint_entities(
      base,
      "assembling-machine-2",
      SOLID_RECIPE,
      "logistic-chest-requester", -- input chest
      "logistic-chest-passive-provider", -- output chest
      "fast-inserter",
      2, -- chest_offset
      1, -- inserter_offset
      request_list,
      "normal",
      0 -- stack_limit (0 = no bar)
    )
    -- building + input chest + input inserter + output chest + output inserter
    assert.equals(5, #entities)

    local building = entities[1]
    assert.equals("assembling-machine-2", building.name)
    assert.equals(SOLID_RECIPE, building.recipe)
    assert.equals(SOLID_RECIPE, building.tags.quick_mall_recipe)
    assert.equals("normal", building.tags.quick_mall_recipe_quality)
  end)

  it("stack_limit > 0 sets the output chest bar; 0 leaves it nil", function()
    local with_bar = blueprint.build_blueprint_entities(
      base, "assembling-machine-2", SOLID_RECIPE,
      nil, "logistic-chest-passive-provider", "fast-inserter",
      2, 1, {}, "normal", 10
    )
    -- With no input chest (empty request list), only output chest + inserter.
    local output_chest
    for _, e in pairs(with_bar) do
      if e.name == "logistic-chest-passive-provider" then output_chest = e end
    end
    assert.is_truthy(output_chest)
    assert.equals(10, output_chest.bar)

    local no_bar = blueprint.build_blueprint_entities(
      base, "assembling-machine-2", SOLID_RECIPE,
      nil, "logistic-chest-passive-provider", "fast-inserter",
      2, 1, {}, "normal", 0
    )
    for _, e in pairs(no_bar) do
      if e.name == "logistic-chest-passive-provider" then
        assert.is_nil(e.bar)
      end
    end
  end)

  it("get_item_requests returns solid ingredients for a recipe", function()
    local recipe = game.forces.player.recipes[SOLID_RECIPE]
    local reqs = blueprint.get_item_requests(game.forces.player, recipe, "normal")
    assert.is_truthy(reqs)
    -- electronic-circuit needs iron-plate + copper-cable (both solid).
    assert.is_true(#reqs >= 1)
  end)

  -- workitem-15: a per-slot module at a NON-normal quality must thread that quality
  -- through to both the building's logistic request_filters AND the items insert-plan.
  it("per-slot module quality flows into request_filters + items id", function()
    -- Discover a real quality prototype whose name is not "normal". If the base
    -- install has none (quality mod disabled), skip gracefully.
    local function find_non_normal_quality()
      local sources = {}
      pcall(function() if prototypes and prototypes.quality then sources[#sources + 1] = prototypes.quality end end)
      pcall(function() if game and game.quality_prototypes then sources[#sources + 1] = game.quality_prototypes end end)
      for _, src in ipairs(sources) do
        for name in pairs(src) do
          if type(name) == "string" and name ~= "normal" then
            return name
          end
        end
      end
      return nil
    end

    -- Discover a real module item, same approach as the module-restriction test.
    local function item_prototypes()
      local ok, res = pcall(function() return game.item_prototypes end)
      if ok and res then return res end
      if prototypes and prototypes.item then return prototypes.item end
      return {}
    end
    local function find_module()
      for name, proto in pairs(item_prototypes()) do
        local effects
        pcall(function() effects = proto.module_effects end)
        if effects and next(effects) then return name end
        if type(name) == "string" and name:find("%-module") then return name end
      end
      return nil
    end

    -- A building with module slots, discovered via the real recipes module.
    local function entity_prototypes()
      local ok, res = pcall(function() return game.entity_prototypes end)
      if ok and res then return res end
      if prototypes and prototypes.entity then return prototypes.entity end
      return {}
    end
    local function find_building_with_slots()
      local all = entity_prototypes()
      for _, candidate in ipairs({ "assembling-machine-3", "assembling-machine-2" }) do
        local proto = all[candidate]
        if proto and recipes.get_module_slot_count(proto) > 0 then
          return candidate
        end
      end
      return nil
    end

    local quality = find_non_normal_quality()
    if not quality then
      log("SKIP module-quality test: no non-normal quality prototype in this install")
      return
    end
    local module_name = find_module()
    if not module_name then
      log("SKIP module-quality test: no module item found")
      return
    end
    local building_name = find_building_with_slots()
    if not building_name then
      log("SKIP module-quality test: no building with module slots")
      return
    end

    local entities = blueprint.build_blueprint_entities(
      base,
      building_name,
      SOLID_RECIPE,
      nil, nil, "fast-inserter",
      2, 1,
      {}, -- empty request list
      "normal",
      0,
      { { name = module_name, quality = quality } } -- one non-normal-quality module in slot 1
    )

    local building = entities[1]
    assert.equals(building_name, building.name)

    -- (a) request_filters carries the chosen quality for the module.
    assert.is_truthy(building.request_filters)
    local filters = building.request_filters.sections[1].filters
    local filter_match
    for _, f in pairs(filters) do
      if f.name == module_name and f.quality == quality then
        filter_match = f
      end
    end
    assert.is_truthy(filter_match)
    assert.equals(quality, filter_match.quality)

    -- (b) items insert-plan id carries the chosen quality (guarded: only present
    -- when defines.inventory.assembling_machine_modules resolved).
    if building.items then
      local item_match
      for _, entry in pairs(building.items) do
        if entry.id and entry.id.name == module_name and entry.id.quality == quality then
          item_match = entry
        end
      end
      assert.is_truthy(item_match)
      assert.equals(quality, item_match.id.quality)
    else
      log("NOTE module-quality test: building.items absent (module inventory constant unresolved)")
    end
  end)
end)
