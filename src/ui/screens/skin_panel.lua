-- skin_panel（皮肤面板）屏:点击意图 + 面板门面,单一归宿(工单 #140,#118 Phase C)。
--
-- 这是 canvas 面,不是选择屏:没有 descriptor / open / canvas 三契约(详见
-- screens_registry 的说明)。面板
-- 门面住 skin_panel/panel.lua(>100 mutation sites 拆分,公开 API 与 catalog
-- 契约面经本文件再导出/镜像保持调用方不变);画廊/面板态/装备动作三卫星住
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
  for slot_index, name in ipairs(skin_nodes.action_buttons) do
    _append_action_button(specs, name, slot_index)
  end
  for slot_index, name in ipairs(skin_nodes.card_images) do
    _append(specs, name, { type = "equip", slot_index = slot_index })
  end
  return specs
end

-- ===== 面板门面:panel.lua 再导出保持公开 API =====

-- skin_panel.catalog 供行为测试通过公开面核对选择、装备与宿主资源装配；
-- 真源在 transaction_context。configure/reset/port 注入时经 panel.sync_catalog
-- 拉新镜像，供调用方观察当前目录。
local function _sync_catalog()
  panel.sync_catalog()
  skin_panel.catalog = panel.catalog
end

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

function skin_panel.configure_catalog_for_tests(catalog)
  panel.configure_catalog_for_tests(catalog)
  _sync_catalog()
end

function skin_panel.reset_for_tests()
  panel.reset_for_tests()
  _sync_catalog()
end

-- 模块加载期的默认装配跟随 port 注入时机(工单 #244):catalog 镜像与默认
-- result applier 在 transaction 实现注入(compose_game 装配)后立即生效。
cosmetics_ports.when_installed(function()
  _sync_catalog()
  panel.install_default_result_applier()
end)

local panel_interrupt = require("src.ui.state.panel_interrupt")
-- screen registry 只有进程级注册、没有卸载生命周期；模块热重载时由固定键
-- 覆盖旧 closer，避免保留旧模块闭包，也无需伪造 screen 实例注销点。
panel_interrupt.register_panel_closer("skin_panel", function(state, role_id, opts)
  skin_panel.close(state, role_id, opts)
end)

return skin_panel

--[[ mutate4lua-manifest
version=4
projectHash=cad06bb1c0c200e7
scope.0.id=chunk:src/ui/screens/skin_panel.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=90
scope.0.semanticHash=eceffb3a6c228d59
scope.1.id=function:_append_action_button
scope.1.kind=function
scope.1.startLine=20
scope.1.endLine=30
scope.1.semanticHash=e2f61d370a143cd8
scope.2.id=function:<anonymous>
scope.2.kind=function
scope.2.startLine=26
scope.2.endLine=28
scope.2.semanticHash=8f46c6ff43ac589d
scope.3.id=function:skin_panel.build_route_specs
scope.3.kind=function
scope.3.startLine=32
scope.3.endLine=42
scope.3.semanticHash=e7985cf40415f3e5
scope.4.id=function:_sync_catalog
scope.4.kind=function
scope.4.startLine=49
scope.4.endLine=52
scope.4.semanticHash=d537922e05aae7ed
scope.5.id=function:skin_panel.configure_catalog_for_tests
scope.5.kind=function
scope.5.startLine=65
scope.5.endLine=68
scope.5.semanticHash=e9e6dbe583e29db4
scope.6.id=function:skin_panel.reset_for_tests
scope.6.kind=function
scope.6.startLine=70
scope.6.endLine=73
scope.6.semanticHash=cc0fc664e9c192f4
scope.7.id=function:<anonymous>#2
scope.7.kind=function
scope.7.startLine=77
scope.7.endLine=80
scope.7.semanticHash=cc0fc664e9c192f4
scope.8.id=function:<anonymous>#3
scope.8.kind=function
scope.8.startLine=85
scope.8.endLine=87
scope.8.semanticHash=2fc68b1d0ce722c8
]]
