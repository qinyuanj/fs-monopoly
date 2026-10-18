local board_slice = require("src.ui.view.board_slice")
local item_slice = require("src.ui.view.item_slice")
local choice_slice = require("src.ui.view.choice_slice")
local panel_slice = require("src.ui.view.panel_slice")
local memo = require("src.foundation.memo")
local number_utils = require("src.foundation.number")
local role_id_utils = require("src.foundation.identity")

local model_api = {}

local FALLBACK_CURRENT_PLAYER_NAME = "-"
local FALLBACK_CURRENT_PLAYER_CASH = 0
local FALLBACK_CURRENT_PLAYER_ID = nil

local function _resolve_current_player(game)
  local turn = game.turn
  local players = game.players
  assert(turn ~= nil and players ~= nil, "missing turn or players")
  local idx = number_utils.to_integer(turn.current_player_index)
  if idx == nil then
    return nil, turn,
      string.format("invalid current player index: index=%s, player_count=%d", tostring(turn.current_player_index), #players)
  end
  local current = players[idx]
  if current == nil then
    return nil, turn,
      string.format("current player not found: index=%s, player_count=%d", tostring(idx), #players)
  end
  return current, turn
end

local function _build_ui_env(state, game)
  local winner = game.winner
  local winner_name = game.winner_names or (winner and assert(winner.name, "missing winner name"))
  return {
    game = game,
    ui_state = state,
    last_turn = game.last_turn,
    finished = game.finished,
    winner_name = winner_name,
  }
end

local function _resolve_current_player_meta(game, current)
  if current == nil then
    return FALLBACK_CURRENT_PLAYER_NAME, FALLBACK_CURRENT_PLAYER_CASH, FALLBACK_CURRENT_PLAYER_ID
  end
  local current_cash = FALLBACK_CURRENT_PLAYER_CASH
  if game ~= nil and type(game.player_cash) == "function" then
    current_cash = game:player_cash(current)
  end
  return current.name or FALLBACK_CURRENT_PLAYER_NAME, current_cash,
    role_id_utils.normalize(current.id)
end

local function _fill_meta(model, env, current, turn)
  local current_name, current_cash, current_player_id = _resolve_current_player_meta(env.game, current)
  model.current_player_name = current_name
  model.current_player_cash = current_cash
  model.turn_count = turn.turn_count
  model.current_player_id = current_player_id
  model.board_tile_count = board_slice.tile_count()
  model.last_turn = env.last_turn
  model.finished = env.finished
  model.winner_name = env.winner_name
  return model
end

-- 派生路由：依赖声明与派生逻辑同处，新增派生状态只需在此登记一处。
-- 快照投影把 dirty 表归一为标量字段；inventory 布尔域投影为 has_inventory。
-- 路由表数据化（CRAP 门禁 #452）：每条路由 = 键 → 依赖字段表，compute 用
-- _any_dirty 遍历——or 决策点从 compute 本体（cx=18）摊到遍历器与数据上，
-- 行为等价（_any_dirty 返回首个 truthy 值或 nil，与原 or 链逐位一致）。
local function _route_snapshot(dirty)
  return {
    players = not not dirty.players,
    board_tiles = not not dirty.board_tiles,
    turn = not not dirty.turn,
    market = not not dirty.market,
    turn_countdown = not not dirty.turn_countdown,
    ui = not not dirty.ui,
    has_inventory = not not dirty.inventory,
  }
end

local _route_deps = {
  board = { "players", "board_tiles", "turn" },
  auto_labels = { "players", "turn", "ui" },
  panel_turn_label = { "turn", "turn_countdown", "ui" },
  panel_player_rows = { "players", "board_tiles", "ui" },
  panel_auto_label = { "players", "turn", "ui" },
  choice_refresh = { "turn", "market", "ui" },
  player_meta = { "players", "turn" },
}
local _slots_deps = { "players", "turn", "ui", "has_inventory" }

-- or 链的等价遍历：返回首个 truthy 依赖值，全空返 nil（与
-- `s.a or s.b or s.c` 结果逐位一致，包括 nil 而非 false 的出口语义）。
local function _any_dirty(s, deps)
  for _, dep in ipairs(deps) do
    if s[dep] then
      return s[dep]
    end
  end
  return nil
end

local _routes_memo = memo.new(function(s)
  local slots = _any_dirty(s, _slots_deps)
  return {
    board = _any_dirty(s, _route_deps.board),
    auto_labels = _any_dirty(s, _route_deps.auto_labels),
    panel = {
      turn_label = _any_dirty(s, _route_deps.panel_turn_label),
      player_rows = _any_dirty(s, _route_deps.panel_player_rows),
      auto_label = _any_dirty(s, _route_deps.panel_auto_label),
    },
    slots = slots,
    choice_refresh = _any_dirty(s, _route_deps.choice_refresh),
    choice_owner = s.players or slots,
    player_meta = _any_dirty(s, _route_deps.player_meta),
  }
end, _route_snapshot)

function model_api.build(game, env)
  assert(game ~= nil, "missing game")
  env = env or _build_ui_env(nil, game)
  local ui_state = env.ui_state
  local ui_runtime = ui_state and ui_state.ui
  local current, turn = _resolve_current_player(game)
  local _, _, current_player_id = _resolve_current_player_meta(game, current)
  local slot_count = item_slice.resolve_slot_count(ui_runtime)
  local item_slots_by_player = item_slice.build_item_slots_by_player(game.players, slot_count)
  local delegated_by_player = item_slice.build_delegated_by_player(env.player_control_by_player)
  local item_slots = role_id_utils.read(item_slots_by_player, current_player_id)
  if not item_slots then
    item_slots = item_slice.build_item_slots_for_player(current, slot_count)
  end
  local choice, market = choice_slice.build_choice_and_market(game, env, ui_state)

  local model = {
    board = board_slice.build(game, env, turn),
    panel = panel_slice.build(game, env, turn, current_player_id, delegated_by_player),
    item_slots = item_slots,
    item_slots_by_player = item_slots_by_player,
    delegated_by_player = delegated_by_player,
    item_choice_owner_id = item_slice.resolve_item_choice_owner_id(game, choice, current_player_id),
    choice = choice,
    market = market,
  }
  return _fill_meta(model, env, current, turn)
end

local function _resolve_update_ctx(env, dirty, game)
  local r_env = env or _build_ui_env(nil, game)
  local r_dirty = dirty or {}
  local ui_state = r_env.ui_state
  return r_env, r_dirty, ui_state and ui_state.ui
end

local function _update_item_slots_model(model, game, current, current_player_id, ui_runtime)
  local slot_count = item_slice.resolve_slot_count(ui_runtime)
  local by_player = item_slice.build_item_slots_by_player(game.players, slot_count)
  model.item_slots_by_player = by_player
  model.item_slots = role_id_utils.read(by_player, current_player_id) or item_slice.build_item_slots_for_player(current, slot_count)
end

local function _update_choice_market(model, game, r_env, current_player_id, routes)
  if routes.choice_refresh then
    local choice, market = choice_slice.build_choice_and_market(game, r_env, r_env.ui_state)
    model.choice = choice
    model.market = market
    model.item_choice_owner_id = item_slice.resolve_item_choice_owner_id(game, choice, current_player_id)
  elseif routes.choice_owner then
    model.item_choice_owner_id = item_slice.resolve_item_choice_owner_id(game, model.choice, current_player_id)
  end
end

local function _update_player_meta_model(model, routes, current_name, current_cash, turn, current_player_id)
  if routes.player_meta then
    model.current_player_name = current_name
    model.current_player_cash = current_cash
    model.turn_count = turn.turn_count
    model.current_player_id = current_player_id
  end
end

function model_api.update(prev, game, env, dirty)
  assert(game, "missing game")
  if not prev then
    return model_api.build(game, env)
  end
  local r_env, r_dirty, ui_runtime = _resolve_update_ctx(env, dirty, game)
  local routes = _routes_memo:get(r_dirty)
  local current, turn = _resolve_current_player(game)
  local current_name, current_cash, current_player_id = _resolve_current_player_meta(game, current)
  local model = prev

  if routes.board then
    model.board = board_slice.update(model.board, game, r_env, turn)
  end
  if routes.auto_labels then
    model.delegated_by_player = item_slice.build_delegated_by_player(r_env.player_control_by_player)
  end

  model.panel = panel_slice.update(
    model.panel, game, r_env, turn, current_player_id,
    model.delegated_by_player,
    routes.panel
  )

  if routes.slots then
    _update_item_slots_model(model, game, current, current_player_id, ui_runtime)
  end

  _update_choice_market(model, game, r_env, current_player_id, routes)
  _update_player_meta_model(model, routes, current_name, current_cash, turn, current_player_id)

  model.board_tile_count = board_slice.tile_count()
  model.last_turn = r_env.last_turn
  model.finished = r_env.finished
  model.winner_name = r_env.winner_name

  return model
end

return model_api

