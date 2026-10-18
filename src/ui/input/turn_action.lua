local logger = require("src.foundation.log")

local turn_action_port = {}

local _default_turn_action_port = {
  dispatch_action = function()
    return { status = "rejected" }
  end,
  should_block_action = function()
    return false
  end,
}

local function _state_port(state)
  return state and state.turn_action_port or nil
end

local function _resolve_raw_port(state, opts)
  local override_port = opts and opts.turn_action_port or nil
  return override_port or _state_port(state)
end

local function _resolve_port_method(raw, method_name)
  if type(raw) == "table" and type(raw[method_name]) == "function" then
    return raw[method_name]
  end
  return _default_turn_action_port[method_name]
end

function turn_action_port.resolve(state, opts)
  local raw = _resolve_raw_port(state, opts)
  if type(raw) ~= "table" then
    return _default_turn_action_port
  end
  return {
    dispatch_action = _resolve_port_method(raw, "dispatch_action"),
    should_block_action = _resolve_port_method(raw, "should_block_action"),
  }
end

function turn_action_port.should_block(state, intent, action_port)
  return action_port.should_block_action(state, intent)
end

-- 行动者归属在事件边界(canvas_event_router 的 attach_event_actor)裁定一次,
-- 用例层只消费不再解析(ADR 0054,GLOSSARY.md「行动者」)。auto 按钮经
-- event_actor_policy.attach_event_actor 后才到这里,actor_role_id 保证非 nil;
-- nil 兜底拒绝是挡测试误用的 guard,生产路径不可达(#442 复核结论)。
function turn_action_port.normalize_auto_intent(state, intent)
  local action = {}
  for k, v in pairs(intent) do
    action[k] = v
  end
  if action.actor_role_id == nil then
    logger.warn("auto intent missing actor_role_id")
    return nil
  end
  return action
end

return turn_action_port

