local common = require("src.ui.coord.choice_helpers")
local ui_controls = require("src.ui.render.support.ui_controls")
local logger = require("src.foundation.log")
local panel_interrupt = require("src.ui.state.panel_interrupt")
local screen_openers = require("src.ui.seams.screen_openers")

local M = {}

-- 标题/正文节点是可选的，缺省文案在这里兜底。
local function _set_screen_copy(ui, screen, choice)
  if screen.title then
    ui:set_label(screen.title, choice.title or "请选择")
  end
  if screen.body then
    ui:set_label(screen.body, choice.body or "")
  end
end

local function _open_screen(state, screen_key, choice, choice_id)
  local ui = state.ui
  local screen = ui.choice_screens[screen_key]
  assert(screen ~= nil, "missing choice screen: " .. tostring(screen_key))

  common.hide_choice_screens(ui)
  ui_controls.set_control_state(ui, screen.root, { visible = true })
  _set_screen_copy(ui, screen, choice)
  common.switch_modal_canvas(state, common.resolve_canvas_for_screen(screen_key))
  ui.choice_active = true
  ui.active_choice_screen_key = screen_key
  panel_interrupt.interrupt(state)
  return ui, screen
end

local function _compact_options(options)
  local out = {}
  for _, option in ipairs(options or {}) do
    if option ~= nil then
      out[#out + 1] = option
    end
  end
  return out
end

local function _set_action_button(ui, name, visible, enabled, label)
  if not name then
    return
  end
  if visible and label ~= nil then
    ui:set_button(name, label)
  end
  ui_controls.set_control_state(ui, name, {
    visible = visible,
    touch_enabled = enabled,
  })
end

local function _store_target_button_labels(screen, choice)
  if not screen then
    return
  end
  screen.confirm_label = "确定"
  screen.cancel_label = choice and choice.cancel_label or "取消"
end

local function _sync_slot_label(ui, label_node, option)
  if not label_node then
    return
  end
  if option then
    ui:set_label(label_node, common.resolve_option_label(option))
  else
    ui:set_label(label_node, "")
  end
  ui_controls.set_control_state(ui, label_node, {
    visible = option ~= nil,
    touch_enabled = false,
  })
end

local function _sync_projection_node(ui, projection_node, option)
  if not projection_node then
    return
  end
  ui_controls.set_control_state(ui, projection_node, {
    visible = option ~= nil,
    touch_enabled = false,
  })
end

-- 槽位标签与投影节点都是可选的，按 index 取到哪个算哪个。
local function _sync_option_slot(ui, screen, index, option)
  _sync_slot_label(ui, screen.slot_labels and screen.slot_labels[index] or nil, option)
  _sync_projection_node(ui, screen.slot_projections and screen.slot_projections[index] or nil, option)
end

-- 设置单个选项按钮并按其样式清除文案,返回按钮 node id。
local function _set_option_node(ui, name, option, clear_button_text)
  local option_id = common.set_option_node(ui, name, option)
  if clear_button_text == true and option then
    ui:set_button(name, "")
  end
  return option_id
end

local function _fill_option_nodes(ui, screen, options, opts)
  local option_ids = {}
  local selected = nil
  opts = opts or {}
  for index, name in ipairs(screen.option_buttons or {}) do
    local option = options[index]
    local option_id = _set_option_node(ui, name, option, opts.clear_button_text)
    option_ids[index] = option_id

    _sync_option_slot(ui, screen, index, option)
    selected = selected or option_id
  end
  return option_ids, selected
end

local function _order_target_options(choice)
  local options = choice.options or {}
  local layout = choice.target_slot_layout
  if not layout then
    return options
  end
  local slots = {}
  for i, option in ipairs(options) do
    local slot = layout[i] or i
    slots[slot] = option
  end
  return slots
end

local function _resolve_player_or_remote_options(choice, screen_key)
  if screen_key == "player" and choice.target_slot_layout then
    return _order_target_options(choice)
  end
  return _compact_options(choice.options)
end

function M.open_choice_modal(state, choice, market, opener_for)
  local screen_key = common.resolve_screen_key(choice)
  if screen_key == "base_inline" or screen_key == "market" then
    return false
  end

  opener_for = assert(opener_for, "missing screen opener lookup")
  local open = opener_for(screen_key)
  if not open then
    logger.warn("unsupported choice screen key:", tostring(screen_key))
    return false
  end
  open(state, choice, choice.id, screen_key)
  return true
end

M.open_screen = _open_screen
M.fill_option_nodes = _fill_option_nodes
M.order_target_options = _order_target_options
M.store_target_button_labels = _store_target_button_labels
M.set_action_button = _set_action_button
M.resolve_player_or_remote_options = _resolve_player_or_remote_options

-- 行为测试公共接缝：商店确认场景由此开屏，验证后续选择派单；经 screen_openers 委派。
function M.open_secondary_confirm_screen(state, choice, choice_id)
  return screen_openers.open_secondary_confirm(state, choice, choice_id)
end
function M.open_pre_confirm_screen(state, choice, option_id, title, body)
  return screen_openers.open_pre_confirm(state, choice, option_id, title, body)
end

return M

--[[ mutate4lua-manifest
version=4
projectHash=454ba10886520a47
scope.0.id=chunk:src/ui/coord/choice_openers.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=173
scope.0.semanticHash=9e182eabf0c81e12
scope.1.id=function:_set_screen_copy
scope.1.kind=function
scope.1.startLine=10
scope.1.endLine=17
scope.1.semanticHash=f0f854bdced1b7ed
scope.2.id=function:_open_screen
scope.2.kind=function
scope.2.startLine=19
scope.2.endLine=32
scope.2.semanticHash=f71c56bfe01f7dbd
scope.3.id=function:_compact_options
scope.3.kind=function
scope.3.startLine=34
scope.3.endLine=42
scope.3.semanticHash=fea49927a0585fd4
scope.4.id=function:_set_action_button
scope.4.kind=function
scope.4.startLine=44
scope.4.endLine=55
scope.4.semanticHash=16076117b93ce4e2
scope.5.id=function:_store_target_button_labels
scope.5.kind=function
scope.5.startLine=57
scope.5.endLine=63
scope.5.semanticHash=be896a9ad7cb1604
scope.6.id=function:_sync_slot_label
scope.6.kind=function
scope.6.startLine=65
scope.6.endLine=78
scope.6.semanticHash=be88da6a74bb4f61
scope.7.id=function:_sync_projection_node
scope.7.kind=function
scope.7.startLine=80
scope.7.endLine=88
scope.7.semanticHash=cb92c61cf359c523
scope.8.id=function:_sync_option_slot
scope.8.kind=function
scope.8.startLine=91
scope.8.endLine=94
scope.8.semanticHash=649376e35748e23a
scope.9.id=function:_set_option_node
scope.9.kind=function
scope.9.startLine=97
scope.9.endLine=103
scope.9.semanticHash=129cbb94b770d39c
scope.10.id=function:_fill_option_nodes
scope.10.kind=function
scope.10.startLine=105
scope.10.endLine=118
scope.10.semanticHash=0374ebc3a39944a4
scope.11.id=function:_order_target_options
scope.11.kind=function
scope.11.startLine=120
scope.11.endLine=132
scope.11.semanticHash=f10a24daf52eb9c7
scope.12.id=function:_resolve_player_or_remote_options
scope.12.kind=function
scope.12.startLine=134
scope.12.endLine=139
scope.12.semanticHash=a5bc7c2cb81f098e
scope.13.id=function:M.open_choice_modal
scope.13.kind=function
scope.13.startLine=141
scope.13.endLine=155
scope.13.semanticHash=f7028ce311abd428
scope.14.id=function:M.open_secondary_confirm_screen
scope.14.kind=function
scope.14.startLine=165
scope.14.endLine=167
scope.14.semanticHash=d590c542c8c308c5
scope.15.id=function:M.open_pre_confirm_screen
scope.15.kind=function
scope.15.startLine=168
scope.15.endLine=170
scope.15.semanticHash=aad746b6887fa005
]]
