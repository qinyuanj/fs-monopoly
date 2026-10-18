local settlement = require("src.rules.land.settlement")
local blocking = require("src.turn.waits.blocking")

-- 落地结算完成、无 res.waiting 时进入 post_action 的等待路由。
-- 等价于 wait_action_anim 路径对固定 post_action 目标的委托(见 Task 2 行为保持证明)。
local function _resolve_finished_landing_state(game, player)
  return blocking.next_wait_state(game, "post_action", { player = player }, true, false)
end

local function _resolve_landing_wait_args(res, player, move_result)
  return res.next_state or "landing", res.next_args or { player = player, move_result = move_result }
end

local function _resolve_waiting_landing_result(game, res, player, move_result)
  local next_state, next_args = _resolve_landing_wait_args(res, player, move_result)
  return blocking.next_wait_state(game, next_state, next_args, res.wait_action_anim, res.wait_move_anim)
end

local function _phase_land(turn_mgr, args)
  local player = args.player
  local move_result = args.move_result
  local game = turn_mgr.game
  local tile = game.board:get_tile(player.position)

  local res = settlement.begin_landing_settlement(game, player.id, {
    tile = tile,
    move_result = move_result,
  })
  if res and res.waiting then
    return _resolve_waiting_landing_result(game, res, player, move_result)
  end
  return _resolve_finished_landing_state(game, player)
end

return {
  run = _phase_land,
  _resolve_wait_state = blocking.next_wait_state,
  resolve_wait_state = blocking.next_wait_state,
}

