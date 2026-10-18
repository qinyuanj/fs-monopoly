local common = require("src.player.actions.state_common")

local status_ops = {}

local function _status_field(holder, key)
  return holder and holder[key] or nil
end

function status_ops.set_player_status(self, player, key, value)
  local status = common.player_status_table(player)
  status[key] = value
  common.mark_players(self)
end

function status_ops.player_dice_count(_self, _player)
  return common.constants.default_dice_count
end

-- 骰子加倍：读归一化倍数（未设置或 <=1 一律视为 1，即无加倍）。
function status_ops.player_pending_dice_multiplier(_self, player)
  local pending = _status_field(_status_field(player, "status"), "pending_dice_multiplier")
  if not pending or pending <= 1 then
    return 1
  end
  return pending
end

-- 骰子加倍：消费——返回归一化倍数并复位为 1。
function status_ops.consume_pending_dice_multiplier(self, player)
  local pending = status_ops.player_pending_dice_multiplier(self, player)
  local status = common.player_status_table(player)
  status.pending_dice_multiplier = 1
  common.mark_players(self)
  return pending
end

-- 遥控骰子：设定待生效点数（values 为逐颗点数列表）。
function status_ops.set_pending_remote_dice(self, player, values)
  assert(type(values) == "table" and values[1] ~= nil, "invalid remote dice values")
  local status = common.player_status_table(player)
  status.pending_remote_dice = { values = values }
  common.mark_players(self)
end

-- 遥控骰子：只读点数列表；未设置返回 nil（投骰阶段读，回合清理时清除）。
function status_ops.peek_pending_remote_dice(_self, player)
  local pending = _status_field(_status_field(player, "status"), "pending_remote_dice")
  return _status_field(pending, "values")
end

local function _status_of(player)
  return player and player.status or nil
end

-- 扣留剩余回合（含当前回合口径）：被扣留期间恒 >= 1，计到 0 即解除。
function status_ops.detention_remaining(_self, player)
  local status = _status_of(player)
  local remaining = status and status.stay_turns or 0
  if remaining <= 0 then
    return 0
  end
  return remaining
end

-- 回合开始消耗一回合扣留：返回本回合玩家可见的含当前回合剩余（>= 1）；
-- 未被扣留时不改状态并返回 0。消费后 detention_remaining 即为减后剩余。
function status_ops.consume_detention_turn(self, player)
  local remaining_inclusive = status_ops.detention_remaining(self, player)
  if remaining_inclusive <= 0 then
    return 0
  end
  local status = common.player_status_table(player)
  status.stay_turns = remaining_inclusive - 1
  common.mark_players(self)
  return remaining_inclusive
end

function status_ops.player_own_turn_started_count(_self, player)
  local status = player and player.status or nil
  return status and status.own_turn_started_count or 0
end

function status_ops.increment_own_turn_started_count(self, player)
  local next_count = status_ops.player_own_turn_started_count(self, player) + 1
  local status = common.player_status_table(player)
  status.own_turn_started_count = next_count
  common.mark_players(self)
  return next_count
end

local function _peek_status_flag(player, key)
  local status = player and player.status or nil
  return (status and status[key]) == true
end

local function _consume_status_flag(self, player, key)
  if not _peek_status_flag(player, key) then
    return false
  end
  local status = common.player_status_table(player)
  status[key] = false
  common.mark_players(self)
  return true
end

function status_ops.has_pending_free_rent(_self, player)
  return _peek_status_flag(player, "pending_free_rent")
end

-- 一次性免租：命中则清除并返回 true。
function status_ops.consume_pending_free_rent(self, player)
  return _consume_status_flag(self, player, "pending_free_rent")
end

function status_ops.has_pending_tax_free(_self, player)
  return _peek_status_flag(player, "pending_tax_free")
end

-- 一次性免税：命中则清除并返回 true。
function status_ops.consume_pending_tax_free(self, player)
  return _consume_status_flag(self, player, "pending_tax_free")
end

function status_ops.set_player_eliminated(self, player, eliminated)
  player.eliminated = eliminated == true
  common.mark_players(self)
end

function status_ops.set_player_property(self, player, tile_id, owned)
  player.properties = player.properties or {}
  if owned then
    player.properties[tile_id] = true
  else
    player.properties[tile_id] = nil
  end
  common.mark_players(self)
end

function status_ops.clear_player_temporal_flags(self, player)
  local status = common.player_status_table(player)
  status.pending_dice_multiplier = 1
  status.pending_free_rent = false
  status.pending_tax_free = false
  status.pending_remote_dice = nil
  common.mark_players(self)
end

local function _clear_player_move_dir(player)
  local status = common.player_status_table(player)
  if status.move_dir == nil then
    return false
  end
  status.move_dir = nil
  return true
end

local function _board_map(game)
  return game and game.board and game.board.map or nil
end

local function _has_outer_map_context(game, player)
  local map = _board_map(game)
  return map ~= nil and map.outer_next ~= nil and player ~= nil and player.position ~= nil
end

local function _is_outer_tile(game, player)
  if not _has_outer_map_context(game, player) then
    return true
  end
  local tile = game.board:get_tile(player.position)
  if tile == nil then
    return true
  end
  return game.board.map.outer_next[tile.id] ~= nil
end

local function _stop_player_movement(game, player)
  if not _is_outer_tile(game, player) then
    return false
  end
  return _clear_player_move_dir(player)
end

local function _stop_all_players(game, players)
  local players_dirty = false
  for _, player in ipairs(players or {}) do
    if _stop_player_movement(game, player) then
      players_dirty = true
    end
  end
  return players_dirty
end

function status_ops.stop_all_players_movement(self)
  local players_dirty = _stop_all_players(self, self.players)
  if players_dirty then
    common.mark_players(self)
  end
end

return status_ops

--[[ mutate4lua-manifest
version=4
projectHash=4ec4f26b15e17e35
scope.0.id=chunk:src/player/actions/status.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=191
scope.0.semanticHash=b25f686bcfd6972b
scope.1.id=function:status_ops.set_player_status
scope.1.kind=function
scope.1.startLine=5
scope.1.endLine=9
scope.1.semanticHash=4ac86bf0b2f1b558
scope.2.id=function:status_ops.player_dice_count
scope.2.kind=function
scope.2.startLine=11
scope.2.endLine=13
scope.2.semanticHash=1cebdc42f47e2d00
scope.3.id=function:status_ops.player_pending_dice_multiplier
scope.3.kind=function
scope.3.startLine=16
scope.3.endLine=23
scope.3.semanticHash=8554b42fd743247a
scope.4.id=function:status_ops.consume_pending_dice_multiplier
scope.4.kind=function
scope.4.startLine=26
scope.4.endLine=32
scope.4.semanticHash=03d71c237f758ac5
scope.5.id=function:status_ops.set_pending_remote_dice
scope.5.kind=function
scope.5.startLine=35
scope.5.endLine=40
scope.5.semanticHash=7eeec3b2b19c6ab8
scope.6.id=function:status_ops.peek_pending_remote_dice
scope.6.kind=function
scope.6.startLine=43
scope.6.endLine=47
scope.6.semanticHash=b221ef427071cba0
scope.7.id=function:_status_of
scope.7.kind=function
scope.7.startLine=49
scope.7.endLine=51
scope.7.semanticHash=616a2ca60599c94f
scope.8.id=function:status_ops.detention_remaining
scope.8.kind=function
scope.8.startLine=54
scope.8.endLine=61
scope.8.semanticHash=bc9f02d3be386b6b
scope.9.id=function:status_ops.consume_detention_turn
scope.9.kind=function
scope.9.startLine=65
scope.9.endLine=74
scope.9.semanticHash=14e678c804e4682e
scope.10.id=function:status_ops.player_own_turn_started_count
scope.10.kind=function
scope.10.startLine=76
scope.10.endLine=79
scope.10.semanticHash=25baf1861cbdf1e0
scope.11.id=function:status_ops.increment_own_turn_started_count
scope.11.kind=function
scope.11.startLine=81
scope.11.endLine=87
scope.11.semanticHash=0658ef6d25f63696
scope.12.id=function:_peek_status_flag
scope.12.kind=function
scope.12.startLine=89
scope.12.endLine=92
scope.12.semanticHash=497edb7112d1d4fc
scope.13.id=function:_consume_status_flag
scope.13.kind=function
scope.13.startLine=94
scope.13.endLine=102
scope.13.semanticHash=00d40c39bd52232a
scope.14.id=function:status_ops.has_pending_free_rent
scope.14.kind=function
scope.14.startLine=104
scope.14.endLine=106
scope.14.semanticHash=740a2311e840efae
scope.15.id=function:status_ops.consume_pending_free_rent
scope.15.kind=function
scope.15.startLine=109
scope.15.endLine=111
scope.15.semanticHash=09b724016540ebed
scope.16.id=function:status_ops.has_pending_tax_free
scope.16.kind=function
scope.16.startLine=113
scope.16.endLine=115
scope.16.semanticHash=740a2311e840efae
scope.17.id=function:status_ops.consume_pending_tax_free
scope.17.kind=function
scope.17.startLine=118
scope.17.endLine=120
scope.17.semanticHash=09b724016540ebed
scope.18.id=function:status_ops.set_player_eliminated
scope.18.kind=function
scope.18.startLine=122
scope.18.endLine=125
scope.18.semanticHash=cefaeb90ff80c944
scope.19.id=function:status_ops.set_player_property
scope.19.kind=function
scope.19.startLine=127
scope.19.endLine=135
scope.19.semanticHash=ae8c37a8ca023215
scope.20.id=function:status_ops.clear_player_temporal_flags
scope.20.kind=function
scope.20.startLine=137
scope.20.endLine=144
scope.20.semanticHash=ae7d05343864c547
scope.21.id=function:_clear_player_move_dir
scope.21.kind=function
scope.21.startLine=146
scope.21.endLine=153
scope.21.semanticHash=fbface076cd4f4b2
scope.22.id=function:_is_outer_tile
scope.22.kind=function
scope.22.startLine=155
scope.22.endLine=164
scope.22.semanticHash=056c96307bea8ad2
scope.23.id=function:_stop_player_movement
scope.23.kind=function
scope.23.startLine=166
scope.23.endLine=171
scope.23.semanticHash=a2149c73c930feb7
scope.24.id=function:_stop_all_players
scope.24.kind=function
scope.24.startLine=173
scope.24.endLine=181
scope.24.semanticHash=65255be6b7d76dde
scope.25.id=function:status_ops.stop_all_players_movement
scope.25.kind=function
scope.25.startLine=183
scope.25.endLine=188
scope.25.semanticHash=a29276060f37d6fc
]]
