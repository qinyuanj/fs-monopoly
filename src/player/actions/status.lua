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

-- 行为测试公共查询：test_land_actions 观察免租结算是否消费或保留一次性效果。
function status_ops.has_pending_free_rent(_self, player)
  return _peek_status_flag(player, "pending_free_rent")
end

-- 一次性免租：命中则清除并返回 true。
function status_ops.consume_pending_free_rent(self, player)
  return _consume_status_flag(self, player, "pending_free_rent")
end

-- 行为测试公共查询：test_land_tax_detention 观察税务结算后的免税效果状态。
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

