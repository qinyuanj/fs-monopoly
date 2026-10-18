local number_utils = require("src.foundation.number")

local tip_text = {}

local UNKNOWN_TILE = "未知地块"
local UNKNOWN_PLAYER = "未知玩家"

local function _board_of(state)
  local game = state and state.game or nil
  return game and game.board or nil
end

local function _tile_at(state, tile_index)
  local board = _board_of(state)
  if board and board.get_tile then
    return board:get_tile(tile_index)
  end
  return nil
end

local function _resolve_tile_name(state, tile_index)
  if not state or not tile_index then
    return UNKNOWN_TILE
  end
  local tile = _tile_at(state, tile_index)
  if tile and tile.name then
    return tile.name
  end
  return UNKNOWN_TILE
end

local function _game_of(state)
  return state and state.game or nil
end

local function _player_of(state, player_id)
  local game = _game_of(state)
  if game and game.find_player_by_id then
    return game:find_player_by_id(player_id) or nil
  end
  return nil
end

local function _resolve_player_name(state, player_id)
  if not player_id then
    return UNKNOWN_PLAYER
  end
  local player = _player_of(state, player_id)
  if player and player.name then
    return player.name
  end
  return tostring(player_id)
end

local function _resolve_item_name(anim)
  return tostring(anim.item_name or anim.item_id or "?")
end

local function _build_roll_text(_, anim)
  local rolls = anim.rolls and table.concat(anim.rolls, ",") or "?"
  local total = anim.total or "?"
  return "投骰动画：" .. rolls .. " => " .. tostring(total)
end

local function _build_tile_text(prefix)
  return function(state, anim)
    return prefix .. _resolve_tile_name(state, anim.tile_index)
  end
end

local function _build_player_tile_text(verb)
  return function(state, anim)
    return _resolve_player_name(state, anim.player_id) .. verb .. _resolve_tile_name(state, anim.tile_index)
  end
end

local function _cleared_obstacle_parts(anim)
  local rb = anim.roadblock_cleared or 0
  local mn = anim.mine_cleared or 0
  local parts = {}
  if rb > 0 then
    parts[#parts + 1] = tostring(rb) .. " 个路障"
  end
  if mn > 0 then
    parts[#parts + 1] = tostring(mn) .. " 个地雷"
  end
  return parts
end

local function _build_clear_obstacles_text(state, anim)
  local player_name = _resolve_player_name(state, anim.player_id)
  local parts = _cleared_obstacle_parts(anim)
  if #parts == 0 then
    return player_name .. " 的清障机器人出动，前方没有障碍"
  end
  return player_name .. " 的清障机器人出动，清除了 " .. table.concat(parts, "、")
end

local function _build_chance_text(_, anim)
  return "机会卡展示：" .. tostring(anim.card_desc or anim.card_id or "?")
end

local function _build_item_use_text(_, anim)
  return "道具生效：" .. _resolve_item_name(anim)
end

local function _build_item_gain_text(state, anim)
  return _resolve_player_name(state, anim.player_id) .. " 获得道具卡：" .. _resolve_item_name(anim)
end

local function _build_item_target_player_text(state, anim)
  local player_name = _resolve_player_name(state, anim.player_id)
  local target_name = _resolve_player_name(state, anim.target_player_id)
  return player_name .. " 对 " .. target_name .. " 使用了 " .. _resolve_item_name(anim)
end

local function _build_teleport_text(state, anim)
  local player_name = _resolve_player_name(state, anim.player_id)
  return player_name .. " 被传送到 "
    .. _resolve_tile_name(state, anim.to_index)
end

local function _build_debug_move_text(state, anim)
  return "位移动画：" .. _resolve_player_name(state, anim.player_id)
    .. " 从 " .. _resolve_tile_name(state, anim.from_index)
    .. " 到 " .. _resolve_tile_name(state, anim.to_index)
end

local function _build_mine_trigger_text(state, anim)
  local player_name = _resolve_player_name(state, anim.player_id)
  return "地雷触发：" .. player_name .. " 从 "
    .. _resolve_tile_name(state, anim.from_index)
    .. " 到 "
    .. _resolve_tile_name(state, anim.to_index)
end

local function _build_cash_receive_text(state, anim)
  local player_name = _resolve_player_name(state, anim.player_id)
  local amount = anim.amount or "?"
  return "收钱动画：" .. player_name .. " +" .. number_utils.format_integer_part(amount)
end

local TIP_BUILDERS = {
  roll = _build_roll_text,
  roadblock = _build_tile_text("路障动画：放置在 "),
  mine = _build_tile_text("地雷动画：埋设在 "),
  missile = _build_player_tile_text(" 发射导弹轰炸 "),
  monster = _build_player_tile_text(" 释放怪兽攻击 "),
  clear_obstacles = _build_clear_obstacles_text,
  upgrade_land = _build_tile_text("加盖动画："),
  chance = _build_chance_text,
  item_gain_popup = _build_item_gain_text,
  item_use = _build_item_use_text,
  item_target_player = _build_item_target_player_text,
  move_effect = _build_debug_move_text,
  teleport_effect = _build_teleport_text,
  forced_relocation = _build_debug_move_text,
   roadblock_trigger = _build_tile_text("路障触发："),
   mine_trigger = _build_mine_trigger_text,
   cash_receive = _build_cash_receive_text,
}

function tip_text.build(state, anim)
  if anim.focus_text and anim.focus_text ~= "" then
    return anim.focus_text
  end
  local builder = TIP_BUILDERS[anim.kind]
  return builder and builder(state, anim) or nil
end

return tip_text

