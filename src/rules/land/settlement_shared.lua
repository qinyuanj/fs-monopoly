local effect_runner = require("src.rules.effects.runner")

local shared = {}

function shared.reject(reason)
  return {
    ok = false,
    status = "rejected",
    reason = reason,
  }
end

function shared.settled()
  return {
    ok = true,
    status = "settled",
    settled = true,
  }
end

function shared.with_ok(result)
  if type(result) == "table" and result.ok == nil then
    result.ok = true
  end
  return result
end

function shared.resolve_actor(game, actor_id)
  if not (game and type(game.find_player_by_id) == "function") then
    return nil
  end
  return game:find_player_by_id(actor_id)
end

local function _resolve_board(game)
  return game and game.board or nil
end

local function _call_board_tile_method(board, method_name, value)
  local method = board and board[method_name] or nil
  if value == nil or type(method) ~= "function" then
    return nil
  end
  return method(board, value)
end

local function _context_tile(context)
  return context and context.tile or nil
end

local function _resolve_board_tile(board, actor, context)
  if context.tile_id ~= nil then
    return _call_board_tile_method(board, "get_tile_by_id", context.tile_id)
  end
  local index = context.board_index or (actor and actor.position)
  return _call_board_tile_method(board, "get_tile", index)
end

function shared.resolve_tile(game, actor, context)
  context = context or {}
  local tile = _context_tile(context)
  if tile ~= nil then
    return tile
  end
  local board = _resolve_board(game)
  if board == nil then
    return nil
  end
  return _resolve_board_tile(board, actor, context)
end

function shared.build_game_ctx(game, move_result, phase_default)
  return effect_runner.build_game_ctx(game, move_result, {
    phase_default = phase_default or "landing",
    on_landing = true,
  })
end

function shared.option_id_from_action(action)
  return action and action.option_id or nil
end

function shared.choice_meta(choice)
  local meta = choice and choice.meta or nil
  if type(meta) ~= "table" then
    return nil, shared.reject("missing_landing_choice_meta")
  end
  return meta
end

function shared.resolve_choice_player(game, meta)
  local player = shared.resolve_actor(game, meta.player_id)
  if player == nil then
    return nil, shared.reject("missing_actor")
  end
  return player
end

function shared.resolve_choice_tile(game, player, meta)
  local tile = shared.resolve_tile(game, player, { tile_id = meta.tile_id })
  if tile == nil then
    return nil, shared.reject("missing_tile")
  end
  return tile
end

return shared

