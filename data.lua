-- Data stage script. Define inputs/shortcuts for Quick Mall.
data:extend({
  {
    type = "custom-input",
    name = "quick-mall-open",
    key_sequence = "CONTROL + M",
    consuming = "none",
  },
  {
    type = "shortcut",
    name = "quick-mall-open",
    action = "lua",
    icon = "__base__/graphics/icons/assembling-machine-2.png",
    icon_size = 64,
    small_icon = "__base__/graphics/icons/assembling-machine-2.png",
    small_icon_size = 64,
    associated_control_input = "quick-mall-open",
  },
  {
    type = "selection-tool",
    name = "quick-mall-placement-tool",
    icon = "__base__/graphics/icons/assembling-machine-2.png",
    icon_size = 64,
    flags = {},
    stack_size = 1,
    selection_color = { r = 0.2, g = 0.7, b = 1.0 },
    alt_selection_color = { r = 1.0, g = 0.5, b = 0.2 },
    selection_mode = { "nothing" },
    alt_selection_mode = { "nothing" },
    selection_cursor_box_type = "copy",
    alt_selection_cursor_box_type = "copy",
  },
})