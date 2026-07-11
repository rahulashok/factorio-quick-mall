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
end)
