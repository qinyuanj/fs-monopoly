local number_utils = require("src.foundation.number")
local owner = require("src.turn.choice.owner")
local item_preconsume_policy = require("src.rules.choice.item_preconsume_policy")
local auto_play_port = require("src.rules.ports.auto_play")
local control = require("src.player.control")
local optional_action_choice = require("src.turn.optional_action_choice")

local choice_auto_policy = {}

local function _resolve_choice_owner(game, choice)
  return owner.resolve_player(game, choice)
end

local function _choice_options(choice)
  return choice and choice.options or nil
end

local function _first_option_id(first)
  return first.id or first
end

local function _pick_first_choice_option(choice)
  local options = _choice_options(choice)
  if type(options) ~= "table" then
    return nil
  end
  local first = options[1]
  if first == nil then
    return nil
  end
  return _first_option_id(first)
end

local function _select_option_action(choice, option_id)
  if option_id == nil then
    return nil
  end
  return {
    type = "choice_select",
    choice_id = choice.id,
    option_id = option_id,
  }
end

local function _build_auto_or_fallback_action(game, choice, allow_first_option_fallback)
  if item_preconsume_policy.is_preconsumed(choice) then
    return _select_option_action(choice, item_preconsume_policy.first_option_id(choice))
  end
  local auto_action = auto_play_port.auto_action_for_choice(game, choice)
  if auto_action then
    return auto_action
  end
  if not allow_first_option_fallback then
    return nil
  end
  return _select_option_action(choice, _pick_first_choice_option(choice))
end

local function _can_computer_actor_choose(is_computer_controlled_actor, min_visible, elapsed)
  if not is_computer_controlled_actor then
    return false
  end
  return min_visible <= 0 or elapsed >= min_visible
end

local function _resolve_computer_controlled_actor(game, choice, ctx)
  local is_computer_controlled = ctx.is_computer_controlled_actor
  if is_computer_controlled == nil then
    local actor = _resolve_choice_owner(game, choice)
    is_computer_controlled = actor and control.is_computer_controlled(actor) or false
  end
  return is_computer_controlled == true
end

local function _dispatch_computer_actor_mode(game, choice, allow_first_option_fallback, is_computer_controlled_actor, min_visible, elapsed)
  if not _can_computer_actor_choose(is_computer_controlled_actor, min_visible, elapsed) then
    return nil
  end
  return _build_auto_or_fallback_action(game, choice, allow_first_option_fallback)
end

local function _dispatch_timeout_mode(game, choice)
  if optional_action_choice.is_cancelable_optional_action_choice(choice) then
    return { type = "complete_optional_action_phase" }
  end
  if choice.allow_cancel == true then
    return { type = "choice_cancel", choice_id = choice.id }
  end
  local fallback = _build_auto_or_fallback_action(game, choice, true)
  if fallback ~= nil then
    return fallback
  end
  return { type = "choice_force_skip", choice_id = choice.id }
end

local function _dispatch_mode(game, choice, mode, is_computer_controlled_actor, min_visible, elapsed)
  if mode == "wait_choice" then
    return _dispatch_computer_actor_mode(game, choice, false, is_computer_controlled_actor, min_visible, elapsed)
  end
  if mode == "tick_min_visible" then
    return _dispatch_computer_actor_mode(game, choice, true, is_computer_controlled_actor, min_visible, elapsed)
  end
  if mode == "tick_timeout" then
    return _dispatch_timeout_mode(game, choice)
  end
  return nil
end

choice_auto_policy.resolve_choice_owner = _resolve_choice_owner

local function _decide_before_mode(choice, ctx)
  if not (choice and choice.id) then
    return true, nil
  end
  if ctx.pending_action then
    return true, ctx.pending_action
  end
  return false, nil
end

local function _dispatch_mode_or_fallback(game, choice, ctx, mode, is_computer_controlled_actor, min_visible, elapsed)
  local result = _dispatch_mode(game, choice, mode, is_computer_controlled_actor, min_visible, elapsed)
  if result ~= nil then
    return result
  end
  return _build_auto_or_fallback_action(game, choice, ctx.allow_first_option_fallback == true)
end

function choice_auto_policy.decide(game, _state, choice, ctx)
  ctx = ctx or {}
  local handled, action = _decide_before_mode(choice, ctx)
  if handled then
    return action
  end

  local mode = ctx.mode or "wait_choice"
  local is_computer_controlled_actor = _resolve_computer_controlled_actor(game, choice, ctx)
  local min_visible = number_utils.non_negative_or_zero(ctx.min_visible_seconds)
  local elapsed = number_utils.non_negative_or_zero(ctx.elapsed_seconds)
  return _dispatch_mode_or_fallback(game, choice, ctx, mode, is_computer_controlled_actor, min_visible, elapsed)
end

return choice_auto_policy

