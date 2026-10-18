local control = require("src.player.control")
local intent_dispatcher = require("src.turn.output.intent_dispatcher")
local landing_visual_hold = require("src.state.visual_hold")
local event_kinds = require("src.config.gameplay.event_kinds")
local event_feed = require("src.rules.ports.event_feed")
local dirty_tracker = require("src.state.dirty_tracker")

-- Late binding: tests may reload src.rules.market, so we require it on each call
-- to avoid holding a stale reference.
local function _market()
  return require("src.rules.market")
end

local move_followup = {}

local function _clear_pending_flag(game)
  if not (game and game.turn) then
    return
  end
  if game.turn.move_followup_pending == true then
    game.turn.move_followup_pending = false
    dirty_tracker.mark(game.dirty, "turn")
  end
end

local function _resolve_player(game, args)
  local player = args.player
  if player then
    return player
  end
  local player_id = args.player_id
  assert(player_id ~= nil, "missing move followup player_id")
  return assert(game:find_player_by_id(player_id), "missing move followup player: " .. tostring(player_id))
end

local function _build_resume_move_args(player, raw_total, interrupt, continue_key)
  return {
    player = player,
    raw_total = raw_total,
    [continue_key] = true,
    remaining_steps = interrupt.remaining_steps,
    facing = interrupt.facing,
    branch_parity = interrupt.branch_parity,
    entered_inner = interrupt.entered_inner,
  }
end

local function _resolve_auto_play_market(game, player, raw_total, interrupt)
  _market().auto.execute(game, player)
  if interrupt.remaining_steps and interrupt.remaining_steps > 0 then
    return "move", _build_resume_move_args(player, raw_total, interrupt, "continue_from_market")
  end
  return nil
end

local function _resolve_choice_wait(game, player, raw_total, interrupt, spec)
  intent_dispatcher.dispatch(game, { kind = "need_choice", choice_spec = spec })
  return "wait_choice", {
    next_state = "move",
    next_args = _build_resume_move_args(player, raw_total, interrupt, "continue_from_market"),
  }
end

local function _resolve_human_market(game, player, raw_total, interrupt)
  local spec, intent = _market().choice.build(player, game)
  if spec then
    return _resolve_choice_wait(game, player, raw_total, interrupt, spec)
  end
  if intent then
    intent_dispatcher.dispatch(game, intent)
  end
  return nil
end

local function _resolve_market_interrupt_wait(game, player, raw_total, interrupt)
  if control.is_computer_controlled(player) then
    return _resolve_auto_play_market(game, player, raw_total, interrupt)
  end
  return _resolve_human_market(game, player, raw_total, interrupt)
end

local function _handle_resume_turn_move(game, args)
  local player = _resolve_player(game, args)
  local move_result = assert(args.move_result, "missing move followup move_result")
  local raw_total = args.raw_total
  game.last_turn.move_result = move_result

  if move_result.market_interrupt then
    local interrupt = move_result.market_interrupt
    local next_state, next_args = _resolve_market_interrupt_wait(game, player, raw_total, interrupt)
    if next_state ~= nil then
      return next_state, next_args
    end
  end

  landing_visual_hold.start(game)
  return "landing", {
    player = player,
    move_result = move_result,
  }
end

local function _handle_resolve_landing(game, args)
  local player = _resolve_player(game, args)
  local move_result = args.move_result
  landing_visual_hold.start(game)
  return "landing", {
    player = player,
    move_result = move_result,
  }
end

local function _handle_apply_location_effects(game, args)
  local log_entries = args.log_entries or {}
  for _, entry in ipairs(log_entries) do
    event_feed.publish(game, {
      kind = event_kinds.move_followup,
      text = entry,
      tip = true,
    })
  end
  local effects = args.effects or {}
  for _, entry in ipairs(effects) do
    local player = assert(game:find_player_by_id(entry.player_id), "missing move followup effect player")
    game:player_apply_location_effect(player, entry.effect)
  end
  return args.next_state, args.next_args
end

local _MOVE_FOLLOWUP_HANDLERS = {
  resume_turn_move = _handle_resume_turn_move,
  resolve_landing = _handle_resolve_landing,
  apply_location_effects = _handle_apply_location_effects,
}

function move_followup.run(turn_mgr, args)
  local game = assert(turn_mgr and turn_mgr.game, "missing move followup game")
  args = args or {}
  _clear_pending_flag(game)

  local mode = args.mode
  local handler = _MOVE_FOLLOWUP_HANDLERS[mode]
  if handler == nil then
    error("unknown move followup mode: " .. tostring(mode))
  end
  return handler(game, args)
end

return move_followup

