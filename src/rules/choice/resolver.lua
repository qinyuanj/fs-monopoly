local logger = require("src.foundation.log")
local item_preconsume_policy = require("src.rules.choice.item_preconsume_policy")
local tables = require("src.foundation.tables")
local event_kinds = require("src.config.gameplay.event_kinds")
local dirty_tracker = require("src.state.dirty_tracker")

local choice_resolver = {}

local function _find_option_id(choice, target_option_id)
  return item_preconsume_policy.each_option(choice, function(_, option_id)
    if option_id == target_option_id then
      return option_id
    end
  end)
end

local function _choice_title(choice)
  if choice and choice.title and choice.title ~= "" then
    return choice.title
  end
  return "请选择"
end

local function _clear_choice(game)
  game.turn.pending_choice = nil
  dirty_tracker.mark(game.dirty, "turn")
end

local function _finish_choice(game, stay)
  _clear_choice(game)
  return { status = stay and "waiting" or "resolved", stay = stay }
end

local function _option_exists(choice, target_option_id)
  if choice == nil or target_option_id == nil then
    return false
  end
  return item_preconsume_policy.each_option(choice, function(_, option_id)
    if option_id == target_option_id or tostring(option_id) == tostring(target_option_id) then
      return true
    end
  end) == true
end

local function _build_select_action(choice, option_id, action)
  return {
    type = "choice_select",
    choice_id = choice.id,
    option_id = option_id,
    actor_role_id = action and action.actor_role_id or nil,
  }
end

local function _resolve_descriptor(game, choice)
  local registries = assert(game.registries, "missing game.registries")
  local choice_registry = assert(registries.choices, "missing choice registry")
  local descriptor = type(choice_registry.descriptor_for) == "function"
      and choice_registry:descriptor_for(choice.kind)
      or choice_registry.handlers[choice.kind]
  assert(descriptor ~= nil, "unknown choice kind: " .. tostring(choice.kind))
  assert(type(descriptor.execute) == "function", "invalid choice descriptor: " .. tostring(choice.kind))
  return descriptor
end

local function _resolve_cancel_followup(game, choice, descriptor)
  local cancel = descriptor and descriptor.cancel or nil
  if type(cancel) ~= "table" then
    return nil, nil
  end
  if cancel.mode == "select_option" then
    return _find_option_id(choice, cancel.option_id), nil
  end
  return nil, nil
end

local base_helpers = {
  is_cancel = item_preconsume_policy.is_cancel_action,
  clear_choice = _clear_choice,
  finish_choice = _finish_choice,
  contains = tables.contains,
}

function choice_resolver.helpers(overrides)
  local out = {}
  for key, value in pairs(base_helpers) do
    out[key] = value
  end
  for key, value in pairs(overrides or {}) do
    out[key] = value
  end
  return setmetatable(out, {
    __newindex = function()
      error("helpers is read-only")
    end,
    __metatable = false,
  })
end

local function _emit_skip_event(choice, opts)
  if opts and type(opts.on_event) == "function" then
    opts.on_event({
      kind = event_kinds.choice_skipped,
      text = "跳过选择：" .. _choice_title(choice),
      tip = false,
    })
  end
end

local function _handle_cancel_result(game, choice, cancel_result, descriptor, opts)
  if type(cancel_result) == "table" and cancel_result.stay then
    cancel_result.status = cancel_result.status or "waiting"
    return cancel_result
  end
  _emit_skip_event(choice, opts)
  _clear_choice(game)
  return { status = "resolved", stay = false }
end

local function _resolve_cancel_fallback(game, choice, action, descriptor, opts)
  local fallback_option_id, cancel_result = _resolve_cancel_followup(game, choice, descriptor)
  if fallback_option_id ~= nil then
    action = _build_select_action(choice, fallback_option_id, action)
    return nil, action
  end
  cancel_result = cancel_result or (descriptor.cancel and descriptor.cancel.resolve)
  if type(cancel_result) == "function" then
    cancel_result = cancel_result(game, choice)
  end
  return _handle_cancel_result(game, choice, cancel_result, descriptor, opts)
end

local function _try_cancel_action(game, choice, action, descriptor, opts)
  if not item_preconsume_policy.is_cancel_action(action) then return nil, action end
  local cancel_result, new_action = _resolve_cancel_fallback(game, choice, action, descriptor, opts)
  if cancel_result then return cancel_result, action end
  return nil, new_action
end

local function _maybe_normalize_action(game, choice, action, descriptor)
  if descriptor.normalize_action == nil then return action end
  local normalized = descriptor.normalize_action(game, choice, action)
  if normalized ~= nil then return normalized end
  return action
end

local function _build_resolve_result(result)
  if result and result.stay then
    result.status = result.status or "waiting"
    return result
  end
  return result or { status = "resolved", stay = false }
end

function choice_resolver.resolve(game, choice, action, opts)
  assert(game, "missing game")
  assert(choice, "missing choice")
  assert(action, "missing action")
  opts = opts or {}

  local descriptor = _resolve_descriptor(game, choice)
  action = item_preconsume_policy.normalize_cancel_action(choice, action)

  local early_result, new_action = _try_cancel_action(game, choice, action, descriptor, opts)
  if early_result then return early_result end
  action = new_action

  action = _maybe_normalize_action(game, choice, action, descriptor)

  if not _option_exists(choice, action.option_id) then
    logger.warn("invalid choice option:", tostring(choice.kind), tostring(action.option_id))
    return { status = "rejected", stay = true }
  end

  return _build_resolve_result(descriptor.execute(game, choice, action))
end

choice_resolver._M_test = {
  _contains = tables.contains,
}

return choice_resolver

