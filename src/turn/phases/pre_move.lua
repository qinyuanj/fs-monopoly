local item_phase = require("src.rules.items.phase")
local item_auto_play_context = require("src.turn.policies.item_play_context")
local dice_multiplier = require("src.turn.phases.dice_multiplier")
local phase_wait = require("src.turn.phases.phase_wait")

local function _resolve_phase_wait_result(phase_res, player, total, raw_total)
  return phase_wait.resolve_result(phase_res, "pre_move", player, total, raw_total)
end

local function _run_pre_move_item_phase(turn_mgr, player, total, raw_total)
  local phase_res = item_phase.run(turn_mgr, "pre_move", {
    player = player,
    auto_play = item_auto_play_context.build(turn_mgr.game, player),
    next_state = "pre_move",
    next_args = {
      player = player,
      total = total,
      raw_total = raw_total,
    },
  })
  if not (phase_res and phase_res.waiting) then
    return nil
  end
  return _resolve_phase_wait_result(phase_res, player, total, raw_total)
end

local function _phase_pre_move(turn_mgr, args)
  args = args or {}
  local game = turn_mgr.game
  local player = args.player or game:current_player()
  local raw_total = args.raw_total
  local total = args.total

  local waiting_state, waiting_args = _run_pre_move_item_phase(turn_mgr, player, total, raw_total)
  if waiting_state ~= nil then
    return waiting_state, waiting_args
  end

  local last_turn = assert(game.last_turn, "missing game.last_turn")
  local raw = assert(last_turn.raw_total, "missing game.last_turn.raw_total")
  local pending_multiplier = game:player_pending_dice_multiplier(player)
  local updated_total = dice_multiplier.apply_roll_total(game, raw, player)
  last_turn.total = updated_total
  if pending_multiplier > 1 then
    dice_multiplier.publish_breakdown(game, player, raw, updated_total, pending_multiplier)
  end
  return "move", { player = player, total = updated_total, raw_total = raw_total }
end

return _phase_pre_move

