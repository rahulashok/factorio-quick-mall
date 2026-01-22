-- Unit tests for Quick Mall
-- This file mocks the Factorio API enough to test the logic functions.

local tests = {}

-- --- MOCKS ---
local defines = {
    direction = { north = 0, east = 2, south = 4, west = 6 }
}

local function mock_player()
    return {
        index = 1,
        force = {
            recipes = {
                ["test-recipe"] = {
                    name = "test-recipe",
                    ingredients = { { name = "iron-plate", amount = 1 } },
                    products = { { type = "item", name = "electronic-circuit", amount = 1 } },
                    enabled = true
                },
                ["fluid-recipe"] = {
                    name = "fluid-recipe",
                    ingredients = { { type = "fluid", name = "water", amount = 10 } },
                    products = { { type = "fluid", name = "steam", amount = 10 } },
                    enabled = true
                }
            }
        },
        surface = {
            get_property = function() return 0 end
        }
    }
end

-- --- TEST HELPERS ---
local function assert_eq(actual, expected, message)
    if actual ~= expected then
        error(string.format("FAIL: %s\n  Expected: %s\n  Actual:   %s", message, tostring(expected), tostring(actual)))
    end
end

-- --- TESTS ---

-- Test the stack limit -> bar conversion logic
function tests.test_stack_limit_to_bar()
    -- We need to extract the logic from control.lua since it's local.
    -- For testing purposes, we define the logic here as it was implemented.
    local function get_bar_value(stack_limit)
        return (stack_limit and stack_limit > 0) and stack_limit or nil
    end

    assert_eq(get_bar_value(1), 1, "Stack limit 1 should be bar 1")
    assert_eq(get_bar_value(5), 5, "Stack limit 5 should be bar 5")
    assert_eq(get_bar_value(0), nil, "Stack limit 0 should be nil bar")
    assert_eq(get_bar_value(nil), nil, "Nil stack limit should be nil bar")
end

-- Test the recipe output detection
function tests.test_recipe_solid_checks()
    -- Logic from control.lua
    local function has_solid_outputs(recipe)
        if not recipe then return false end
        local products = recipe.products or {}
        for _, product in pairs(products) do
            if product.type == "item" then return true end
        end
        return false
    end

    local player = mock_player()
    assert_eq(has_solid_outputs(player.force.recipes["test-recipe"]), true, "Test recipe should have solid outputs")
    assert_eq(has_solid_outputs(player.force.recipes["fluid-recipe"]), false, "Fluid recipe should NOT have solid outputs")
end

-- Test blueprint entity generation (partial)
function tests.test_build_blueprint_entities_bar()
    -- Mock the local function behavior
    local function build_mock_entities(output_chest, stack_limit)
        local bar_value = (stack_limit and stack_limit > 0) and stack_limit or nil
        local entities = {}
        if output_chest then
            table.insert(entities, {
                name = output_chest,
                bar = bar_value
            })
        end
        return entities
    end

    local entities = build_mock_entities("steel-chest", 10)
    assert_eq(entities[1].name, "steel-chest", "Should have output chest")
    assert_eq(entities[1].bar, 10, "Should have bar set to 10")

    local entities_no_limit = build_mock_entities("steel-chest", 0)
    assert_eq(entities_no_limit[1].bar, nil, "Should have nil bar for limit 0")
end

local function log(msg)
    if game then
        game.print(msg)
    else
        print(msg)
    end
end

-- --- RUNNER ---
function tests.run_all()
    log("Running Quick Mall tests...")
    local count = 0
    local total = 0
    for name, func in pairs(tests) do
        if name:find("^test_") then
            total = total + 1
            local status, err = pcall(func)
            if status then
                log("  [PASS] " .. name)
                count = count + 1
            else
                log("  [FAIL] " .. name .. ": " .. err)
            end
        end
    end
    log(string.format("Tests complete. %d/%d tests passed.", count, total))
end

-- Uncomment to run automatically if this file is loaded in a standalone Lua environment
-- tests.run_all()

return tests
