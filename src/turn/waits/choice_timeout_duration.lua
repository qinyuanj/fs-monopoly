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

--[[ mutate4lua-manifest
version=4
projectHash=e150820374e00f7c
scope.0.id=chunk:src/turn/waits/choice_timeout_duration.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=40
scope.0.semanticHash=fa262d1cc32d4693
scope.1.id=function:_turn_pending_choice
scope.1.kind=function
scope.1.startLine=10
scope.1.endLine=12
scope.1.semanticHash=4124418157cabcda
scope.2.id=function:_state_pending_choice
scope.2.kind=function
scope.2.startLine=14
scope.2.endLine=16
scope.2.semanticHash=0a1ae9f84e856668
scope.3.id=function:_resolve_pending_choice
scope.3.kind=function
scope.3.startLine=18
scope.3.endLine=20
scope.3.semanticHash=27d6c8103f520825
scope.4.id=function:_positive_numeric
scope.4.kind=function
scope.4.startLine=22
scope.4.endLine=24
scope.4.semanticHash=286216ad17caada3
scope.5.id=function:_resolve_scoped_timeout
scope.5.kind=function
scope.5.startLine=26
scope.5.endLine=31
scope.5.semanticHash=54eaa0bbc2eeaf4c
scope.6.id=function:M.resolve_choice_timeout_seconds
scope.6.kind=function
scope.6.startLine=33
scope.6.endLine=37
scope.6.semanticHash=b248910eff27300b
]]
