local runtime = require("src.ui.render.support.runtime_ui")
local debug_nodes = require("src.ui.schema.debug")
local base_contract = require("src.ui.schema.base_contract")

local M = {}

local query_node = runtime.query_node

local _mutate_name
local _mutate_fn
local function _mutate_role_callback()
  local node = query_node(_mutate_name)
  _mutate_fn(node)
end

local function mutate_node(name, mutator)
  assert(name ~= nil, "missing ui node name")
  assert(type(mutator) == "function", "missing node mutator")
  local active_role = runtime.get_client_role and runtime.get_client_role() or nil
  if active_role ~= nil then
    local node = query_node(name)
    mutator(node)
    return
  end
  _mutate_name = name
  _mutate_fn = mutator
  runtime.for_each_role_or_global(_mutate_role_callback)
end

local _text_val
local function _text_mutator(node) node.text = _text_val end

local _visible_val
local function _visible_mutator(node) node.visible = _visible_val end

local _disabled_val
local function _disabled_mutator(node) node.disabled = _disabled_val end

-- mutate_node 的全量命中变体：同名节点（如「基础_分享动效」×2）一个不漏。
-- 复用 _mutate_name 单槽闭包，与 mutate_node 同步调用风格一致（不可嵌套）。
local function _mutate_all_role_callback()
  local nodes = runtime.query_nodes(_mutate_name)
  for _, node in ipairs(nodes) do
    _mutate_fn(node)
  end
end

local function mutate_nodes_all(name, mutator)
  assert(name ~= nil, "missing ui node name")
  assert(type(mutator) == "function", "missing node mutator")
  local active_role = runtime.get_client_role and runtime.get_client_role() or nil
  _mutate_name = name
  _mutate_fn = mutator
  if active_role ~= nil then
    _mutate_all_role_callback()
    return
  end
  runtime.for_each_role_or_global(_mutate_all_role_callback)
end

local function set_text(_, name, text)
  _text_val = text or ""
  mutate_node(name, _text_mutator)
end

local function set_visible(_, name, visible)
  _visible_val = visible == true
  mutate_node(name, _visible_mutator)
end

local function set_visible_all(_, name, visible)
  _visible_val = visible == true
  mutate_nodes_all(name, _visible_mutator)
end

local function set_touch_enabled(_, name, enabled)
  _disabled_val = not enabled
  mutate_node(name, _disabled_mutator)
end

local function set_touch_enabled_all(_, name, enabled)
  _disabled_val = not enabled
  mutate_nodes_all(name, _disabled_mutator)
end

local function _resolve_target_screen(ui)
  if not ui then
    return nil
  end
  return ui.choice_screens and ui.choice_screens.target or nil
end

local function _hide_target_button(ui, button_name)
  if not button_name then
    return
  end
  ui:set_button(button_name, "")
  ui:set_visible(button_name, false)
  ui:set_touch_enabled(button_name, false)
end

local function sync_target_choice_buttons(state)
  local ui = state and state.ui or nil
  local screen = _resolve_target_screen(ui)
  if not screen then
    return
  end
  _hide_target_button(ui, screen.confirm)
  _hide_target_button(ui, screen.cancel)
end

local _event_log_text
local function _event_log_mutator(node)
  node.text = _event_log_text
end

local function set_event_log(_, text)
  _event_log_text = text or ""
  mutate_node(base_contract.action_log.label, _event_log_mutator)
end

local function set_event_log_visible(ui, visible)
  if ui then
    ui.debug_visible = visible == true
  end
  set_visible(nil, debug_nodes.canvas, visible)
end

local _slot_name_val
local _image_key_val
local function _apply_item_slot()
  local nodes = runtime.query_nodes(_slot_name_val)
  for _, node in ipairs(nodes) do
    runtime.set_node_texture_keep_size(node, _image_key_val)
  end
end

local function set_item_slot_image(slot_name, image_key)
  assert(slot_name ~= nil, "missing slot name")
  assert(image_key ~= nil, "missing image key for slot: " .. tostring(slot_name))
  local active_role = runtime.get_client_role and runtime.get_client_role() or nil
  _slot_name_val = slot_name
  _image_key_val = image_key
  if active_role ~= nil then
    _apply_item_slot()
    return
  end
  runtime.for_each_role_or_global(_apply_item_slot)
end

M.query_node = query_node
M.set_text = set_text
M.set_visible = set_visible
M.set_visible_all = set_visible_all
M.set_touch_enabled = set_touch_enabled
M.set_touch_enabled_all = set_touch_enabled_all
M.set_event_log = set_event_log
M.set_event_log_visible = set_event_log_visible
M.set_item_slot_image = set_item_slot_image
M.sync_target_choice_buttons = sync_target_choice_buttons

return M

