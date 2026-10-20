require("test.bootstrap").install_package_paths()
local luassert = require("luassert")
-- screens/item_atlas 面板面规约(#262 幸存闭合):开/关屏 notify 载荷
-- (source/text/key)与模块装载时 catalog 初值非 nil。
local support = require("test.support.shared_support")
local function _assert_eq(a, b, msg) luassert.is.equal(b, a, msg) end
local _with_patches = support.with_patches
local item_atlas = require("src.ui.screens.item_atlas")
local panel_tip = require("src.ui.coord.panel_tip")
local panel_helpers = require("src.ui.render.support.panel_helpers")
local canvas = require("src.ui.coord.canvas_coordinator")
local item_atlas_view = require("src.ui.render.widgets.item_atlas")

local function _panel_patches(tips, switches)
  return {
    { target = panel_tip, key = "enqueue", value = function(source, text, key)
      tips[#tips + 1] = { source = source, text = text, key = key }
    end },
    { target = panel_helpers, key = "with_owner_role", value = function(_, _, fn)
      return fn()
    end },
    { target = canvas, key = "switch_by_role_id", value = function(_, target, role_id)
      switches[#switches + 1] = { target = target, role_id = role_id }
    end },
    { target = item_atlas_view, key = "refresh_page", value = function() end },
    { target = item_atlas_view, key = "hide_enlarged", value = function() end },
  }
end
describe("TestItemAtlasScreen", function()
it("test_reset_for_tests_binds_the_default_catalog", function()
  -- 装载时预绑已删(#262,等价变异);catalog 字段由注入路径维护。
  item_atlas.reset_for_tests()
  local atlas_state = require("src.ui.screens.item_atlas.item_atlas_state")
  _assert_eq(item_atlas.catalog, atlas_state.catalog(), "reset should rebind the default catalog")
  _assert_eq(item_atlas.catalog ~= nil, true, "catalog after reset must not be nil")
end)

it("test_open_notifies_with_the_exact_tip_payload", function()
  -- kills "ui.item_atlas" -> nil 与 "图鉴已打开" -> nil。
  local tips = {}
  local switches = {}
  _with_patches(_panel_patches(tips, switches), function()
    item_atlas.open({ ui = {} }, 3)
  end)
  _assert_eq(#tips, 1, "open should notify exactly once")
  _assert_eq(tips[1].source, "ui.item_atlas", "open tip should carry the panel source")
  _assert_eq(tips[1].text, "图鉴已打开", "open tip should carry the opened text")
  _assert_eq(tips[1].key, "item_atlas:open:3", "open tip should carry the role-scoped key")
end)

it("test_close_notifies_with_the_exact_tip_payload", function()
  -- kills "已关闭" -> nil 与 "item_atlas:close" -> nil。
  local tips = {}
  local switches = {}
  _with_patches(_panel_patches(tips, switches), function()
    item_atlas.close({ ui = {} }, 3)
  end)
  _assert_eq(#tips, 1, "close should notify exactly once")
  _assert_eq(tips[1].source, "ui.item_atlas", "close tip should carry the panel source")
  _assert_eq(tips[1].text, "已关闭", "close tip should carry the closed text")
  _assert_eq(tips[1].key, "item_atlas:close", "close tip should carry the close key")
end)
it("test_open_runs_every_render_step_through_the_owner_role_scope", function()
  -- #176 review:开屏路径的 passthrough 文字(关闭文字/提示文字)在开屏瞬间
  -- 就要关触摸,不得只在后续翻页的 refresh_page 里顺手做。view 的开屏准备
  -- (背景开触摸 + passthrough 关触摸)与翻页刷新同属 open 的渲染步,与
  -- 清放大卡同口径经 with_owner_role 路由到 owner 角色作用域。
  local scopes = {}
  _with_patches({
    { target = panel_tip, key = "enqueue", value = function() end },
    { target = panel_helpers, key = "with_owner_role", value = function(_, role_id, fn)
      scopes[#scopes + 1] = role_id
      return fn()
    end },
    { target = canvas, key = "switch_by_role_id", value = function() end },
    { target = item_atlas_view, key = "prepare_open", value = function() end },
    { target = item_atlas_view, key = "refresh_page", value = function() end },
    { target = item_atlas_view, key = "hide_enlarged", value = function() end },
  }, function()
    item_atlas.open({ ui = {} }, 5)
  end)
  _assert_eq(#scopes, 3, "open should route prepare + refresh + enlarged cleanup through owner scope")
end)


end)
