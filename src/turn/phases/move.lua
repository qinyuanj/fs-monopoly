local movement = require("src.rules.movement")
local dice_multiplier = require("src.turn.phases.dice_multiplier")
local move_followup = require("src.turn.phases.move_followup")
local dirty_tracker = require("src.state.dirty_tracker")

local function _merge_move_args(out, extra)
  if extra == nil then
    return out
  end
  for key, value in pairs(extra) do
    out[key] = value
  end
  return out
end

local function _build_move_args(player, raw_total, extra)
  return _merge_move_args({
    player = player,
    raw_total = raw_total,
  }, extra)
end

local function _build_move_opts(args, branch_parity)
  local move_opts = { branch_parity = branch_parity }
  if args.continue_from_market then
    move_opts.direction = args.facing
    move_opts.branch_parity = args.branch_parity
    move_opts.entered_inner = args.entered_inner
  end
  return move_opts
end

local function _resolve_move_total(args, raw_total)
  if args.continue_from_market then
    return args.remaining_steps
  end
  return raw_total
end

local function _next_move_anim_seq(turn)
  local seq = (turn.move_anim_seq or 0) + 1
  turn.move_anim_seq = seq
  return seq
end

local function _build_move_anim_data(game, player, start_index, move_result)
  return {
    seq = _next_move_anim_seq(game.turn),
    player_id = player.id,
    from_index = start_index,
    to_index = player.position,
    visited = move_result.visited,
    steps = move_result.steps,
    stopped_on_roadblock = move_result.stopped_on_roadblock == true,
    market_interrupt = move_result.market_interrupt ~= nil and move_result.market_interrupt ~= false,
  }
end

local function _queue_move_anim(game, anim_data)
  game.turn.move_anim = anim_data
  dirty_tracker.mark_turn(game)
end

local function _build_wait_move_anim_result(player, raw_total, move_result)
  return "wait_move_anim", {
    next_state = "move_followup",
    next_args = _build_move_args(player, raw_total, {
      mode = "resume_turn_move",
      move_result = move_result,
      raw_total = raw_total,
    }),
  }
end

local function _run_move_followup(turn_mgr, player, raw_total, move_result)
  return move_followup.run(turn_mgr, {
    mode = "resume_turn_move",
    player = player,
    raw_total = raw_total,
    move_result = move_result,
  })
end

local function _perform_move(turn_mgr, game, player, total, move_opts)
  local start_index = player.position
  local move_result = movement.move(turn_mgr.game, player, total, move_opts)
  local anim_gate_port = assert(game.anim_gate_port, "missing anim_gate_port")
  if anim_gate_port.wait_move_anim == true then
    local anim_data = _build_move_anim_data(game, player, start_index, move_result)
    _queue_move_anim(game, anim_data)
    return _build_wait_move_anim_result(player, move_opts.branch_parity, move_result)
  end
  return _run_move_followup(turn_mgr, player, move_opts.branch_parity, move_result)
end

local function _phase_move(turn_mgr, args)
  local player = args.player
  local raw_total = args.raw_total
  assert(turn_mgr.game ~= nil, "missing game")
  local move_result = args.move_result
  local game = turn_mgr.game

  local total = dice_multiplier.apply_move_total(game, player, args.total, raw_total)
  local move_opts = _build_move_opts(args, total)
  total = _resolve_move_total(args, total)

  if not move_result then
    return _perform_move(turn_mgr, game, player, total, move_opts)
  end

  return _run_move_followup(turn_mgr, player, raw_total, move_result)
end

return _phase_move

