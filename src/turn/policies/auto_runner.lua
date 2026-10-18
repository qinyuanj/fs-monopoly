local Class = require("src.foundation.class")

local choice_auto_policy = require("src.turn.policies.choice_auto")
local choice_contract = require("src.config.choice.contract")
local timing = require("src.config.gameplay.timing")

local auto_runner = Class("AutoRunner")


function auto_runner:init(opts)
  opts = opts or {}
  self.interval = opts.interval or 0.15
  self.timer = 0
  self.enabled = false
  self.waiting_for_interval = false
  self.last_actor_role_id = nil
  self.last_wait_kind = nil
  self.last_choice_id = nil
end


function auto_runner:set_enabled(on)
  self.enabled = on
  self:reset_timer()
end


function auto_runner:reset_timer()
  self.timer = 0
  self.waiting_for_interval = false
  self.last_actor_role_id = nil
  self.last_wait_kind = nil
  self.last_choice_id = nil
end

local function _env_pending_choice(env)
  return env and env.pending_choice or nil
end

local function _env_actor_role_id(env)
  return env and (env.current_player_id or env.current_player_index) or nil
end

local function _resolve_choice_actor_role_id(env)
  local choice = _env_pending_choice(env)
  local owner_role_id = choice_contract.resolve_owner_role_id(choice)
  if owner_role_id ~= nil then
    return owner_role_id
  end
  return _env_actor_role_id(env)
end

local _choice_ctx = { mode = "wait_choice" }

local function _choice_env_ready(env)
  return env and env.pending_choice and env.game
end

local function _resolve_choice_action(env)
  if not _choice_env_ready(env) then
    return nil
  end
  local action = choice_auto_policy.decide(env.game, env.state, env.pending_choice, _choice_ctx)
  if action and action.actor_role_id == nil then
    action.actor_role_id = _resolve_choice_actor_role_id(env)
  end
  return action
end

local function _resolve_wait_kind(env)
  if env and env.pending_choice then
    return "choice"
  end
  if env and env.modal_active then
    return "modal"
  end
  return "next"
end

local function _resolve_interval_seconds(self, env)
  local wait_kind = _resolve_wait_kind(env)
  if wait_kind == "choice" then
    return timing.auto_decision_delay_seconds or 0
  end
  return self.interval or 0
end

local function _wait_signature_changed(self, actor_role_id, wait_kind, choice_id)
  return actor_role_id ~= self.last_actor_role_id
      or wait_kind ~= self.last_wait_kind
      or choice_id ~= self.last_choice_id
end

local function _env_choice_id(env)
  local choice = _env_pending_choice(env)
  return choice and choice.id or nil
end

local function _sync_wait_signature(self, env)
  local actor_role_id = _env_actor_role_id(env)
  local wait_kind = _resolve_wait_kind(env)
  local choice_id = _env_choice_id(env)
  local changed = _wait_signature_changed(self, actor_role_id, wait_kind, choice_id)
  if changed then
    self.timer = 0
    self.waiting_for_interval = false
    self.last_actor_role_id = actor_role_id
    self.last_wait_kind = wait_kind
    self.last_choice_id = choice_id
  end
end

local function _should_skip_action(self, env)
  if not self.enabled then
    return true
  end
  env = env or {}
  if env.game_finished then
    return true
  end
  if env.current_player_computer_controlled ~= true then
    return true
  end
  return false
end

local function _should_wait_interval(self, interval)
  if self.timer < interval then
    self.waiting_for_interval = true
    return true
  end
  return false
end

local function _reset_timer_state(self)
  self.timer = 0
  self.waiting_for_interval = false
end

local _modal_button_action = { type = "modal_button", index = 1 }
local _modal_confirm_action = { type = "modal_confirm" }
local _next_button_action = { type = "ui_button", id = "next", actor_role_id = nil }

local function _resolve_modal_action(env)
  if not env.modal_active then
    return nil
  end
  if env.modal_buttons and #env.modal_buttons > 0 then
    return _modal_button_action
  end
  return _modal_confirm_action
end

local function _resolve_next_button_action(env)
  _next_button_action.actor_role_id = env.current_player_id or env.current_player_index
  return _next_button_action
end

function auto_runner:next_action(dt, env)
  if _should_skip_action(self, env) then
    return nil
  end

  _sync_wait_signature(self, env)
  local interval = _resolve_interval_seconds(self, env)
  self.timer = self.timer + dt
  if _should_wait_interval(self, interval) then
    return nil
  end
  _reset_timer_state(self)

  local choice_action = _resolve_choice_action(env)
  if choice_action then
    return choice_action
  end

  local modal_action = _resolve_modal_action(env)
  if modal_action then
    return modal_action
  end

  return _resolve_next_button_action(env)
end

return auto_runner

