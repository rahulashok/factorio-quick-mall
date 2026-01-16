local GUI_ROOT = "quick-mall-window"
local GUI_ITEM = "quick-mall-item"
local GUI_BUILDING = "quick-mall-building"
local GUI_RECIPE = "quick-mall-recipe"
local GUI_INPUT_CHEST = "quick-mall-input-chest"
local GUI_OUTPUT_CHEST = "quick-mall-output-chest"
local GUI_INSERTER = "quick-mall-inserter"
local GUI_BUILDING_FLOW = "quick-mall-building-flow"
local GUI_BUILDING_PREFIX = "quick-mall-building-"
local GUI_INSERTER_FLOW = "quick-mall-inserter-flow"
local GUI_INSERTER_PREFIX = "quick-mall-inserter-"
local GUI_CREATE = "quick-mall-create"
local GUI_CLOSE = "quick-mall-close"

local STATIC_BUILDING_CANDIDATES = {
  { name = "assembling-machine-1", label = "Assembler 1" },
  { name = "assembling-machine-2", label = "Assembler 2" },
  { name = "assembling-machine-3", label = "Assembler 3" },
  { name = "chemical-plant", label = "Chemical Plant" },
  { name = "oil-refinery", label = "Oil Refinery" },
  { name = "foundry", label = "Foundry" },
}

local INPUT_CHEST_CANDIDATES = {
  {
    name = "logistic-chest-requester",
    label = "Requester Chest",
    aliases = { "requester-chest", "logistic-requester-chest" },
  },
  {
    name = "logistic-chest-buffer",
    label = "Buffer Chest",
    aliases = { "buffer-chest", "logistic-buffer-chest" },
  },
}

local OUTPUT_CHEST_CANDIDATES = {
  {
    name = "logistic-chest-passive-provider",
    label = "Passive Provider",
    aliases = { "passive-provider-chest", "logistic-passive-provider-chest" },
  },
  {
    name = "logistic-chest-buffer",
    label = "Buffer Chest",
    aliases = { "buffer-chest", "logistic-buffer-chest" },
  },
  {
    name = "logistic-chest-active-provider",
    label = "Active Provider",
    aliases = { "active-provider-chest", "logistic-active-provider-chest" },
  },
}

local INSERTER_CANDIDATES = {
  { name = "burner-inserter", label = "Burner Inserter" },
  { name = "inserter", label = "Inserter (Yellow)" },
  { name = "fast-inserter", label = "Fast Inserter (Blue)" },
  { name = "bulk-inserter", label = "Bulk Inserter (Green)" },
  { name = "stack-inserter", label = "Stack Inserter" },
}

local function get_entity_prototypes()
  local ok, prototypes = pcall(function()
    return game.entity_prototypes
  end)
  if ok and prototypes then
    return prototypes
  end

  ok, prototypes = pcall(function()
    if game.get_filtered_entity_prototypes then
      return game.get_filtered_entity_prototypes({})
    end
    return nil
  end)
  if ok and prototypes then
    return prototypes
  end

  local proto_root = rawget(_G, "prototypes")
  if proto_root and proto_root.entity then
    return proto_root.entity
  end

  return {}
end

local function resolve_entity_prototype(entity_name)
  local ok, proto = pcall(function()
    if game.get_entity_prototype then
      return game.get_entity_prototype(entity_name)
    end
    return nil
  end)
  if ok and proto then
    return proto
  end

  local prototypes = get_entity_prototypes()
  if type(prototypes) == "table" then
    return prototypes[entity_name]
  end

  ok, proto = pcall(function()
    return prototypes and prototypes[entity_name] or nil
  end)
  if ok then
    return proto
  end

  return nil
end

local function can_resolve_prototypes()
  return resolve_entity_prototype("inserter") ~= nil
end

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

local function get_localised_entity_name(entity_name)
  local prototype = resolve_entity_prototype(entity_name)
  return prototype and prototype.localised_name or entity_name
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

local function render_building_buttons(frame, options)
  local building_icons = frame and find_child_by_name(frame, GUI_BUILDING_FLOW)
  if not building_icons then
    return
  end

  building_icons.clear()

  if #options.buildings.names == 0 then
    building_icons.add({ type = "label", caption = "Unavailable" })
    return
  end

  for _, building_name in ipairs(options.buildings.names) do
    local button = building_icons.add({
      type = "sprite-button",
      name = GUI_BUILDING_PREFIX .. building_name,
      sprite = "entity/" .. building_name,
      style = "slot_button",
      tooltip = get_localised_entity_name(building_name),
    })
    button.toggled = (options.building_selection == building_name)
  end
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
  local prototypes = get_entity_prototypes()

  if type(prototypes) == "table" and next(prototypes) ~= nil then
    for name, prototype in pairs(prototypes) do
      local placeable = prototype.items_to_place_this and #prototype.items_to_place_this > 0
      if placeable and prototype.crafting_categories and next(prototype.crafting_categories) then
        if not item_name or find_recipe_for_item(force, item_name, prototype) then
          table.insert(names, name)
        end
      end
    end
  else
    for _, option in ipairs(STATIC_BUILDING_CANDIDATES) do
      local prototype = resolve_entity_prototype(option.name)
      if prototype and prototype.crafting_categories and next(prototype.crafting_categories) then
        if not item_name or find_recipe_for_item(force, item_name, prototype) then
          table.insert(names, option.name)
        end
      end
    end
  end

  table.sort(names)

  for _, name in ipairs(names) do
    local prototype = resolve_entity_prototype(name)
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

  local building_prototype = resolve_entity_prototype(building_name)
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

local function get_storage_root()
  local root = rawget(_G, "global") or rawget(_G, "storage")
  if not root then
    return nil
  end

  root.quick_mall = root.quick_mall or {}
  root.quick_mall.options = root.quick_mall.options or {}
  return root.quick_mall
end

local function ensure_global()
  get_storage_root()
end

local function destroy_gui(player)
  if player.gui.screen[GUI_ROOT] then
    player.gui.screen[GUI_ROOT].destroy()
  end
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
    local ok, can_place = pcall(function()
      return surface.can_place_entity({
        name = placement.name,
        position = placement.position,
        force = force,
        direction = placement.direction or defines.direction.north,
      })
    end)
    if not ok then
      return false, placement.name
    end
    if not can_place then
      return false, placement.name
    end
  end

  return true, nil
end

local function build_layout_placements(center, building_name, input_chest, output_chest, inserter_name, chest_offset, inserter_offset)
  return {
    { name = building_name, position = center, direction = defines.direction.north },
    { name = input_chest, position = { x = center.x - chest_offset, y = center.y } },
    { name = output_chest, position = { x = center.x + chest_offset, y = center.y } },
    { name = inserter_name, position = { x = center.x - inserter_offset, y = center.y }, direction = defines.direction.east },
    { name = inserter_name, position = { x = center.x + inserter_offset, y = center.y }, direction = defines.direction.east },
  }
end

local function build_blueprint_entities(
  base_position,
  building_name,
  recipe_name,
  input_chest,
  output_chest,
  inserter_name,
  chest_offset,
  inserter_offset
)
  local entities = {}
  local next_id = 1

  local function add_entity(def)
    def.entity_number = next_id
    next_id = next_id + 1
    table.insert(entities, def)
  end

  add_entity({
    name = building_name,
    position = { x = base_position.x, y = base_position.y },
    direction = defines.direction.north,
    recipe = recipe_name,
  })

  add_entity({
    name = input_chest,
    position = { x = base_position.x - chest_offset, y = base_position.y },
    is_input_chest = true,
  })

  add_entity({
    name = output_chest,
    position = { x = base_position.x + chest_offset, y = base_position.y },
  })

  add_entity({
    name = inserter_name,
    position = { x = base_position.x - inserter_offset, y = base_position.y },
    direction = defines.direction.west,
  })

  add_entity({
    name = inserter_name,
    position = { x = base_position.x + inserter_offset, y = base_position.y },
    direction = defines.direction.west,
  })

  return entities
end

local function validate_entity_names(names)
  local missing = {}
  for _, name in ipairs(names) do
    if not resolve_entity_prototype(name) then
      table.insert(missing, name)
    end
  end
  return missing
end

local function apply_request_filters_to_blueprint(stack, entities, request_list)
  if not (stack and stack.valid_for_read and stack.is_blueprint and request_list) then
    return
  end

  local blueprint_entities = stack.get_blueprint_entities()
  if not blueprint_entities then
    return
  end

  local input_chest_entity = nil
  for _, entity in ipairs(blueprint_entities) do
    if entities[entity.entity_number] and entities[entity.entity_number].is_input_chest then
      input_chest_entity = entity
      break
    end
  end

  if not input_chest_entity then
    return
  end

  input_chest_entity.request_filters = {}
  for index, request in ipairs(request_list) do
    input_chest_entity.request_filters[index] = {
      index = index,
      name = request.name,
      count = request.count,
    }
  end

  stack.set_blueprint_entities(blueprint_entities)
end

local function give_blueprint_cursor(player, entities, request_list)
  local function cursor_is_empty(stack)
    if not (stack and stack.valid) then
      return true
    end
    return not stack.valid_for_read
  end

  local function set_blueprint_on_stack(stack)
    if not (stack and stack.valid) then
      return false
    end
    if not cursor_is_empty(stack) then
      player.clear_cursor()
    end
    if not cursor_is_empty(stack) then
      return false
    end
    stack.set_stack({ name = "blueprint" })
    if not stack.valid_for_read or not stack.is_blueprint then
      return false
    end
    local missing = validate_entity_names({
      entities[1].name,
      entities[2].name,
      entities[3].name,
      entities[4].name,
      entities[5].name,
    })
    if #missing > 0 then
      return false
    end

    stack.set_blueprint_entities(entities)
    apply_request_filters_to_blueprint(stack, entities, request_list)
    return true
  end

  if set_blueprint_on_stack(player.cursor_stack) then
    return true
  end

  local inventory = player.get_main_inventory and player.get_main_inventory()
  if inventory and inventory.valid then
    local inserted = inventory.insert({ name = "blueprint", count = 1 })
    if inserted > 0 then
      local stack = inventory.find_item_stack("blueprint")
      if stack and stack.valid then
        local missing = validate_entity_names({
          entities[1].name,
          entities[2].name,
          entities[3].name,
          entities[4].name,
          entities[5].name,
        })
        if #missing > 0 then
          return false
        end
        stack.set_blueprint_entities(entities)
        apply_request_filters_to_blueprint(stack, entities, request_list)
        player.print("Quick Mall: blueprint added to inventory. Pick it up to place.")
        return true
      end
    end
  end

  return false
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
    building_selection = nil,
    inserter_selection = nil,
    prototype_resolution_uncertain = false,
  }
  options.prototype_resolution_uncertain = options.input_chests.uncertain
    or options.output_chests.uncertain
    or options.inserters.uncertain
  local storage = get_storage_root()
  if storage then
    storage.options[player.index] = options
  end

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
  item_flow.add({ type = "label", caption = "Item: " })
  item_flow.add({
    type = "choose-elem-button",
    name = GUI_ITEM,
    elem_type = "item",
    tooltip = "Choose the item to craft.",
  })

  local building_flow = content.add({ type = "flow", direction = "horizontal" })
  building_flow.add({ type = "label", caption = "Building: " })
  local building_icons = building_flow.add({
    type = "flow",
    name = GUI_BUILDING_FLOW,
    direction = "horizontal",
  })
  building_icons.style.horizontal_spacing = 4

  local recipe_flow = content.add({ type = "flow", direction = "horizontal" })
  recipe_flow.add({ type = "label", caption = "Recipe: " })
  recipe_flow.add({
    type = "drop-down",
    name = GUI_RECIPE,
    items = options.recipes.labels,
    selected_index = 1,
  })

  local input_flow = content.add({ type = "flow", direction = "horizontal" })
  input_flow.add({ type = "label", caption = "Input chest: " })
  input_flow.add({
    type = "drop-down",
    name = GUI_INPUT_CHEST,
    items = options.input_chests.labels,
    selected_index = 1,
  })

  local output_flow = content.add({ type = "flow", direction = "horizontal" })
  output_flow.add({ type = "label", caption = "Output chest: " })
  output_flow.add({
    type = "drop-down",
    name = GUI_OUTPUT_CHEST,
    items = options.output_chests.labels,
    selected_index = 1,
  })

  local inserter_flow = content.add({ type = "flow", direction = "horizontal" })
  inserter_flow.add({ type = "label", caption = "Inserter: " })
  local inserter_icons = inserter_flow.add({
    type = "flow",
    name = GUI_INSERTER_FLOW,
    direction = "horizontal",
  })
  inserter_icons.style.horizontal_spacing = 4

  for _, inserter_name in ipairs(options.inserters.names) do
    local button = inserter_icons.add({
      type = "sprite-button",
      name = GUI_INSERTER_PREFIX .. inserter_name,
      sprite = "entity/" .. inserter_name,
      style = "slot_button",
      tooltip = get_localised_entity_name(inserter_name),
    })
    button.toggled = false
  end

  local button_flow = content.add({ type = "flow", direction = "horizontal" })
  button_flow.style.horizontal_align = "right"
  button_flow.add({
    type = "button",
    name = GUI_CREATE,
    caption = "Place ghosts",
  })

  player.opened = frame

  if #options.buildings.names > 0 then
    options.building_selection = options.buildings.names[1]
  end
  render_building_buttons(frame, options)

  if options.inserters.names[1] then
    options.inserter_selection = options.inserters.names[1]
    local default_button = find_child_by_name(frame, GUI_INSERTER_PREFIX .. options.inserters.names[1])
    if default_button then
      default_button.toggled = true
    end
  end
end

local function refresh_building_dropdown(player, item_name)
  ensure_global()
  local storage = get_storage_root()
  local options = storage and storage.options[player.index]
  if not options then
    return
  end

  local frame = player.gui.screen[GUI_ROOT]
  if not frame then
    return
  end

  options.buildings = build_building_options(player.force, item_name)
  options.building_selection = options.buildings.names[1]
  render_building_buttons(frame, options)
end

local function refresh_recipe_dropdown(player, item_name)
  ensure_global()
  local storage = get_storage_root()
  local options = storage and storage.options[player.index]
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
  local storage = get_storage_root()
  local options = storage and storage.options[player.index]

  if not options then
    player.print("Quick Mall: please reopen the menu.")
    return
  end

  local frame = player.gui.screen[GUI_ROOT]
  if not frame then
    return
  end

  local item_elem = find_child_by_name(frame, GUI_ITEM)
  local recipe_elem = find_child_by_name(frame, GUI_RECIPE)
  local input_elem = find_child_by_name(frame, GUI_INPUT_CHEST)
  local output_elem = find_child_by_name(frame, GUI_OUTPUT_CHEST)

  local item_name = item_elem and item_elem.elem_value
  if not item_name then
    player.print("Quick Mall: choose an item first.")
    return
  end

  local building_name = options.building_selection
  local recipe_name = recipe_elem and options.recipes.names[recipe_elem.selected_index] or nil
  local input_chest = options.input_chests.names[input_elem.selected_index]
  local output_chest = options.output_chests.names[output_elem.selected_index]
  local inserter_name = options.inserter_selection

  if not (building_name and input_chest and output_chest and inserter_name) then
    player.print("Quick Mall: some selected entities are not available.")
    return
  end

  local building_prototype = resolve_entity_prototype(building_name)
  if not building_prototype then
    player.print("Quick Mall: selected building is not available.")
    return
  end

  local missing = validate_entity_names({
    building_name,
    input_chest,
    output_chest,
    inserter_name,
  })
  if #missing > 0 then
    player.print("Quick Mall: selected entities are not available: " .. table.concat(missing, ", "))
    return
  end

  local recipe = nil
  if recipe_name then
    local selected = player.force.recipes[recipe_name]
    if selected and recipe_outputs_item(selected, item_name) and recipe_usable_in_building(selected, building_prototype) then
      recipe = selected
    end
  end
  if not recipe then
    recipe = find_recipe_for_item(player.force, item_name, building_prototype)
  end
  if not recipe then
    player.print("Quick Mall: no enabled recipe for that item using the selected building.")
    return
  end

  local tile_width = select(1, get_entity_tile_size(building_prototype))
  local half_width = math.floor(tile_width / 2)
  local inserter_offset = half_width + 1
  local chest_offset = half_width + 2

  local entities = build_blueprint_entities(
    { x = 0, y = 0 },
    building_name,
    recipe.name,
    input_chest,
    output_chest,
    inserter_name,
    chest_offset,
    inserter_offset
  )

  local request_list = get_item_requests(recipe)
  if not give_blueprint_cursor(player, entities, request_list) then
    player.print("Quick Mall: unable to create blueprint. Clear your cursor and try again.")
    return
  end

  player.print("Quick Mall: blueprint ready. Click to place it.")
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
    elseif event.element.name:find(GUI_BUILDING_PREFIX, 1, true) == 1 then
      local storage = get_storage_root()
      local options = storage and storage.options[player.index]
      if not options then
        return
      end

      local building_name = event.element.name:sub(#GUI_BUILDING_PREFIX + 1)
      options.building_selection = building_name

      local frame = player.gui.screen[GUI_ROOT]
      local building_icons = frame and find_child_by_name(frame, GUI_BUILDING_FLOW)
      if building_icons then
        for _, child in pairs(building_icons.children) do
          if child and child.valid and child.name:find(GUI_BUILDING_PREFIX, 1, true) == 1 then
            child.toggled = (child.name == event.element.name)
          end
        end
      end

      local item_elem = find_child_by_name(frame, GUI_ITEM)
      local item_name = item_elem and item_elem.elem_value
      refresh_recipe_dropdown(player, item_name)
    elseif event.element.name:find(GUI_INSERTER_PREFIX, 1, true) == 1 then
      local storage = get_storage_root()
      local options = storage and storage.options[player.index]
      if not options then
        return
      end

      local inserter_name = event.element.name:sub(#GUI_INSERTER_PREFIX + 1)
      options.inserter_selection = inserter_name

      local frame = player.gui.screen[GUI_ROOT]
      local inserter_icons = frame and find_child_by_name(frame, GUI_INSERTER_FLOW)
      if inserter_icons then
        for _, child in pairs(inserter_icons.children) do
          if child and child.valid and child.name:find(GUI_INSERTER_PREFIX, 1, true) == 1 then
            child.toggled = (child.name == event.element.name)
          end
        end
      end
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

  if event.element and event.element.valid and event.element.name == GUI_RECIPE then
    return
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
