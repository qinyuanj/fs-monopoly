local timing = require("src.config.gameplay.timing")
local number_utils = require("src.foundation.number")
local runtime_state = require("src.state.runtime")
local event_feed = require("src.rules.ports.event_feed")
local event_kinds = require("src.config.gameplay.event_kinds")
local logger = require("src.foundation.log")
local control = require("src.player.control")

local afk_signal = {}

local function _counts(state)
  if type(state) ~= "table" then
    return nil
  end
  local turn_runtime = runtime_state.ensure_turn_runtime(state)
  if type(turn_runtime.afk_timeout_counts) ~= "table" then
    turn_runtime.afk_timeout_counts = {}
  end
  return turn_runtime.afk_timeout_counts
end

local function _resolve_player(game, role_id)
  if not (game and type(game.find_player_by_id) == "function") then
    return nil
  end
  local ok, player = pcall(game.find_player_by_id, game, role_id)
  if ok then
    return player
  end
  return nil
end

local function _threshold()
  local value = number_utils.to_integer(timing.afk.consecutive_timeout_count)
  if value and value > 0 then
    return value
  end
  return 2
end

function afk_signal.is_timeout_eligible(player)
  return player ~= nil
    and not control.is_delegated(player)
    and not control.is_replacement_computer(player)
    and player.eliminated ~= true
end

local function _eligible(game, player)
  return game ~= nil
    and game.finished ~= true
    and player ~= nil
    and not control.is_replacement_computer(player)
    and player.eliminated ~= true
end

local function _clear_count(counts, player, role_id)
  local key = player and player.id or role_id
  if key ~= nil then
    counts[key] = nil
  end
end

local function _resolve_counted_player(game, counts, role_id)
  local player = _resolve_player(game, role_id)
  if not _eligible(game, player) or control.is_delegated(player) then
    _clear_count(counts, player, role_id)
    return nil
  end
  return player
end

local function _publish_afk_placement(game, player, count, window_kind)
  event_feed.publish(game, {
    kind = event_kinds.afk_auto_enabled,
    text = tostring(player.name) .. " 已进入托管",
    tip = true,
    source = "afk",
    role_id = player.id,
    consecutive_timeout_count = count,
    window_kind = window_kind,
  })
end

function afk_signal.reset(state)
  local turn_runtime = runtime_state.ensure_turn_runtime(state)
  turn_runtime.afk_timeout_counts = {}
end

-- 连续超时计数自增(CRAP 门禁):缺省 0 的兜底收敛到本函数,
-- on_timeout_fallback 只留阈值判定与托管切换。
local function _bump_count(counts, key)
  local count = (counts[key] or 0) + 1
  counts[key] = count
  return count
end

function afk_signal.on_timeout_fallback(game, state, role_id, window_kind)
  local counts = _counts(state)
  if counts == nil then
    return false
  end
  local player = _resolve_counted_player(game, counts, role_id)
  if player == nil then
    return false
  end

  local count = _bump_count(counts, player.id)
  if count < _threshold() then
    return false
  end

  counts[player.id] = nil
  if not control.enable_afk_delegation(player).changed then
    return false
  end
  logger.info_unlimited(
    "[AFK]",
    "role_id=" .. tostring(player.id),
    "source=afk",
    "count=" .. tostring(count),
    "window=" .. tostring(window_kind)
  )
  _publish_afk_placement(game, player, count, window_kind)
  return true
end

function afk_signal.on_real_input(game, state, role_id)
  local counts = _counts(state)
  if counts == nil then
    return false
  end
  local player = _resolve_player(game, role_id)
  _clear_count(counts, player, role_id)
  return player ~= nil
end

function afk_signal.prune(game, state)
  local counts = _counts(state)
  if counts == nil then
    return
  end
  for role_id in pairs(counts) do
    local player = _resolve_player(game, role_id)
    if not _eligible(game, player) or control.is_delegated(player) then
      counts[role_id] = nil
    end
  end
end

return afk_signal

