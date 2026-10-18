-- 相机目标解析:follow 目标位置与「本机 role」身份链。
-- 原 ui_sync/camera.lua 的解析链;camera.lua 保留编排与公共面。
local runtime_ports = require("src.foundation.ports.runtime_ports")
local runtime_state = require("src.ui.state.runtime")
local unit_position = require("src.ui.render.support.unit_position")
local runtime_ui = require("src.ui.render.support.runtime_ui")

local M = {}

local function _safe_call_method(state, obj, key, log_key, log_prefix)
  if type(obj[key]) ~= "function" then return nil end
  local ok, result = pcall(obj[key])
  if not ok then
    runtime_state.log_once(state, "warn", log_key, "camera_sync", log_prefix, tostring(result))
    return nil
  end
  return result
end

local function _resolve_unit_position(state, role)
  if role == nil then return nil end
  local unit = _safe_call_method(state, role, "get_ctrl_unit", "camera_sync:get_ctrl_unit_failed", "resolve unit failed:")
  if unit == nil then return nil end
  return _safe_call_method(state, unit, "get_position", "camera_sync:get_position_failed", "resolve unit position failed:")
end

local function _resolve_followed_unit_live_position(state, player_id)
  local board_scene = state and state.board_scene or nil
  if board_scene == nil then
    return nil
  end
  local units_by_player_id = board_scene.units_by_player_id
  if type(units_by_player_id) ~= "table" then
    return nil
  end
  return unit_position.read_unit_position(units_by_player_id[player_id])
end

function M.resolve_follow_target_position(state, player_id)
  local live_pos = _resolve_followed_unit_live_position(state, player_id)
  if live_pos ~= nil then
    return live_pos
  end
  local followed_pos = runtime_state.get_follow_target_position(state, player_id)
  if followed_pos ~= nil then
    return followed_pos
  end
  local target_role = runtime_ports.resolve_role(player_id)
  if target_role == nil then
    return nil
  end
  return _resolve_unit_position(state, target_role)
end

local function _current_player_index(turn)
  return turn and turn.current_player_index or nil
end

local function _player_at_index(players, current_index)
  return current_index and players and players[current_index] or nil
end

local function _current_player(game)
  local players = game and game.players or nil
  return _player_at_index(players, _current_player_index(game and game.turn or nil))
end

local function _resolve_current_player_id(state)
  local game = state and state.game or nil
  local current_player = _current_player(game)
  return current_player and current_player.id or nil
end

-- 单 role 兜底链路的「本机角色」(#601):client_role 优先(多席位局跟本机
-- 角色),client_role 缺位才兜底当前行动玩家。「上一次点击者缓存」已整体退役,
-- 不再参与相机身份解析。
local function _resolve_camera_local_role_id(state)
  return runtime_ui.resolve_role_id(runtime_ui.get_client_role())
    or _resolve_current_player_id(state)
end

function M.resolve_local_role(state)
  local role_id = _resolve_camera_local_role_id(state)
  if role_id == nil then return nil, nil end
  return runtime_ports.resolve_role(role_id), role_id
end

-- 目标位置惰性解析并记忆:全场都在看自己时一次宿主查询都不做,多 role 时也只查一次。
function M.make_target_pos_reader(state, player_id)
  local resolved = false
  local pos = nil
  return function()
    if not resolved then
      resolved = true
      pos = M.resolve_follow_target_position(state, player_id)
    end
    return pos
  end
end

return M

