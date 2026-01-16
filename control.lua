local GUI_ROOT = "quick-mall-window"
local GUI_ITEM = "quick-mall-item"
local GUI_BUILDING = "quick-mall-building"
local GUI_RECIPE = "quick-mall-recipe"
local GUI_INPUT_CHEST = "quick-mall-input-chest"
local GUI_OUTPUT_CHEST = "quick-mall-output-chest"
local GUI_INSERTER = "quick-mall-inserter"
local GUI_CREATE = "quick-mall-create"
local GUI_CLOSE = "quick-mall-close"

local INPUT_CHEST_CANDIDATES = {
  { name = "logistic-chest-requester", label = "Requester Chest" },
  { name = "logistic-chest-buffer", label = "Buffer Chest" },
}

local OUTPUT_CHEST_CANDIDATES = {
  { name = "logistic-chest-passive-provider", label = "Passive Provider" },
  { name = "logistic-chest-buffer", label = "Buffer Chest" },
  { name = "logistic-chest-active-provider", label = "Active Provider" },
}

local INSERTER_CANDIDATES = {
  { name = "burner-inserter", label = "Burner Inserter" },
  { name = "inserter", label = "Inserter (Yellow)" },
  { name = "fast-inserter", label = "Fast Inserter (Blue)" },
  { name = "bulk-inserter", label = "Bulk Inserter (Green)" },
  { name = "stack-inserter", label = "Stack Inserter" },
}

local function build_option_list(candidates)
  local names = {}
  local labels = {}

  for _, option in ipairs(candidates) do
    if game.entity_prototypes[option.name] then
      table.insert(names, option.name)
      table.insert(labels, option.label)
    end
  end

  if #names == 0 then
    return { names = { nil }, labels = { "Unavailable" } }
  end

  return { names = names, labels = labels }
end

local function find_recipe_for_item(force, item_name, building_prototype)
  for _, recipe in pairs(force.recipes) do
    if recipe.enabled then
      local products = recipe.products or {}
      for _, product in pairs(products) do
        if product.type == "item" and product.name == item_name then
          if not building_prototype then
            return recipe
          end

          local categories = building_prototype.crafting_categories or {}
          if categories[recipe.category] then
            return recipe
          end
        end
      end
    end
  end

  return nil
end

local function build_building_options(force, item_name)
  local names = {}
  local labels = {}

  for name, prototype in pairs(game.entity_prototypes) do
    local placeable = prototype.items_to_place_this and #prototype.items_to_place_this > 0
    if placeable and prototype.crafting_categories and next(prototype.crafting_categories) then
      if not item_name or find_recipe_for_item(force, item_name, prototype) then
        table.insert(names, name)
      end
    end
  end

  table.sort(names)

  for _, name in ipairs(names) do
    local prototype = game.entity_prototypes[name]
    local localised_name = prototype and prototype.localised_name
    if localised_name then
      table.insert(labels, localised_name)
    else
      table.insert(labels, name)
    end
  end

  if #names == 0 then
    return { names = { nil }, labels = { "Unavailable" } }
  end

  return { names = names, labels = labels }
end

local function recipe_outputs_item(recipe, item_name)
  if not recipe or not recipe.enabled then
    return false
  end

  for _, product in pairs(recipe.products or {}) do
    if product.type == "item" and product.name == item_name then
      return true
    end
  end

  return false
end

local function recipe_usable_in_building(recipe, building_prototype)
  if not (recipe and building_prototype) then
    return false
  end

  local categories = building_prototype.crafting_categories or {}
  return categories[recipe.category] == true
end

local function build_recipe_options(force, item_name, building_name)
  if not (item_name and building_name) then
    return { names = { nil }, labels = { "Unavailable" } }
  end

  local building_prototype = game.entity_prototypes[building_name]
  if not building_prototype then
    return { names = { nil }, labels = { "Unavailable" } }
  end

  local names = {}
  for recipe_name, recipe in pairs(force.recipes) do
    if recipe_outputs_item(recipe, item_name) and recipe_usable_in_building(recipe, building_prototype) then
      table.insert(names, recipe_name)
    end
  end

  table.sort(names)

  if #names == 0 then
    return { names = { nil }, labels = { "Unavailable" } }
  end

  local labels = {}
  for _, recipe_name in ipairs(names) do
    local recipe = force.recipes[recipe_name]
    table.insert(labels, recipe and recipe.name or recipe_name)
  end

  return { names = names, labels = labels }
end

local function ensure_global()
  global.quick_mall = global.quick_mall or {}
  global.quick_mall.options = global.quick_mall.options or {}
end

local function destroy_gui(player)
  if player.gui.screen[GUI_ROOT] then
    player.gui.screen[GUI_ROOT].destroy()
  end
end

local function find_child_by_name(element, name)
  if not (element and element.valid) then
    return nil
  end

  if element.name == name then
    return element
  end

  for _, child in pairs(element.children) do
    local found = find_child_by_name(child, name)
    if found then
      return found
    end
  end

  return nil
end

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

local function get_item_requests(recipe)
  local requests = {}

  for _, ingredient in pairs(recipe.ingredients or {}) do
    local ingredient_type = ingredient.type or "item"
    if ingredient_type == "item" then
      local amount = ingredient.amount or ingredient.amount_max or ingredient.amount_min or 1
      local count = math.max(1, math.ceil(amount))
      table.insert(requests, { name = ingredient.name, count = count })
    end
  end

  return requests
end

local function can_place_all(surface, force, placements)
  for _, placement in ipairs(placements) do
    if not surface.can_place_entity({
      name = placement.name,
      position = placement.position,
      force = force,
      direction = placement.direction or defines.direction.north,
    }) then
      return false, placement.name
    end
  end

  return true, nil
end

local function create_quick_mall(player, item_name, building_name, recipe_name, input_chest, output_chest, inserter_name)
  local force = player.force
  local surface = player.surface
  local building_prototype = game.entity_prototypes[building_name]

  if not building_prototype then
    player.print("Quick Mall: selected building is not available.")
    return
  end

  local recipe = nil
  if recipe_name then
    local selected = force.recipes[recipe_name]
    if selected and recipe_outputs_item(selected, item_name) and recipe_usable_in_building(selected, building_prototype) then
      recipe = selected
    end
  end

  if not recipe then
    recipe = find_recipe_for_item(force, item_name, building_prototype)
  end
  if not recipe then
    player.print("Quick Mall: no enabled recipe for that item using the selected building.")
    return
  end

  local assembler_position = surface.find_non_colliding_position(
    building_name,
    player.position,
    10,
    0.5,
    false
  )

  if not assembler_position then
    player.print("Quick Mall: could not find a clear spot to place the assembler.")
    return
  end

  local tile_width = select(1, get_entity_tile_size(building_prototype))
  local half_width = math.floor(tile_width / 2)
  local inserter_offset = half_width + 1
  local chest_offset = half_width + 2

  local placements = {
    { name = building_name, position = assembler_position, direction = defines.direction.north },
    { name = input_chest, position = { x = assembler_position.x - chest_offset, y = assembler_position.y } },
    { name = output_chest, position = { x = assembler_position.x + chest_offset, y = assembler_position.y } },
    { name = inserter_name, position = { x = assembler_position.x - inserter_offset, y = assembler_position.y }, direction = defines.direction.east },
    { name = inserter_name, position = { x = assembler_position.x + inserter_offset, y = assembler_position.y }, direction = defines.direction.west },
  }

  local can_place, blocked_name = can_place_all(surface, force, placements)
  if not can_place then
    player.print("Quick Mall: not enough space to place " .. blocked_name .. ".")
    return
  end

  local request_list = get_item_requests(recipe)

  surface.create_entity({
    name = "entity-ghost",
    inner_name = building_name,
    force = force,
    position = assembler_position,
    direction = defines.direction.north,
    tags = { quick_mall_recipe = recipe.name },
  })

  surface.create_entity({
    name = "entity-ghost",
    inner_name = input_chest,
    force = force,
    position = { x = assembler_position.x - chest_offset, y = assembler_position.y },
    tags = { quick_mall_requests = request_list },
  })

  surface.create_entity({
    name = "entity-ghost",
    inner_name = output_chest,
    force = force,
    position = { x = assembler_position.x + chest_offset, y = assembler_position.y },
  })

  surface.create_entity({
    name = "entity-ghost",
    inner_name = inserter_name,
    force = force,
    position = { x = assembler_position.x - inserter_offset, y = assembler_position.y },
    direction = defines.direction.east,
  })

  surface.create_entity({
    name = "entity-ghost",
    inner_name = inserter_name,
    force = force,
    position = { x = assembler_position.x + inserter_offset, y = assembler_position.y },
    direction = defines.direction.west,
  })

  player.print("Quick Mall: ghosts placed for " .. recipe.name .. ".")
end

local function build_gui(player)
  ensure_global()
  destroy_gui(player)

  local options = {
    buildings = build_building_options(player.force, nil),
    recipes = { names = { nil }, labels = { "Unavailable" } },
    input_chests = build_option_list(INPUT_CHEST_CANDIDATES),
    output_chests = build_option_list(OUTPUT_CHEST_CANDIDATES),
    inserters = build_option_list(INSERTER_CANDIDATES),
  }
  global.quick_mall.options[player.index] = options

  local frame = player.gui.screen.add({
    type = "frame",
    name = GUI_ROOT,
    direction = "vertical",
    caption = "",
  })
  frame.auto_center = true

  local titlebar = frame.add({ type = "flow", direction = "horizontal" })
  titlebar.drag_target = frame
  titlebar.add({ type = "label", caption = "Quick Mall", style = "frame_title" })
  local drag = titlebar.add({ type = "empty-widget", style = "draggable_space_header" })
  drag.style.horizontally_stretchable = true
  drag.style.height = 24
  drag.drag_target = frame
  titlebar.add({
    type = "sprite-button",
    name = GUI_CLOSE,
    style = "frame_action_button",
    sprite = "utility/close",
  })

  local content = frame.add({ type = "flow", direction = "vertical" })
  content.style.padding = 12
  content.style.vertical_spacing = 8

  local item_flow = content.add({ type = "flow", direction = "horizontal" })
  item_flow.add({ type = "label", caption = "Item" })
  item_flow.add({
    type = "choose-elem-button",
    name = GUI_ITEM,
    elem_type = "item",
    tooltip = "Choose the item to craft.",
  })

  local building_flow = content.add({ type = "flow", direction = "horizontal" })
  building_flow.add({ type = "label", caption = "Building" })
  building_flow.add({
    type = "drop-down",
    name = GUI_BUILDING,
    items = options.buildings.labels,
    selected_index = 1,
  })

  local recipe_flow = content.add({ type = "flow", direction = "horizontal" })
  recipe_flow.add({ type = "label", caption = "Recipe" })
  recipe_flow.add({
    type = "drop-down",
    name = GUI_RECIPE,
    items = options.recipes.labels,
    selected_index = 1,
  })

  local input_flow = content.add({ type = "flow", direction = "horizontal" })
  input_flow.add({ type = "label", caption = "Input chest" })
  input_flow.add({
    type = "drop-down",
    name = GUI_INPUT_CHEST,
    items = options.input_chests.labels,
    selected_index = 1,
  })

  local output_flow = content.add({ type = "flow", direction = "horizontal" })
  output_flow.add({ type = "label", caption = "Output chest" })
  output_flow.add({
    type = "drop-down",
    name = GUI_OUTPUT_CHEST,
    items = options.output_chests.labels,
    selected_index = 1,
  })

  local inserter_flow = content.add({ type = "flow", direction = "horizontal" })
  inserter_flow.add({ type = "label", caption = "Inserter" })
  inserter_flow.add({
    type = "drop-down",
    name = GUI_INSERTER,
    items = options.inserters.labels,
    selected_index = 1,
  })

  local button_flow = content.add({ type = "flow", direction = "horizontal" })
  button_flow.style.horizontal_align = "right"
  button_flow.add({
    type = "button",
    name = GUI_CREATE,
    caption = "Place ghosts",
  })

  player.opened = frame
end

local function refresh_building_dropdown(player, item_name)
  ensure_global()
  local options = global.quick_mall.options[player.index]
  if not options then
    return
  end

  local frame = player.gui.screen[GUI_ROOT]
  if not frame then
    return
  end

  options.buildings = build_building_options(player.force, item_name)

  local building_elem = find_child_by_name(frame, GUI_BUILDING)
  if building_elem then
    building_elem.items = options.buildings.labels
    building_elem.selected_index = 1
  end
end

local function refresh_recipe_dropdown(player, item_name)
  ensure_global()
  local options = global.quick_mall.options[player.index]
  if not options then
    return
  end

  local frame = player.gui.screen[GUI_ROOT]
  if not frame then
    return
  end

  local building_elem = find_child_by_name(frame, GUI_BUILDING)
  local building_name = nil
  if building_elem then
    building_name = options.buildings.names[building_elem.selected_index]
  end

  options.recipes = build_recipe_options(player.force, item_name, building_name)

  local recipe_elem = find_child_by_name(frame, GUI_RECIPE)
  if recipe_elem then
    recipe_elem.items = options.recipes.labels
    recipe_elem.selected_index = 1
  end
end

local function handle_create_click(player)
  ensure_global()
  local options = global.quick_mall.options[player.index]

  if not options then
    player.print("Quick Mall: please reopen the menu.")
    return
  end

  local frame = player.gui.screen[GUI_ROOT]
  if not frame then
    return
  end

  local item_elem = find_child_by_name(frame, GUI_ITEM)
  local building_elem = find_child_by_name(frame, GUI_BUILDING)
  local recipe_elem = find_child_by_name(frame, GUI_RECIPE)
  local input_elem = find_child_by_name(frame, GUI_INPUT_CHEST)
  local output_elem = find_child_by_name(frame, GUI_OUTPUT_CHEST)
  local inserter_elem = find_child_by_name(frame, GUI_INSERTER)

  local item_name = item_elem and item_elem.elem_value
  if not item_name then
    player.print("Quick Mall: choose an item first.")
    return
  end

  local building_name = options.buildings.names[building_elem.selected_index]
  local recipe_name = recipe_elem and options.recipes.names[recipe_elem.selected_index] or nil
  local input_chest = options.input_chests.names[input_elem.selected_index]
  local output_chest = options.output_chests.names[output_elem.selected_index]
  local inserter_name = options.inserters.names[inserter_elem.selected_index]

  if not (building_name and input_chest and output_chest and inserter_name) then
    player.print("Quick Mall: some selected entities are not available.")
    return
  end

  create_quick_mall(player, item_name, building_name, recipe_name, input_chest, output_chest, inserter_name)
end

local function apply_ghost_tags(entity, tags)
  if not (entity and entity.valid and tags) then
    return
  end

  if tags.quick_mall_recipe and entity.set_recipe then
    entity.set_recipe(tags.quick_mall_recipe)
  end

  if tags.quick_mall_requests and entity.request_slot_count then
    for index, request in ipairs(tags.quick_mall_requests) do
      entity.set_request_slot(request, index)
    end
  end
end

script.on_init(function()
  ensure_global()
end)

script.on_event("quick-mall-open", function(event)
  local player = game.get_player(event.player_index)
  if player then
    build_gui(player)
  end
end)

script.on_event(defines.events.on_lua_shortcut, function(event)
  if event.prototype_name ~= "quick-mall-open" then
    return
  end

  local player = game.get_player(event.player_index)
  if player then
    build_gui(player)
  end
end)

script.on_event(defines.events.on_gui_click, function(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end

  if event.element and event.element.valid then
    if event.element.name == GUI_CREATE then
      handle_create_click(player)
    elseif event.element.name == GUI_CLOSE then
      destroy_gui(player)
    end
  end
end)

script.on_event(defines.events.on_gui_elem_changed, function(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end

  if event.element and event.element.valid and event.element.name == GUI_ITEM then
    refresh_building_dropdown(player, event.element.elem_value)
    refresh_recipe_dropdown(player, event.element.elem_value)
  end
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end

  if event.element and event.element.valid and event.element.name == GUI_BUILDING then
    local item_elem = find_child_by_name(player.gui.screen[GUI_ROOT], GUI_ITEM)
    local item_name = item_elem and item_elem.elem_value
    refresh_recipe_dropdown(player, item_name)
  end
end)

script.on_event(defines.events.on_gui_closed, function(event)
  if event.element and event.element.valid and event.element.name == GUI_ROOT then
    event.element.destroy()
  end
end)

local function handle_built_entity(event)
  local entity = event.created_entity or event.entity
  if not entity or not entity.valid then
    return
  end

  apply_ghost_tags(entity, event.tags)
end

script.on_event(defines.events.on_built_entity, handle_built_entity)
script.on_event(defines.events.on_robot_built_entity, handle_built_entity)
