-- 落位几何计算:地面位置解析、占用槽位与网格偏移。纯计算,不触碰宿主单元与动画状态。
local board_geometry = require("src.config.gameplay.camera_follow")
local unit_position = require("src.ui.render.support.unit_position")

local geometry = {}

function geometry.resolve_min_player_y(scene)
  return unit_position.read_scene_ground_y(scene) + board_geometry.player_min_ground_offset
end

local function _occupant_count(list)
  return list and #list or 1
end

function geometry.resolve_occupant_slot(list, pid)
  local count = _occupant_count(list)
  local slot = 1
  if list and count > 1 then
    for s = 1, count do
      if list[s] == pid then
        slot = s
        break
      end
    end
  end
  return slot, count
end

function geometry.calc_slot_offset(slot, count, spacing)
  if count <= 1 or spacing <= 0 then
    return 0.0, 0.0
  end
  local per_row = 0
  while per_row * per_row < count do
    per_row = per_row + 1
  end
  local row = math.floor((slot - 1) / per_row)
  local col = (slot - 1) % per_row
  local start = -(per_row - 1) * spacing * 0.5
  local ox = start + col * spacing
  local oz = start + row * spacing
  return ox, oz
end

function geometry.calc_y_offset(base_y, min_player_y)
  if base_y < min_player_y then
    return min_player_y - base_y
  end
  return 0
end

function geometry.resolve_target_position(base, y_offset, ox, oz)
  return base + math.Vector3(ox, y_offset, oz)
end

return geometry

