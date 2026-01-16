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
})