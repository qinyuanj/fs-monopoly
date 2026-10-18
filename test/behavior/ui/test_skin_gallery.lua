require("test.bootstrap").install_package_paths()
local luassert = require("luassert")
-- Behavior specs for src/ui/screens/skin_panel/skin_gallery.lua.
-- 画廊适配器只持有关屏路由，展示与所有权事实留在 canonical 面板。

local P = require("test.support.shared_support")
local function _assert_eq(a, b, msg) luassert.is.equal(b, a, msg) end
local _with_patches = P.with_patches
local skin_gallery = require("src.ui.screens.skin_panel.skin_gallery")
local skin_panel = require("src.ui.screens.skin_panel")
describe("TestSkinGallery", function()
it("test_asserts_descriptive_errors_for_missing_state", function()
  -- 杀 L7 两层消息钉:state 缺失与 state.ui 缺失必须各报各的消息。
  luassert.has_error(function()
    skin_gallery.handle_action(nil, "close")
  end, "missing state")
  luassert.has_error(function()
    skin_gallery.handle_action({}, "close")
  end, "missing state.ui")
end)

it("test_unlock_keeps_facts_in_skin_panel_and_only_routes_close", function()
  local canonical = { open = true, owned_by_role = { ["1"] = { [101] = true } } }
  local state = { ui = {} }
  _with_patches({
    { target = skin_panel, key = "unlock", value = function() return canonical end },
  }, function()
    local result = skin_gallery.handle_action(state, "buy", 1)
    _assert_eq(result, canonical, "unlock should return the canonical skin panel state")
    _assert_eq(state.ui.skin_gallery.mode, "skin", "unlock should route close to the skin panel")
    _assert_eq(state.ui.skin_gallery.owned_by_role, nil, "gallery route must not mirror skin ownership")
  end)
end)

it("test_equip_keeps_selection_in_skin_panel_and_only_routes_close", function()
  local canonical = { open = false, selected_by_role = { ["1"] = 101 } }
  local state = { ui = {} }
  _with_patches({
    { target = skin_panel, key = "equip", value = function() return canonical end },
  }, function()
    local result = skin_gallery.handle_action(state, "equip", 1)
    _assert_eq(result, canonical, "equip should return the canonical skin panel state")
    _assert_eq(state.ui.skin_gallery.mode, nil, "equip should clear the route after the panel auto-closes")
    _assert_eq(state.ui.skin_gallery.selected_by_role, nil, "gallery route must not mirror skin selection")
  end)
end)

it("test_existing_route_drops_stale_skin_mode_after_equip_closed_panel", function()
  local state = {
    ui = {
      skin_panel = { open = false },
      skin_gallery = { mode = "skin" },
    },
  }

  local route = skin_gallery.handle_action(state, "bogus", 1)

  _assert_eq(route.mode, nil, "a closed skin panel should clear its close route")
end)

end)
