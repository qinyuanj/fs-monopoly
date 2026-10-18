local logger = require("src.foundation.log")
local runtime = require("src.ui.render.support.runtime_ui")
local base_contract = require("src.ui.schema.base_contract")
local ui_touch_policy = require("src.ui.input.touch")
local tip_queue = require("src.foundation.tips")
local ui_manager_nodes = require("Data.UIManagerNodes")

local bindings = {}

local missing_button_tips = {}
local GLOBAL_ROLE_SCOPE = "__global"

local function _show_missing_button_tip(name)
  if missing_button_tips[name] then
    return
  end
  missing_button_tips[name] = true
  tip_queue.enqueue({
    text = "UI 节点未适配: " .. tostring(name),
    duration = 2.0,
    dedupe_key = "ui_missing_button:" .. tostring(name),
    blocks_inter_turn = false,
    source = "ui.missing_button",
  })
end

local function _report_register_node_click_failure(name)
  -- tip 只弹一次且转瞬即逝,留 warn 让注册失败在 log.txt 有痕可查。
  logger.warn("ui node click registration failed:", tostring(name))
  _show_missing_button_tip(name)
end

local function _is_registered(registered, name, scope_key)
  local scopes = registered[name]
  if scopes == true then
    return true
  end
  return type(scopes) == "table" and scopes[scope_key] == true
end

local function _mark_registered(registered, name, scope_key)
  local scopes = registered[name]
  if type(scopes) ~= "table" then
    scopes = {}
    registered[name] = scopes
  end
  scopes[scope_key] = true
end

local function _cache_key(name, scope_key)
  return tostring(name) .. "\0" .. tostring(scope_key)
end

local function _dispatch_with_event_role(callback, data, bind_client_role)
  if not bind_client_role then
    callback(data)
    return
  end
  local role = data and data.role or nil
  if role ~= nil then
    runtime.with_client_role(role, callback, data)
    return
  end
  callback(data)
end

local function _resolve_click_nodes(cache, name, scope_key)
  local key = _cache_key(name, scope_key)
  local nodes = cache[key] or cache[name]
  if nodes then
    return nodes
  end
  local ok, result = pcall(runtime.query_nodes, name)
  if not ok then
    _report_register_node_click_failure(name)
    return nil
  end
  cache[key] = result
  cache[name] = result
  return result
end

local function _attach_click_listeners(nodes, callback, listeners, bind_client_role)
  for _, node in ipairs(nodes) do
    local listener = node:listen(UIManager.EVENT.CLICK, function(data)
      _dispatch_with_event_role(callback, data, bind_client_role)
    end)
    table.insert(listeners, listener)
  end
end

local function _assert_register_node_click_args(name, callback, registered, listeners)
  assert(name ~= nil, "missing node name")
  assert(type(callback) == "function", "missing callback")
  assert(registered ~= nil, "missing registered map")
  assert(listeners ~= nil, "missing listeners list")
end

local function _should_bind_client_role(opts)
  return opts == nil or opts.bind_client_role ~= false
end

local function _has_click_nodes(nodes)
  return nodes and nodes[1] ~= nil
end

function bindings.register_node_click(cache, name, callback, registered, listeners, opts)
  _assert_register_node_click_args(name, callback, registered, listeners)
  local bind_client_role = _should_bind_client_role(opts)
  local scope_key = GLOBAL_ROLE_SCOPE
  if _is_registered(registered, name, scope_key) then return end
  local nodes = _resolve_click_nodes(cache, name, scope_key)
  if not _has_click_nodes(nodes) then
    _report_register_node_click_failure(name)
    return
  end
  _mark_registered(registered, name, scope_key)
  _attach_click_listeners(nodes, callback, listeners, bind_client_role)
end

local function _set_node_touch_enabled_fallback(node, enabled)
  if not node then
    return
  end
  node.disabled = not enabled
end

local function _cached_nodes(cache, name)
  return cache and cache[name] or nil
end

local function _has_nodes(nodes)
  return nodes ~= nil and nodes[1] ~= nil
end

local function _query_target_nodes(cache, name)
  local nodes = _cached_nodes(cache, name)
  if _has_nodes(nodes) then
    return nodes
  end
  local ok, result = pcall(runtime.query_nodes, name)
  if not ok then
    return nil
  end
  return result
end

local function _enable_target_nodes(name, nodes)
  if not nodes or not nodes[1] then
    return
  end
  for _, node in ipairs(nodes) do
    pcall(_set_node_touch_enabled_fallback, node, true)
  end
end

local function _enable_action_log_targets(cache, targets)
  for _, name in ipairs(targets) do
    _enable_target_nodes(name, _query_target_nodes(cache, name))
  end
end

local function _try_enable_via_touch_policy(ui)
  if not (ui and ui.set_touch_enabled) then
    return false
  end
  local ok = pcall(ui_touch_policy.set_action_log_toggle_touch, ui, true)
  return ok
end

function bindings.enable_action_log_toggle_touch(cache, ui)
  local targets = base_contract.action_log.toggle_targets or {}
  local main_path_ok = _try_enable_via_touch_policy(ui)

  if not main_path_ok then
    _enable_action_log_targets(cache, targets)
  end

  pcall(runtime.set_client_role, nil)
end

function bindings.register_missing_button_tip(cache, registered, listeners)
  for _, entry in pairs(ui_manager_nodes) do
    if type(entry) == "table" then
      local name = entry[1]
      local kind = entry[2]
      if kind == "EButton" and not registered[name] then
        bindings.register_node_click(cache, name, function()
          _show_missing_button_tip(name)
        end, registered, listeners)
      end
    end
  end
end

return bindings

