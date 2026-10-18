require("test.bootstrap").install_package_paths()
local luassert = require("luassert")
-- player 选择屏 Screen 深模块直测：descriptor 字段 + 路由意图 + registry 注册。
local registry = require("src.ui.screens_registry")
local player_screen = require("src.ui.screens.player_choice")
local schema = require("src.ui.schema.player_choice")

describe("TestPlayerChoiceScreen", function()
it("test_exposes_a_descriptor_with_the_pinned_player_fields", function()
  local d = player_screen.descriptor()
  luassert.truthy(d.key == "player", "descriptor key is player")
  luassert.is_not_nil(d.root, "has root/canvas node")
  luassert.is_not_nil(d.title, "has title")
  luassert.is_not_nil(d.option_buttons, "has option_buttons")
end)

it("test_registers_itself_into_the_registry_under_its_key", function()
  luassert.is_not_nil(registry.build_choice_screens().player, "registry aggregates player descriptor")
  luassert.truthy(registry.opener_for("player") == player_screen.open, "registry maps player opener")
end)

it("test_builds_a_route_spec_for_every_slot_node", function()
  local specs = player_screen.build_route_specs({})
  local spec_names = {}
  for _, s in ipairs(specs) do
    spec_names[s.name] = true
  end
  for _, name in ipairs(schema.slots) do
    luassert.truthy(spec_names[name], "slot node has route spec: " .. name)
  end
end)


end)
