local runtime_ports = require("src.foundation.ports.runtime_ports")
local asset_total = require("src.rules.land.asset_total")

-- Custom player archive keys configured in the host editor: the host ranking
-- panels read and sort these values, so the Lua side only accumulates them.
local WIN_COUNT_KEY = 1001
local TOTAL_ASSETS_KEY = 1002

local leaderboard = {
  win_count_archive_key = WIN_COUNT_KEY,
  total_assets_archive_key = TOTAL_ASSETS_KEY,
  quit_reasons = {
    disconnect = true,
    manual_exit = true,
    crash = true,
  },
}

function leaderboard.is_quit_reason(reason)
  return leaderboard.quit_reasons[reason] == true
end

local function _add_archive_int(role_id, key, delta)
  if delta == 0 then
    return
  end
  local current = runtime_ports.get_archive_int(role_id, key)
  runtime_ports.set_archive_int(role_id, key, current + delta)
end

local function _winner_id_set(game)
  local ids = {}
  for _, winner in ipairs(game.winners or {}) do
    ids[winner.id] = true
  end
  return ids
end

local function _accumulate_player(game, player, winner_ids)
  if winner_ids[player.id] then
    _add_archive_int(player.id, WIN_COUNT_KEY, 1)
  end
  if not leaderboard.is_quit_reason(player.quit_reason) then
    _add_archive_int(player.id, TOTAL_ASSETS_KEY, asset_total.player_total(game, player))
  end
end

-- Accumulate this game's contributions into the host archives once: each
-- winner gains one win (胜利榜); every player still in the game adds their
-- remaining total assets (富豪榜). Players who quit mid-game are excluded, and
-- the run is skipped entirely when the host has custom archives disabled.
-- 结算触发与中途退出标记由 app 边界 leaderboard_settlement 接线
-- (gm.finished → settle;宿主角色退出触发器 → quit_reason)。
-- settle 前置守卫:游戏缺失/已结算过,或宿主关闭了自定义档案,整次结算跳过。
local function _should_settle(game)
  if game == nil or game.leaderboard_settled then
    return false
  end
  return runtime_ports.archives_enabled()
end

function leaderboard.settle(game)
  if not _should_settle(game) then
    return false
  end
  local winner_ids = _winner_id_set(game)
  for _, player in ipairs(game.players or {}) do
    _accumulate_player(game, player, winner_ids)
  end
  game.leaderboard_settled = true
  return true
end

return leaderboard

