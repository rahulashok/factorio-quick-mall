local GUI_ROOT = "quick-mall-window"
local GUI_ITEM = "quick-mall-item"
local GUI_RECIPE_FLOW = "quick-mall-recipe-flow"
local GUI_RECIPE_PREFIX = "quick-mall-recipe-"
local GUI_INPUT_CHEST = "quick-mall-input-chest"
local GUI_OUTPUT_CHEST = "quick-mall-output-chest"
local GUI_INSERTER = "quick-mall-inserter"
local GUI_BUILDING_FLOW = "quick-mall-building-flow"
local GUI_BUILDING_PREFIX = "quick-mall-building-"
local GUI_INSERTER_FLOW = "quick-mall-inserter-flow"
local GUI_INSERTER_PREFIX = "quick-mall-inserter-"
local GUI_INPUT_FLOW = "quick-mall-input-flow"
local GUI_INPUT_PREFIX = "quick-mall-input-"
local GUI_OUTPUT_FLOW = "quick-mall-output-flow"
local GUI_OUTPUT_PREFIX = "quick-mall-output-"
local GUI_QUALITY_FLOW = "quick-mall-quality-flow"
local GUI_QUALITY_PREFIX = "quick-mall-quality-"
local GUI_CREATE = "quick-mall-create"
local GUI_CLOSE = "quick-mall-close"

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

local function render_input_chest_buttons(frame, options)
  local input_icons = frame and find_child_by_name(frame, GUI_INPUT_FLOW)
  if not input_icons then
    return
  end

  input_icons.clear()

  for _, chest_name in ipairs(options.input_chests.names) do
    local button = input_icons.add({
      type = "sprite-button",
      name = GUI_INPUT_PREFIX .. chest_name,
      sprite = "entity/" .. chest_name,
      style = "slot_button",
      tooltip = get_localised_entity_name(chest_name),
    })
    button.toggled = (options.input_chest_selection == chest_name)
  end
end

local function render_output_chest_buttons(frame, options)
  local output_icons = frame and find_child_by_name(frame, GUI_OUTPUT_FLOW)
  if not output_icons then
    return
  end

  output_icons.clear()

  for _, chest_name in ipairs(options.output_chests.names) do
    local button = output_icons.add({
      type = "sprite-button",
      name = GUI_OUTPUT_PREFIX .. chest_name,
      sprite = "entity/" .. chest_name,
      style = "slot_button",
      tooltip = get_localised_entity_name(chest_name),
    })
    button.toggled = (options.output_chest_selection == chest_name)
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

local function render_quality_buttons(frame, options)
  local quality_icons = frame and find_child_by_name(frame, GUI_QUALITY_FLOW)
  if not quality_icons then
    return
  end

  quality_icons.clear()

  if #options.qualities <= 1 then
    quality_icons.parent.visible = false
    return
  end
  quality_icons.parent.visible = true

  for _, quality in ipairs(options.qualities) do
    local button = quality_icons.add({
      type = "sprite-button",
      name = GUI_QUALITY_PREFIX .. quality.name,
      sprite = "quality/" .. quality.name,
      style = "slot_button",
      tooltip = quality.localised_name,
    })
    button.toggled = (options.quality_selection == quality.name)
  end
end

local function render_recipe_buttons(frame, options)
  local recipe_icons = frame and find_child_by_name(frame, GUI_RECIPE_FLOW)
  if not recipe_icons then
    return
  end

  recipe_icons.clear()

  if #options.recipes.names == 0 or (options.recipes.names[1] == nil) then
    recipe_icons.add({ type = "label", caption = "Unavailable" })
    return
  end

  for i, recipe_name in ipairs(options.recipes.names) do
    local button = recipe_icons.add({
      type = "sprite-button",
      name = GUI_RECIPE_PREFIX .. i,
      sprite = "recipe/" .. recipe_name,
      style = "slot_button",
      tooltip = options.recipes.labels[i],
    })
    button.toggled = (options.recipe_selection_index == i)
  end
end

local function build_building_options(force, item_name)
  local prototypes = get_entity_prototypes()
  local entries = {}
  local found_names = {}

  if prototypes then
    for name, prototype in pairs(prototypes) do
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
        if not item_name or find_recipe_for_item(force, item_name, prototype) then
          table.insert(entries, {
            name = name,
            label = prototype.localised_name or name,
            order = prototype.order or "z"
          })
          found_names[name] = true
        end
      end
    end
  end

  if #entries == 0 then
    for _, option in ipairs(STATIC_BUILDING_CANDIDATES) do
      if not found_names[option.name] then
        local prototype = resolve_entity_prototype(option.name)
        if prototype then
          if not item_name or find_recipe_for_item(force, item_name, prototype) then
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

local function get_item_requests(player, recipe, quality)
  local requests = {}
  local index = 1
  local quality_name = quality or "normal"
  for _, ingredient in pairs(recipe.ingredients or {}) do
    local name = ingredient.name or ingredient[1]
    local ingredient_type = ingredient.type or "item"
    if ingredient_type == "item" and name then
      local prototype = resolve_item_prototype(name)
      local stack_size = (prototype and prototype.stack_size) or 1
      -- Request 1 full stack of each input
      local count = stack_size
      table.insert(requests, { index = index, name = name, count = count, quality = quality_name, comparator = "=" })
      index = index + 1
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
    { name = output_chest, position = { x = center.x - chest_offset, y = center.y + 1 } },
    { name = inserter_name, position = { x = center.x - inserter_offset, y = center.y }, direction = defines.direction.east },
    { name = inserter_name, position = { x = center.x - inserter_offset, y = center.y + 1 }, direction = defines.direction.west },
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
  inserter_offset,
  request_list,
  quality
)
  local entities = {}
  local next_id = 1
  local quality_name = quality or "normal"

  local request_filters = nil
  if request_list then
    request_filters = {}
    for index, request in ipairs(request_list) do
      request_filters[index] = {
        index = index,
        name = request.name,
        count = request.count,
        quality = request.quality,
        comparator = request.comparator,
      }
    end
  end

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
    recipe_quality = quality_name,
    tags = { 
      quick_mall_recipe = recipe_name,
      quick_mall_recipe_quality = quality_name
    },
  })

  add_entity({
    name = input_chest,
    position = { x = base_position.x - chest_offset, y = base_position.y },
    request_filters = {
      sections = {
          {
              index = 1,
              filters = request_filters
          }
      }
  },    
  })

  add_entity({
    name = output_chest,
    position = { x = base_position.x - chest_offset, y = base_position.y + 1 },
  })

  add_entity({
    name = inserter_name,
    position = { x = base_position.x - inserter_offset, y = base_position.y },
    direction = defines.direction.west,
  })

  add_entity({
    name = inserter_name,
    position = { x = base_position.x - inserter_offset, y = base_position.y + 1 },
    direction = defines.direction.east,
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
    return true
  end

  if set_blueprint_on_stack(player.cursor_stack) then
    return true
  end

  return false
end

local function get_quality_options()
  local qualities = {}
  
  -- Factorio 2.0+
  if prototypes and prototypes.quality then
    local sorted = {}
    for name, proto in pairs(prototypes.quality) do
      table.insert(sorted, proto)
    end
    table.sort(sorted, function(a, b)
      return (a.level or 0) < (b.level or 0)
    end)
    for _, proto in ipairs(sorted) do
      if not proto.hidden then
        table.insert(qualities, { name = proto.name, localised_name = proto.localised_name })
      end
    end
  end

  -- Fallback for 1.1 or if no qualities found (just normal)
  if #qualities == 0 then
    table.insert(qualities, { name = "normal", localised_name = "Normal" })
  end

  return qualities
end

local function build_chest_options(force, is_input)
  local prototypes = get_entity_prototypes()
  local entries = {}
  local found_names = {}

  if prototypes then
    for name, proto in pairs(prototypes) do
      local is_valid = false
      local type = proto.type
      
      if type == "logistic-container" then
        local mode = proto.logistic_mode
        if is_input then
          if mode == "requester" or mode == "buffer" then
            is_valid = true
          end
        else
          is_valid = true
        end
      elseif not is_input and type == "container" then
        is_valid = true
      end

      if is_valid then
        local is_hidden = false
        pcall(function()
          if proto.has_flag("hidden") then
            is_hidden = true
          end
        end)

        local placeable = false
        if proto.items_to_place_this and #proto.items_to_place_this > 0 then
          placeable = true
        end

        if not is_hidden and placeable then
          local lower_name = name:lower()
          if lower_name:find("bottomless", 1, true) or 
             lower_name:find("debug", 1, true) or 
             lower_name:find("cheat", 1, true) or
             lower_name:find("editor", 1, true) then
            placeable = false
          end
        end

        if not is_hidden and placeable then
          local sort_weight = 100
          if type == "logistic-container" then
            local mode = proto.logistic_mode
            if mode == "requester" then sort_weight = 10
            elseif mode == "buffer" then sort_weight = 20
            elseif mode == "passive-provider" then sort_weight = 30
            elseif mode == "active-provider" then sort_weight = 40
            elseif mode == "storage" then sort_weight = 50
            end
          elseif type == "container" then
            if name:find("steel") then sort_weight = 60
            elseif name:find("iron") then sort_weight = 70
            elseif name:find("wood") then sort_weight = 80
            else sort_weight = 90
            end
          end

          table.insert(entries, {
            name = name,
            label = proto.localised_name or name,
            order = proto.order or "z",
            weight = sort_weight
          })
          found_names[name] = true
        end
      end
    end
  end

  if #entries == 0 then
    local candidates = is_input and INPUT_CHEST_CANDIDATES or OUTPUT_CHEST_CANDIDATES
    return build_option_list(candidates)
  end

  table.sort(entries, function(a, b)
    if a.weight ~= b.weight then
      return a.weight > b.weight
    end
    return a.order > b.order
  end)

  local names = {}
  local labels = {}
  for _, entry in ipairs(entries) do
    table.insert(names, entry.name)
    table.insert(labels, entry.label)
  end

  return { names = names, labels = labels, uncertain = false }
end

local function build_gui(player)
  ensure_global()
  destroy_gui(player)

  local storage = get_storage_root()
  local existing_options = storage and storage.options[player.index]

  local options = {
    buildings = build_building_options(player.force, existing_options and existing_options.item_selection),
    recipes = { names = { nil }, labels = { "Unavailable" } },
    input_chests = build_chest_options(player.force, true),
    output_chests = build_chest_options(player.force, false),
    inserters = build_option_list(INSERTER_CANDIDATES),
    qualities = get_quality_options(),
    item_selection = existing_options and existing_options.item_selection,
    building_selection = existing_options and existing_options.building_selection,
    recipe_selection_index = existing_options and existing_options.recipe_selection_index or 1,
    input_chest_selection = existing_options and existing_options.input_chest_selection,
    output_chest_selection = existing_options and existing_options.output_chest_selection,
    inserter_selection = existing_options and existing_options.inserter_selection,
    quality_selection = existing_options and existing_options.quality_selection or "normal",
    prototype_resolution_uncertain = false,
    is_initializing = true,
  }

  local function is_valid_selection(selection, list)
    if not selection then return false end
    for _, name in ipairs(list) do
      if name == selection then return true end
    end
    return false
  end

  if not is_valid_selection(options.building_selection, options.buildings.names) then
    options.building_selection = options.buildings.names[1]
  end

  if options.item_selection and options.building_selection then
    options.recipes = build_recipe_options(player.force, options.item_selection, options.building_selection)
  end

  if options.recipe_selection_index > #options.recipes.names then
    options.recipe_selection_index = 1
  end

  options.prototype_resolution_uncertain = options.input_chests.uncertain
    or options.output_chests.uncertain
    or options.inserters.uncertain
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
  local item_picker = item_flow.add({
    type = "choose-elem-button",
    name = GUI_ITEM,
    elem_type = "item",
    tooltip = "Choose the item to craft.",
  })
  
  if options.item_selection then
    item_picker.elem_value = options.item_selection
  end

  options.is_initializing = false

  local quality_flow = content.add({ type = "flow", direction = "horizontal" })
  quality_flow.add({ type = "label", caption = "Item Quality: " })
  local quality_icons = quality_flow.add({
    type = "flow",
    name = GUI_QUALITY_FLOW,
    direction = "horizontal",
  })
  quality_icons.style.horizontal_spacing = 4

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
  local recipe_icons = recipe_flow.add({
    type = "flow",
    name = GUI_RECIPE_FLOW,
    direction = "horizontal",
  })
  recipe_icons.style.horizontal_spacing = 4

  local input_flow = content.add({ type = "flow", direction = "horizontal" })
  input_flow.add({ type = "label", caption = "Input chest: " })
  local input_icons = input_flow.add({
    type = "flow",
    name = GUI_INPUT_FLOW,
    direction = "horizontal",
  })
  input_icons.style.horizontal_spacing = 4

  local output_flow = content.add({ type = "flow", direction = "horizontal" })
  output_flow.add({ type = "label", caption = "Output chest: " })
  local output_icons = output_flow.add({
    type = "flow",
    name = GUI_OUTPUT_FLOW,
    direction = "horizontal",
  })
  output_icons.style.horizontal_spacing = 4

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
    button.toggled = (options.inserter_selection == inserter_name)
  end

  local button_flow = content.add({ type = "flow", direction = "horizontal" })
  button_flow.style.horizontal_align = "right"
  button_flow.add({
    type = "button",
    name = GUI_CREATE,
    caption = "Place ghosts",
  })

  player.opened = frame

  render_building_buttons(frame, options)
  render_recipe_buttons(frame, options)

  if not is_valid_selection(options.input_chest_selection, options.input_chests.names) then
    options.input_chest_selection = options.input_chests.names[1]
  end
  render_input_chest_buttons(frame, options)

  if not is_valid_selection(options.output_chest_selection, options.output_chests.names) then
    options.output_chest_selection = options.output_chests.names[1]
  end
  render_output_chest_buttons(frame, options)

  local function is_valid_quality(selection, list)
    if not selection then return false end
    for _, q in ipairs(list) do
      if q.name == selection then return true end
    end
    return false
  end

  if not is_valid_quality(options.quality_selection, options.qualities) then
    options.quality_selection = "normal"
  end
  render_quality_buttons(frame, options)

  if not is_valid_selection(options.inserter_selection, options.inserters.names) then
    options.inserter_selection = options.inserters.names[1]
  end
  -- Update inserter buttons state
  local inserter_icons = find_child_by_name(frame, GUI_INSERTER_FLOW)
  if inserter_icons then
    for _, child in pairs(inserter_icons.children) do
      if child and child.valid and child.name:find(GUI_INSERTER_PREFIX, 1, true) == 1 then
        local inserter_name = child.name:sub(#GUI_INSERTER_PREFIX + 1)
        child.toggled = (options.inserter_selection == inserter_name)
      end
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

local function refresh_recipe_buttons(player, item_name)
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

  local building_name = options.building_selection
  options.recipes = build_recipe_options(player.force, item_name, building_name)

  -- Reset recipe selection index if it's out of range
  if options.recipe_selection_index > #options.recipes.names then
    options.recipe_selection_index = 1
  end

  render_recipe_buttons(frame, options)
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

  local item_name = item_elem and item_elem.elem_value
  if not item_name then
    player.print("Quick Mall: choose an item first.")
    return
  end

  local building_name = options.building_selection
  local recipe_name = options.recipes.names[options.recipe_selection_index]
  local input_chest = options.input_chest_selection
  local output_chest = options.output_chest_selection
  local inserter_name = options.inserter_selection
  local quality_name = options.quality_selection

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

  local request_list = get_item_requests(player, recipe, quality_name)
  local entities = build_blueprint_entities(
    { x = 0, y = 0 },
    building_name,
    recipe.name,
    input_chest,
    output_chest,
    inserter_name,
    chest_offset,
    inserter_offset,
    request_list,
    quality_name
  )
  if not give_blueprint_cursor(player, entities, request_list) then
    player.print("Quick Mall: unable to create blueprint. Clear your cursor and try again.")
    return
  end

  destroy_gui(player)
  player.print("Quick Mall: blueprint ready. Click to place it.")
end

local function apply_ghost_tags(entity, tags)
  if not (entity and entity.valid and tags) then
    return
  end

  if tags.quick_mall_recipe and entity.set_recipe then
    local quality = tags.quick_mall_recipe_quality or "normal"
    entity.set_recipe(tags.quick_mall_recipe, quality)
  end

  if tags.quick_mall_requests then
    local ok, setter = pcall(function()
      return entity.set_request_slot
    end)
    if ok and setter then
      for index, request in ipairs(tags.quick_mall_requests) do
        local success = pcall(function()
          setter(entity, request, index)
        end)
        if not success then
          break
        end
      end
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
      refresh_recipe_buttons(player, item_name)
    elseif event.element.name:find(GUI_RECIPE_PREFIX, 1, true) == 1 then
      local storage = get_storage_root()
      local options = storage and storage.options[player.index]
      if not options then
        return
      end

      local index = tonumber(event.element.name:sub(#GUI_RECIPE_PREFIX + 1))
      options.recipe_selection_index = index

      local frame = player.gui.screen[GUI_ROOT]
      render_recipe_buttons(frame, options)
    elseif event.element.name:find(GUI_INPUT_PREFIX, 1, true) == 1 then
      local storage = get_storage_root()
      local options = storage and storage.options[player.index]
      if not options then
        return
      end

      local chest_name = event.element.name:sub(#GUI_INPUT_PREFIX + 1)
      options.input_chest_selection = chest_name

      local frame = player.gui.screen[GUI_ROOT]
      render_input_chest_buttons(frame, options)
    elseif event.element.name:find(GUI_OUTPUT_PREFIX, 1, true) == 1 then
      local storage = get_storage_root()
      local options = storage and storage.options[player.index]
      if not options then
        return
      end

      local chest_name = event.element.name:sub(#GUI_OUTPUT_PREFIX + 1)
      options.output_chest_selection = chest_name

      local frame = player.gui.screen[GUI_ROOT]
      render_output_chest_buttons(frame, options)
    elseif event.element.name:find(GUI_QUALITY_PREFIX, 1, true) == 1 then
      local storage = get_storage_root()
      local options = storage and storage.options[player.index]
      if not options then
        return
      end

      local quality_name = event.element.name:sub(#GUI_QUALITY_PREFIX + 1)
      options.quality_selection = quality_name

      local frame = player.gui.screen[GUI_ROOT]
      render_quality_buttons(frame, options)
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
    local storage = get_storage_root()
    local options = storage and storage.options[player.index]
    
    if options and options.is_initializing then
      return
    end
    if options then
      options.item_selection = event.element.elem_value
      options.recipe_selection_index = 1
    end
    refresh_building_dropdown(player, event.element.elem_value)
    refresh_recipe_buttons(player, event.element.elem_value)
  end
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(event)
  local player = game.get_player(event.player_index)
  if not player then
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

  local tags = event.tags
  if not tags and entity.tags then
    local ok, entity_tags = pcall(function()
      return entity.tags
    end)
    if ok then
      tags = entity_tags
    end
  end

  apply_ghost_tags(entity, tags)
end

script.on_event(defines.events.on_built_entity, handle_built_entity)
script.on_event(defines.events.on_robot_built_entity, handle_built_entity)
