-- =============================================================================
-- Quick Mall — scripts/constants.lua
-- =============================================================================
-- GUI element name/prefix string constants and the static candidate option
-- tables. No dependencies.
-- =============================================================================

local GUI_ROOT = "quick-mall-window"
local GUI_ITEM = "quick-mall-item"
local GUI_RECIPE_FLOW = "quick-mall-recipe-flow"
local GUI_RECIPE_PREFIX = "quick-mall-recipe-"
local GUI_INPUT_CHEST = "quick-mall-input-chest"
local GUI_OUTPUT_CHEST = "quick-mall-output-chest"
local GUI_STACK_LIMIT = "quick-mall-stack-limit"
local GUI_STACK_LIMIT_FLOW = "quick-mall-stack-limit-flow"
local GUI_INSERTER = "quick-mall-inserter"
local GUI_BUILDING_FLOW = "quick-mall-building-flow"
local GUI_BUILDING_PREFIX = "quick-mall-building-"
local GUI_INSERTER_FLOW = "quick-mall-inserter-flow"
local GUI_INSERTER_PREFIX = "quick-mall-inserter-"
local GUI_INPUT_FLOW = "quick-mall-input-flow"
local GUI_INPUT_PREFIX = "quick-mall-input-"
local GUI_OUTPUT_FLOW = "quick-mall-output-flow"
local GUI_OUTPUT_PREFIX = "quick-mall-output-"
local GUI_QUALITY_WARNING = "quick-mall-quality-warning"
local GUI_CREATE = "quick-mall-create"
local GUI_CLOSE = "quick-mall-close"

-- Icon-row layout limits (workitem-10). Icon containers are `table`s that wrap
-- their sprite-buttons into rows of GUI_ICON_COLUMNS. When a row would need more
-- than GUI_MAX_INLINE_ROWS rows, the render_* helpers wrap the table in a bounded
-- scroll-pane (GUI_OVERFLOW_SCROLL_HEIGHT tall) so a very long list scrolls in
-- place instead of extending past the window edge.
local GUI_ICON_COLUMNS = 10
local GUI_MAX_INLINE_ROWS = 3
-- ~3 rows of 40px slot buttons plus inter-row spacing; the scroll-pane clamps the
-- table to this height and shows a vertical scrollbar past the inline limit.
local GUI_OVERFLOW_SCROLL_HEIGHT = 3 * 40 + 8

-- === Candidate option tables ===
-- Fallback/ordering hints. Each entry is { name, label, aliases? }. `name` is the
-- preferred prototype name; `aliases` list alternate prototype names to try when
-- `name` is not present (handles 1.1 vs 2.0 vs modded logistic-chest naming).

-- Fallback crafting buildings used only if the dynamic candidate scan finds none.
local STATIC_BUILDING_CANDIDATES = {
  { name = "assembling-machine-1", label = "Assembler 1" },
  { name = "assembling-machine-2", label = "Assembler 2" },
  { name = "assembling-machine-3", label = "Assembler 3" },
  { name = "chemical-plant", label = "Chemical Plant" },
  { name = "oil-refinery", label = "Oil Refinery" },
  { name = "foundry", label = "Foundry" },
  { name = "em-plant", label = "EM Plant" },
}

local INPUT_CHEST_CANDIDATES = {
  { name = "wooden-chest", label = "Wooden Chest" },
  { name = "iron-chest", label = "Iron Chest" },
  { name = "steel-chest", label = "Steel Chest" },
  {
    name = "logistic-chest-buffer",
    label = "Buffer Chest",
    aliases = { "buffer-chest", "logistic-buffer-chest" },
  },
  {
    name = "logistic-chest-requester",
    label = "Requester Chest",
    aliases = { "requester-chest", "logistic-requester-chest" },
  },
}

local OUTPUT_CHEST_CANDIDATES = {
  { name = "wooden-chest", label = "Wooden Chest" },
  { name = "iron-chest", label = "Iron Chest" },
  { name = "steel-chest", label = "Steel Chest" },
  {
    name = "logistic-chest-passive-provider",
    label = "Passive Provider Chest",
    aliases = { "passive-provider-chest", "logistic-passive-provider-chest" },
  },
  {
    name = "logistic-chest-active-provider",
    label = "Active Provider Chest",
    aliases = { "active-provider-chest", "logistic-active-provider-chest" },
  },
  {
    name = "logistic-chest-storage",
    label = "Storage Chest",
    aliases = { "storage-chest", "logistic-storage-chest" },
  },
  {
    name = "logistic-chest-buffer",
    label = "Buffer Chest",
    aliases = { "buffer-chest", "logistic-buffer-chest" },
  },
  {
    name = "logistic-chest-requester",
    label = "Requester Chest",
    aliases = { "requester-chest", "logistic-requester-chest" },
  },
}

local INSERTER_CANDIDATES = {
  { name = "burner-inserter", label = "Burner Inserter" },
  { name = "inserter", label = "Inserter (Yellow)" },
  { name = "fast-inserter", label = "Fast Inserter (Blue)" },
  { name = "bulk-inserter", label = "Bulk Inserter (Green)" },
  { name = "stack-inserter", label = "Stack Inserter" },
}

return {
  GUI_ROOT = GUI_ROOT,
  GUI_ITEM = GUI_ITEM,
  GUI_RECIPE_FLOW = GUI_RECIPE_FLOW,
  GUI_RECIPE_PREFIX = GUI_RECIPE_PREFIX,
  GUI_INPUT_CHEST = GUI_INPUT_CHEST,
  GUI_OUTPUT_CHEST = GUI_OUTPUT_CHEST,
  GUI_STACK_LIMIT = GUI_STACK_LIMIT,
  GUI_STACK_LIMIT_FLOW = GUI_STACK_LIMIT_FLOW,
  GUI_INSERTER = GUI_INSERTER,
  GUI_BUILDING_FLOW = GUI_BUILDING_FLOW,
  GUI_BUILDING_PREFIX = GUI_BUILDING_PREFIX,
  GUI_INSERTER_FLOW = GUI_INSERTER_FLOW,
  GUI_INSERTER_PREFIX = GUI_INSERTER_PREFIX,
  GUI_INPUT_FLOW = GUI_INPUT_FLOW,
  GUI_INPUT_PREFIX = GUI_INPUT_PREFIX,
  GUI_OUTPUT_FLOW = GUI_OUTPUT_FLOW,
  GUI_OUTPUT_PREFIX = GUI_OUTPUT_PREFIX,
  GUI_QUALITY_WARNING = GUI_QUALITY_WARNING,
  GUI_CREATE = GUI_CREATE,
  GUI_CLOSE = GUI_CLOSE,
  GUI_ICON_COLUMNS = GUI_ICON_COLUMNS,
  GUI_MAX_INLINE_ROWS = GUI_MAX_INLINE_ROWS,
  GUI_OVERFLOW_SCROLL_HEIGHT = GUI_OVERFLOW_SCROLL_HEIGHT,
  STATIC_BUILDING_CANDIDATES = STATIC_BUILDING_CANDIDATES,
  INPUT_CHEST_CANDIDATES = INPUT_CHEST_CANDIDATES,
  OUTPUT_CHEST_CANDIDATES = OUTPUT_CHEST_CANDIDATES,
  INSERTER_CANDIDATES = INSERTER_CANDIDATES,
}
