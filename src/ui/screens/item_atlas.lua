-- item_atlas（图鉴）屏:点击意图 + 面板面,单一归宿(工单 #141,#118 Phase C)。
--
-- 这是 canvas 面,不是选择屏:没有 descriptor / open / canvas 三契约(详见
-- screens_registry 的说明)。
-- 开屏/翻页/图集选择面住 item_atlas/panel.lua(>100 mutation sites 拆分,
-- 公开 API 经本文件再导出保持调用方不变);面板态/目录/翻页纯逻辑住
-- item_atlas/ 子目录卫星(require 路径 src.ui.screens.item_atlas.*)。
local append_intent_spec = require("src.ui.input.route_specs")
local item_atlas_nodes = require("src.ui.schema.item_atlas")
local atlas_state = require("src.ui.screens.item_atlas.item_atlas_state")
local panel = require("src.ui.screens.item_atlas.panel")

local item_atlas = { key = "item_atlas" }

-- ===== route 面 =====

local _append = append_intent_spec.builder("item_atlas_action")

function item_atlas.build_route_specs(_state)
  local specs = {}
  _append(specs, item_atlas_nodes.close_button, "close")
  _append(specs, item_atlas_nodes.close_blank, "dismiss")
  -- #178 点背景关闭:与关闭按钮同一动作。
  _append(specs, item_atlas_nodes.background, "close")
  _append(specs, item_atlas_nodes.page_prev, "prev")
  _append(specs, item_atlas_nodes.page_next, "next")
  for slot_index, name in ipairs(item_atlas_nodes.card_images) do
    _append(specs, name, { type = "select", slot_index = slot_index })
  end
  return specs
end

-- ===== 面板面(开屏/翻页/图集选择):panel.lua 再导出保持公开 API =====

item_atlas.open = panel.open
item_atlas.close = panel.close
item_atlas.handle_action = panel.handle_action

function item_atlas.configure_catalog_for_tests(catalog)
  item_atlas.catalog = atlas_state.set_catalog(catalog)
end

function item_atlas.reset_for_tests()
  item_atlas.catalog = atlas_state.set_catalog(nil)
end

-- 装载时不再预绑 catalog:该字段只被测试注入路径(configure/reset)消费,
-- src 内无读者,预绑值在「首个 reset 前」的窗口外不可观测(等价变异,#262
-- 删除);读取方一律先 reset_for_tests 再取。

local panel_interrupt = require("src.ui.state.panel_interrupt")
-- screen registry 只有进程级注册、没有卸载生命周期；模块热重载时由固定键
-- 覆盖旧 closer，避免保留旧模块闭包，也无需伪造 screen 实例注销点。
panel_interrupt.register_panel_closer("item_atlas", function(state, role_id)
  item_atlas.close(state, role_id)
end)

return item_atlas

