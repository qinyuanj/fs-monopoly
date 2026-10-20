-- skin_panel（皮肤面板）屏:点击意图 + 面板门面,单一归宿(工单 #140,#118 Phase C)。
--
-- 这是 canvas 面,不是选择屏:没有 descriptor / open / canvas 三契约(详见
-- screens_registry 的说明)。面板
-- 门面住 skin_panel/panel.lua，公开动作 API 经本文件再导出；画廊/面板态/装备动作三卫星住
-- skin_panel/ 子目录(require 路径 src.ui.screens.skin_panel.*)。
local append_intent_spec = require("src.ui.input.route_specs")
local cosmetics_ports = require("src.ui.seams.cosmetics")
local skin_nodes = require("src.ui.schema.skin")
local panel = require("src.ui.screens.skin_panel.panel")

local skin_panel = { key = "skin_panel" }

-- ===== route 面 =====

local INTENT_TYPE = "skin_panel_action"
local _append = append_intent_spec.builder(INTENT_TYPE)

local function _append_action_button(specs, name, slot_index)
  if not name then
    return
  end
  specs[#specs + 1] = {
    name = name,
    build_intent = function()
      return { type = INTENT_TYPE, action = { type = "activate_slot", slot_index = slot_index } }
    end,
  }
end

function skin_panel.build_route_specs(_state)
  local specs = {}
  _append(specs, skin_nodes.close_button, "close")
  -- #178 点背景关闭:与关闭按钮同一面板动作。
  _append(specs, skin_nodes.activity_background, "close")
  for slot_index, name in ipairs(skin_nodes.action_buttons) do
    _append_action_button(specs, name, slot_index)
  end
  for slot_index, name in ipairs(skin_nodes.card_images) do
    _append(specs, name, { type = "equip", slot_index = slot_index })
  end
  return specs
end

-- ===== 面板门面:panel.lua 再导出保持公开 API =====

skin_panel.apply_transaction_result = panel.apply_transaction_result
skin_panel.is_slot_equipped = panel.is_slot_equipped
skin_panel.configure_equip = panel.configure_equip
skin_panel.configure_unequip = panel.configure_unequip
skin_panel.configure_archive = panel.configure_archive
skin_panel.open = panel.open
skin_panel.close = panel.close
skin_panel.unlock = panel.unlock
skin_panel.equip = panel.equip
skin_panel.handle_action = panel.handle_action

skin_panel.configure_catalog_for_tests = panel.configure_catalog_for_tests
skin_panel.reset_for_tests = panel.reset_for_tests

-- 默认 result applier 在 transaction 实现注入(compose_game 装配)后立即生效。
cosmetics_ports.when_installed(function()
  panel.install_default_result_applier()
end)

local panel_interrupt = require("src.ui.state.panel_interrupt")
-- screen registry 只有进程级注册、没有卸载生命周期；模块热重载时由固定键
-- 覆盖旧 closer，避免保留旧模块闭包，也无需伪造 screen 实例注销点。
panel_interrupt.register_panel_closer("skin_panel", function(state, role_id, opts)
  skin_panel.close(state, role_id, opts)
end)

return skin_panel

