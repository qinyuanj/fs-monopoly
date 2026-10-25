local gameplay_read_port = require("src.ui.view.gameplay_read_port")
local number_utils = require("src.foundation.number")
local role_avatar = require("src.ui.view.role_avatar")
local runtime_ports = require("src.foundation.ports.runtime_ports")

local panel = {}
local _ZERO = number_utils.to_integer("0")

local function _normalize_integer_value(value)
  local normalized = number_utils.to_integer(value)
  if normalized == nil then
    return _ZERO
  end
  return math.max(normalized, _ZERO)
end

local function _resolve_role(player)
  if not player or player.id == nil then
    return nil
  end
  return runtime_ports.resolve_role(player.id)
end

local function _valid_name(role_name)
  return role_name ~= nil and role_name ~= ""
end

local function _resolve_role_name(role)
  if not role or type(role.get_name) ~= "function" then
    return nil
  end
  local ok, role_name = pcall(role.get_name)
  if not ok or not _valid_name(role_name) then
    return nil
  end
  return role_name
end

local _empty_status = {
  name = "",
  avatar = nil,
  eliminated = false,
  cash_value = nil,
  total_assets_value = nil,
  cash = "",
  land_count = "",
  total_assets = "",
}

local _cached_statuses = {
  {},
  {},
  {},
  {},
}
local _cached_cash_values = {}
local _cached_land_values = {}
local _cached_total_values = {}

local function _read_player_cash(game, player)
  if game == nil or type(game.player_cash) ~= "function" then
    return _ZERO
  end
  return _normalize_integer_value(game:player_cash(player))
end

local function _tile_of(board, tile_id)
  return board and board.get_tile_by_id and board:get_tile_by_id(tile_id) or nil
end

-- 土地类地块按其等级累加地块总投入(口径唯一在 gameplay_read_port);非土地或地块缺省时总额不变。
local function _accumulate_tile_invested(tile, total)
  if tile and tile.type == "land" then
    return total + gameplay_read_port.total_land_invested(tile, tile.level)
  end
  return total
end

local function _accumulate_player_assets(game, player, board)
  local cash = _read_player_cash(game, player)
  local land_count = 0
  local total = cash
  for tile_id in pairs(player.properties or {}) do
    land_count = land_count + 1
    total = _accumulate_tile_invested(_tile_of(board, tile_id), total)
  end
  return cash, land_count, total
end

local function _build_player_label(player_name, eliminated)
  local display_name = player_name or ""
  if eliminated then
    return display_name .. " (出局)"
  end
  return display_name
end

local function _sync_cached_label(cache, index, value, prefix, current_label)
  if cache[index] == value then
    return current_label
  end
  cache[index] = value
  return prefix .. number_utils.format_integer_part(value)
end

local function _build_player_status(game, player, board, index)
  local status = _cached_statuses[index]
  local role = _resolve_role(player)
  local display_name = _resolve_role_name(role) or player.name
  status.name = _build_player_label(display_name, player.eliminated == true)
  status.avatar = role_avatar.resolve_from_role(role)
  status.eliminated = player.eliminated == true
  local cash, land_count, total = _accumulate_player_assets(game, player, board)
  status.cash_value = cash
  local normalized_total = _normalize_integer_value(total)
  status.total_assets_value = normalized_total
  local display_cash = cash
  status.cash = _sync_cached_label(_cached_cash_values, index, display_cash, "现金: ", status.cash)
  status.land_count = _sync_cached_label(_cached_land_values, index, land_count, "地块: ", status.land_count)
  local display_total = normalized_total
  status.total_assets = _sync_cached_label(_cached_total_values, index, display_total, "总资产: ", status.total_assets)
  return status
end

local _cached_turn_label_seconds
local _cached_turn_label

function panel.build_turn_label(_, countdown_seconds)
  local secs = countdown_seconds or 0
  if secs ~= _cached_turn_label_seconds then
    _cached_turn_label_seconds = secs
    _cached_turn_label = "倒计时:" .. tostring(secs)
  end
  return _cached_turn_label
end


local _status_out = {}

local function _build_status_row(game, player, board, index)
  if player then
    return _build_player_status(game, player, board, index)
  end
  return _empty_status
end

local function _fill_status_rows(game, players, board, count)
  for i = 1, count do
    _status_out[i] = _build_status_row(game, players[i], board, i)
  end
end

local function _trim_status_rows(count)
  for i = count + 1, #_status_out do
    _status_out[i] = nil
  end
end

local function _players_of(game)
  return game and game.players or {}
end

local function _board_of(game_obj)
  return game_obj and game_obj.board or nil
end

function panel.build_player_statuses(game, game_obj, max_players)
  local players = _players_of(game)
  local count = max_players or #players
  local board = _board_of(game_obj)
  _fill_status_rows(game, players, board, count)
  _trim_status_rows(count)
  return _status_out
end

function panel.build_auto_label(_auto_play)
  return "托管"
end

return panel

