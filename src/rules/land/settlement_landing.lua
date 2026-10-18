local effect_pipeline = require("src.rules.effects.pipeline")
local land_actions = require("src.rules.land.actions")
local landing_defs = require("src.rules.land.landing_defs")
local pricing = require("src.rules.land.pricing")
local shared = require("src.rules.land.settlement_shared")

local landing = {}

local max_landing_depth = 10

local function _is_relocation_action_anim(entry)
  return entry and (entry.kind == "move_effect" or entry.kind == "teleport_effect" or entry.kind == "forced_relocation")
end

local function _queue_has_relocation_action_anim(queue)
  if type(queue) ~= "table" then
    return false
  end
  for _, entry in ipairs(queue) do
    if _is_relocation_action_anim(entry) then
      return true
    end
  end
  return false
end

local function _has_pending_relocation_action_anim(game)
  if not (game and game.turn) then
    return false
  end
  if _is_relocation_action_anim(game.turn.action_anim) then
    return true
  end
  return _queue_has_relocation_action_anim(game.turn.action_anim_queue)
end

local function _tile_level(st)
  return (st and st.level) or 0
end

local function _landing_optional_cost(effect_id, tile, game)
  if effect_id ~= "upgrade_land" or tile == nil or game == nil then
    return nil
  end
  local st = land_actions.safe_tile_state(game, tile)
  return pricing.upgrade_cost(tile, _tile_level(st))
end

local function _build_move_followup_result(target_player, out, wait_key)
  return {
    ok = true,
    waiting = true,
    reason = "followup_landing_wait",
    [wait_key] = true,
    next_state = "move_followup",
    next_args = {
      mode = "resolve_landing",
      player_id = target_player.id,
      move_result = out.move_result,
    },
  }
end

local _begin_resolved_landing

local function _resolve_target_player(game, fallback_player, out)
  if out.player_id == nil then
    return fallback_player
  end
  return shared.resolve_actor(game, out.player_id)
end

local function _tile_index_of(out, target_player)
  return out.board_index or target_player.position
end

local function _board_ready(game, board_index)
  return board_index ~= nil and game ~= nil and game.board ~= nil
end

local function _resolve_next_tile(game, target_player, out)
  if target_player == nil then
    return nil
  end
  local board_index = _tile_index_of(out, target_player)
  if not _board_ready(game, board_index) then
    return nil
  end
  return game.board:get_tile(board_index)
end

local function _landing_depth_rejected(out)
  local rejected = shared.reject("landing_depth_exceeded")
  rejected.followup = out
  return rejected
end

local function _followup_wait_key(game, out)
  if out.wait_move_anim == true then
    return "wait_move_anim"
  end
  if _has_pending_relocation_action_anim(game) then
    return "wait_action_anim"
  end
  return nil
end

local function _continue_followup_landing(game, target_player, next_tile, out, depth)
  return _begin_resolved_landing(game, target_player, next_tile, {
    move_result = out.move_result,
  }, depth + 1)
end

local function _resolve_followup_landing(game, player, out, depth)
  if depth >= max_landing_depth then
    return _landing_depth_rejected(out)
  end

  local target_player = _resolve_target_player(game, player, out)
  local next_tile = _resolve_next_tile(game, target_player, out)
  if next_tile == nil then
    return out
  end
  local wait_key = _followup_wait_key(game, out)
  if wait_key then
    return _build_move_followup_result(target_player, out, wait_key)
  end
  return _continue_followup_landing(game, target_player, next_tile, out, depth)
end

local function _should_stop_landing_result(out)
  return type(out) == "table" and (out.ok == false or out.status == "rejected" or out.kind == "need_landing")
end

function _begin_resolved_landing(game, player, tile, context, depth)
  -- depth 是必传实参:入口(begin_landing_settlement)按 context.depth or 0 给初值,
  -- 递归(_continue_followup_landing)传 depth + 1。这里不再写第二份默认值——
  -- 「depth or context.depth or 0」的整条默认链在两个调用方面前恒被短路,
  -- 变异体全是等价死尾(#259 清扫裁定:等价变异体优先删冗余源码)。
  context = context or {}

  local game_ctx = shared.build_game_ctx(game, context.move_result, "landing")
  local function handle_need_landing(out)
    return _resolve_followup_landing(game, player, out, depth)
  end

  local result = effect_pipeline.run(landing_defs, player, tile, game_ctx, {
    next_state = "post_action",
    next_args = { player = player },
    optional_choice_kind = "landing_optional_effect",
    optional_reason = "landing_optional",
    optional_allow_cancel = true,
    optional_cancel_label = "跳过",
    optional_cost_resolver = _landing_optional_cost,
    on_need_landing = handle_need_landing,
    stop_if = _should_stop_landing_result,
  })
  return shared.with_ok(result) or shared.settled()
end

local function _landing_opts(context)
  return context or {}, (context or {}).depth or 0
end

function landing.begin_landing_settlement(game, actor_id, context)
  if game == nil then
    return shared.reject("missing_game")
  end
  local actor = shared.resolve_actor(game, actor_id)
  if actor == nil then
    return shared.reject("missing_actor")
  end
  local tile = shared.resolve_tile(game, actor, context)
  if tile == nil then
    return shared.reject("missing_tile")
  end
  local opts, depth = _landing_opts(context)
  return _begin_resolved_landing(game, actor, tile, opts, depth)
end

landing._M_test = {
  _has_pending_relocation_action_anim = _has_pending_relocation_action_anim,
}

return landing

