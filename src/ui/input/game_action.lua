local logger = require("src.foundation.log")
local pre_confirm_flow = require("src.ui.input.pre_confirm")
local item_phase_ask_flow = require("src.ui.input.item_phase_ask")
local pending_confirmation = require("src.ui.state.pending_confirmation")
local command_policy = require("src.ui.input.command_policy")
local highlight_lifecycle = require("src.ui.state.item_slot_highlight_lifecycle_queue")

local game_action_dispatcher = {}

local function _is_item_slot_click(intent)
  return command_policy.is_item_slot_command(intent)
end

-- #595:槽位命令无条件解冻(玩家已经动过手),与规则结算是否接受无关
-- (场景 015),故在这里登记而不等结算回来。
local function _register_slot_command(state, intent)
  if not _is_item_slot_click(intent) then
    return
  end
  highlight_lifecycle.push(state, "slot_command", intent and intent.choice_id or nil)
end

local _PRE_CONFIRM_HANDLERS = {
  choice_select = function(state, game, intent, opts, action_port)
    pending_confirmation.confirm(state)
    action_port.dispatch_action(game, state, intent, opts)
    return true
  end,
  choice_cancel = function(state)
    pre_confirm_flow.cancel(state)
    return true
  end,
}

local function _intent_type(intent)
  return intent and intent.type
end

local function _pre_confirm_handler(intent)
  return _PRE_CONFIRM_HANDLERS[_intent_type(intent)]
end

local function _dispatch_pre_confirm_handler(handler, state, game, intent, opts, action_port)
  if handler == nil then
    return false
  end
  return handler(state, game, intent, opts, action_port)
end

local function _handle_pre_confirm(state, game, intent, opts, action_port)
  if not pending_confirmation.is_source_active(state, pending_confirmation.SOURCE_CHOICE_SELECT) then
    return false
  end
  return _dispatch_pre_confirm_handler(_pre_confirm_handler(intent), state, game, intent, opts, action_port)
end

local function _dispatch_basic_action(state, game, intent, opts, action_port, turn_action_helpers)
  local action = intent
  if intent.type == "ui_button" and intent.id == "auto" then
    action = turn_action_helpers.normalize_auto_intent(state, intent)
    if action == nil then
      return true
    end
  end
  action_port.dispatch_action(game, state, action, opts)
  return true
end

local function _dispatch_market_intent(action_type, required_keys, game, state, intent, opts, action_port)
  for _, key in ipairs(required_keys) do
    if intent[key] == nil then
      logger.warn(intent.type .. " missing " .. key)
      return true
    end
  end
  local payload = { type = action_type, actor_role_id = intent.actor_role_id }
  for _, key in ipairs(required_keys) do
    payload[key] = intent[key]
  end
  action_port.dispatch_action(game, state, payload, opts)
  return true
end

local _MARKET_CONFIRM_KEYS = { "choice_id", "option_id" }
local _MARKET_TAB_KEYS = { "choice_id", "tab" }
local _MARKET_PAGE_KEYS = { "choice_id" }

local _COMMAND_HANDLERS = {
  basic = function(s, g, i, o, ap, h) return _dispatch_basic_action(s, g, i, o, ap, h) end,
  market_confirm    = function(s, g, i, o, ap) return _dispatch_market_intent("choice_select", _MARKET_CONFIRM_KEYS, g, s, i, o, ap) end,
  market_page_prev  = function(s, g, i, o, ap) return _dispatch_market_intent("market_page_prev", _MARKET_PAGE_KEYS, g, s, i, o, ap) end,
  market_page_next  = function(s, g, i, o, ap) return _dispatch_market_intent("market_page_next", _MARKET_PAGE_KEYS, g, s, i, o, ap) end,
  market_tab_select = function(s, g, i, o, ap) return _dispatch_market_intent("market_tab_select", _MARKET_TAB_KEYS, g, s, i, o, ap) end,
}

local function _route_by_policy(state, game, intent, opts, action_port, helpers)
  local handler = _COMMAND_HANDLERS[command_policy.game_handler(intent)]
  if handler then return handler(state, game, intent, opts, action_port, helpers) end
  return false
end

local function _try_slot_dispatchers(state, game, intent, opts, ap)
  if item_phase_ask_flow.dispatch(state, game, intent, opts, ap) then return true end
  return _handle_pre_confirm(state, game, intent, opts, ap)
end

local function _try_enter_pre_confirm(state, intent)
  if pending_confirmation.is_active(state) then return false end
  if not pre_confirm_flow.needs_pre_confirm(state, intent) then return false end
  return pre_confirm_flow.enter(state, intent)
end

local function _try_pipeline_early(state, game, intent, opts, ap)
  if _try_slot_dispatchers(state, game, intent, opts, ap) then return true end
  return _try_enter_pre_confirm(state, intent)
end

function game_action_dispatcher.dispatch(state, game, intent, opts, action_port, turn_action_helpers)
  local intent_type = intent and intent.type
  if not intent_type then return false end
  _register_slot_command(state, intent)
  if _try_pipeline_early(state, game, intent, opts, action_port) then return true end
  return _route_by_policy(state, game, intent, opts, action_port, turn_action_helpers)
end

return game_action_dispatcher

