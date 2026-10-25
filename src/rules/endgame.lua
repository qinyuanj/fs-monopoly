local event_kinds = require("src.config.gameplay.event_kinds")
local achievement_progress = require("src.rules.ports.achievement_progress")
local event_feed = require("src.rules.ports.event_feed")
local monopoly_event = require("src.foundation.events")
local asset_total = require("src.rules.land.asset_total")
local bankruptcy = require("src.rules.elimination.bankruptcy")
local timing = require("src.config.gameplay.timing")

local M = {}

M.eliminate = bankruptcy.eliminate
M._try_call_life_die = bankruptcy._try_call_life_die
M._resolve_bankruptcy_text = bankruptcy._resolve_bankruptcy_text

local function _total_assets(game, player)
  return asset_total.player_total(game, player)
end

local function _winner_names(list)
  local names = {}
  for _, player in ipairs(list) do
    table.insert(names, player.name)
  end
  return table.concat(names, "、")
end

local function _assign_winner_fields(game, winners)
  game.winners = winners
  if #winners == 1 then
    game.winner = winners[1]
  else
    game.winner = nil
  end
  local names = _winner_names(winners)
  game.winner_names = names
  return names
end

local function _publish_victory(game, message)
  event_feed.publish(game, {
    kind = event_kinds.victory,
    text = message .. game.winner_names,
  })
end

local function _record_winner_progress(game, winners)
  local winner_ids = {}
  for _, player in ipairs(winners) do
    winner_ids[player.id] = true
    achievement_progress.game_won(game, player)
  end
  return winner_ids
end

local function _emit_game_finished(winners, winner_ids, names, message)
  monopoly_event.emit(monopoly_event.game.finished, {
    winners = winners,
    winner_ids = winner_ids,
    winner_names = names,
    message = message,
  })
end

local function _apply_winners(game, winners, message)
  local names = _assign_winner_fields(game, winners)
  _publish_victory(game, message)
  local winner_ids = _record_winner_progress(game, winners)
  _emit_game_finished(winners, winner_ids, names, message)
  game.finished = true
  return true
end

local function _positive_limit(value)
  if value == nil or value <= 0 then
    return nil
  end
  return value
end

local function _elapsed_game_time(game)
  if game.game_time_seconds ~= nil then return game.game_time_seconds end
  if game.elapsed_game_seconds ~= nil then return game.elapsed_game_seconds end
  if game.elapsed_seconds ~= nil then return game.elapsed_seconds end
  return game.current_time
end

local function _game_time_reached(game)
  local limit = _positive_limit(timing.game_time_limit_seconds)
  if limit == nil then
    return false
  end
  local elapsed = _elapsed_game_time(game)
  return elapsed ~= nil and elapsed >= limit
end

local function _turn_limit_reached(game)
  local turn_limit = _positive_limit(timing.turn_limit)
  if turn_limit == nil then
    return false
  end
  local turn_count = game.turn and game.turn.turn_count or nil
  return turn_count ~= nil and turn_count >= turn_limit
end

local function _record_candidate(winners, best, player, assets)
  if best == nil or assets > best then
    return assets, { player }
  end
  if assets == best then
    table.insert(winners, player)
  end
  return best, winners
end

local function _apply_asset_winners(game, alive)
  if #alive == 0 then
    return _apply_winners(game, {}, "游戏结束，无人生还")
  end
  local winners = {}
  local best = nil
  for _, player in ipairs(alive) do
    best, winners = _record_candidate(winners, best, player, _total_assets(game, player))
  end
  return _apply_winners(game, winners, "游戏结束，时间到，胜者:")
end

-- tick 层的门卫谓词:时钟没到点不必每帧跑完整 check_victory(省掉每帧 alive_players 分配)。
M.game_time_reached = _game_time_reached

local function _victory_by_alive_count(game, alive)
  if #alive == 1 then
    return _apply_winners(game, { alive[1] }, "游戏结束，胜者:")
  end
  return _apply_winners(game, {}, "游戏结束，无人生还")
end

function M.check_victory(self)
  if self.finished then
    return true
  end
  local alive = self:alive_players()
  if _game_time_reached(self) or _turn_limit_reached(self) then
    return _apply_asset_winners(self, alive)
  end
  if #alive <= 1 then
    return _victory_by_alive_count(self, alive)
  end
  return false
end

return M

