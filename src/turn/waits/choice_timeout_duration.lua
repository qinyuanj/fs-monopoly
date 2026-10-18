-- 选择超时时长解析:
-- scoped 配置优先,缺 scope 回落 scope_timeouts.choice,再回落 constants 基础值。
local number_utils = require("src.foundation.number")
local constants = require("src.config.content.constants")
local timing = require("src.config.gameplay.timing")
local runtime_state = require("src.state.runtime")

local M = {}

local function _turn_pending_choice(game)
  return game and game.turn and game.turn.pending_choice
end

local function _state_pending_choice(state)
  return state and runtime_state.get_pending_choice(state)
end

local function _resolve_pending_choice(choice, game, state)
  return choice or _turn_pending_choice(game) or _state_pending_choice(state) or nil
end

local function _positive_numeric(value)
  return number_utils.is_numeric(value) and value > 0 and value or nil
end

local function _resolve_scoped_timeout(kind)
  local scope_timeouts = timing.scope_timeouts
  if type(scope_timeouts) ~= "table" then return nil end
  return _positive_numeric(kind and scope_timeouts[kind])
    or _positive_numeric(scope_timeouts.choice)
end

function M.resolve_choice_timeout_seconds(game, state, choice)
  local pending = _resolve_pending_choice(choice, game, state)
  local kind = pending and pending.kind or nil
  return _resolve_scoped_timeout(kind) or constants.action_timeout_seconds or 0
end

return M

