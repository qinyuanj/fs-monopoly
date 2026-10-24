require("test.bootstrap").install_package_paths()
local luassert = require("luassert")
-- #204:皮肤商店屏的展示状态只有开关、页码与所属角色,住 state.ui.skin_panel;
-- 归属与穿戴不在这里(归皮肤归属模块)。
local panel_state = require("src.ui.screens.skin_panel.skin_panel_state")

describe("TestSkinPanelState", function()
it("test_ensure_creates_a_closed_first_page_panel", function()
  local root_state = { ui = {} }
  local panel = panel_state.ensure(root_state)
  luassert.same({ open = false, page_index = 1 }, panel, "fresh panel is closed on page 1")
  luassert.truthy(panel == root_state.ui.skin_panel, "panel lives at state.ui.skin_panel")
end)

it("test_ensure_reuses_an_existing_panel", function()
  local existing = { open = true }
  local root_state = { ui = { skin_panel = existing } }
  luassert.truthy(panel_state.ensure(root_state) == existing, "existing panel must be reused, not replaced")
end)

it("test_ensure_raises_missing_state_without_ui", function()
  for _, root_state in ipairs({ {}, false }) do
    local ok, err = pcall(panel_state.ensure, root_state or nil)
    luassert.truthy(ok == false, "ensure must fail without ui state")
    luassert.truthy(tostring(err):find("missing_state") ~= nil, "error must carry missing_state")
  end
end)
end)
