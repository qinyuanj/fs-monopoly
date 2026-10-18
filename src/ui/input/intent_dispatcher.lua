local logger = require("src.foundation.log")
local turn_action_port = require("src.ui.input.turn_action")
local game_action_dispatcher = require("src.ui.input.game_action")
local view_command_dispatcher = require("src.ui.input.view_command")
local command_policy = require("src.ui.input.command_policy")

local intent_dispatcher = {}

local function _dispatch_game_action(state, game, intent, opts, action_port)
  local resolved_action_port = action_port or turn_action_port.resolve(state, opts)
  return game_action_dispatcher.dispatch(state, game, intent, opts, resolved_action_port, turn_action_port)
end

intent_dispatcher.dispatch_view_command = view_command_dispatcher.dispatch

function intent_dispatcher.dispatch(state, game, intent, opts)
  assert(intent, "missing intent")
  local intent_type = intent.type
  local action_port = turn_action_port.resolve(state, opts)
  if command_policy.dispatches_before_game(intent) then
    -- View command 在 game 前派发即为终态：即使端口缺失（诊断场景，dispatch
    -- warn 后返回 false）也直接消费，避免落入 game-action 路径造成第 2 次
    -- 派发与重复/串扰 warn。
    intent_dispatcher.dispatch_view_command(state, intent)
    return
  end
  if turn_action_port.should_block(state, intent, action_port) then return end
  if not game then
    logger.warn("ui intent without game:", tostring(intent_type))
    return
  end
  if _dispatch_game_action(state, game, intent, opts, action_port) then return end
  intent_dispatcher.dispatch_view_command(state, intent)
end

return intent_dispatcher

