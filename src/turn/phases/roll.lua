local dice_multiplier = require("src.turn.phases.dice_multiplier")
local event_kinds = require("src.config.gameplay.event_kinds")
local event_feed = require("src.rules.ports.event_feed")
local phase_wait = require("src.turn.phases.phase_wait")

-- 覆盖值不足 count 时，末位值重复填满。
local function _roll_from_override(count, override_values)
  local results = {}
  local total = 0
  for i = 1, count do
    local v = override_values[i] or override_values[#override_values]
    table.insert(results, v)
    total = total + v
  end
  return results, total
end

local function _roll_from_rng(count, rng)
  assert(rng and rng.next_int, "Dice.Roll requires rng")
  local results = {}
  local total = 0
  for _ = 1, count do
    local v = rng:next_int(1, 6)
    table.insert(results, v)
    total = total + v
  end
  return results, total
end

local function _roll_dice(count, override_values, rng)
  if override_values and #override_values > 0 then
    return _roll_from_override(count, override_values)
  end
  return _roll_from_rng(count, rng)
end

local function _resolve_dice_override(game, player)
  return game:peek_pending_remote_dice(player)
end

local function _log_roll_event(game, player, rolls, total)
  event_feed.publish(game, {
    kind = event_kinds.dice_roll,
    text = player.name .. " 投骰: [" .. table.concat(rolls, ",") .. "] => " .. tostring(total),
    tip = true,
  })
end

local function _store_roll_results(game, rolls, total, raw_total)
  game.last_turn.rolls = rolls
  game.last_turn.total = total
  game.last_turn.raw_total = raw_total
end

local function _perform_dice_roll(game, player)
  local dice_count = game:player_dice_count(player)
  local override = _resolve_dice_override(game, player)
  local rolls, raw_total = _roll_dice(dice_count, override, game.rng)
  local total = dice_multiplier.apply_roll_total(game, raw_total, player)
  _log_roll_event(game, player, rolls, total)
  _store_roll_results(game, rolls, total, raw_total)
  return rolls, raw_total, total
end

local function _should_wait_for_anim(game, skip_anim)
  if skip_anim then
    return false
  end
  local anim_gate_port = game.anim_gate_port
  return anim_gate_port and anim_gate_port.wait_action_anim or false
end

local function _build_anim_wait_result(player, rolls, raw_total, total)
  return "wait_action_anim", {
    next_state = "roll",
    next_args = {
      player = player,
      rolls = rolls,
      raw_total = raw_total,
      total = total,
      skip_anim = true,
    },
  }
end

local function _resolve_phase_wait_result(phase_res, player, total, raw_total)
  return phase_wait.resolve_result(phase_res, "move", player, total, raw_total)
end

local function _queue_roll_anim(game, player, rolls, total)
  game:queue_action_anim({
    kind = "roll",
    player_id = player.id,
    rolls = rolls,
    total = total,
  })
end

local function _phase_roll(turn_mgr, args)
  args = args or {}
  local game = turn_mgr.game
  local player = args.player or game:current_player()
  local rolls = args.rolls
  local raw_total = args.raw_total
  local total = args.total

  if not rolls then
    rolls, raw_total, total = _perform_dice_roll(game, player)
  end

  assert(game.anim_gate_port, "missing anim_gate_port")
  if _should_wait_for_anim(game, args.skip_anim) then
    _queue_roll_anim(game, player, rolls, total)
    return _build_anim_wait_result(player, rolls, raw_total, total)
  end

  return "pre_move", { player = player, total = total, raw_total = raw_total }
end

local function _phase_roll_direct(turn_mgr, args)
  local next_state, next_args = _phase_roll(turn_mgr, args)
  if next_state == "pre_move" then
    return "move", next_args
  end
  return next_state, next_args
end

local roll = {}
roll._roll_dice = _roll_dice
roll._phase_roll = _phase_roll_direct
roll._phase_roll_with_pre_move = _phase_roll
roll._resolve_phase_wait_result = _resolve_phase_wait_result
return roll

