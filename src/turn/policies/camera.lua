local number_utils = require("src.foundation.number")
local runtime_state = require("src.state.runtime")

local turn_camera_policy = {}

local function _is_follow_candidate(player)
  return player and player.id ~= nil and player.eliminated ~= true
end

local function _game_turn(game)
  return game and game.turn or nil
end

local function _game_players(game)
  return game and game.players or nil
end

local function _validated_player_list(game)
  local turn = _game_turn(game)
  local players = _game_players(game)
  if not (turn and type(players) == "table") then
    return nil, nil, nil
  end
  local count = #players
  if count <= 0 then
    return nil, nil, nil
  end
  local current_index = number_utils.to_integer(turn.current_player_index)
  return players, count, current_index
end

local function _scan_next_candidate(players, count, start_index)
  for offset = 1, count do
    local idx = ((start_index - 1 + offset) % count) + 1
    local candidate = players[idx]
    if _is_follow_candidate(candidate) then
      return candidate.id
    end
  end
  return nil
end

local function _player_at(players, index)
  return index and players[index] or nil
end

local function _resolve_follow_player_id(game)
  local players, count, current_index = _validated_player_list(game)
  if not players then
    return nil
  end
  local current = _player_at(players, current_index)
  if _is_follow_candidate(current) then
    return current.id
  end
  if current_index == nil then
    return nil
  end
  return _scan_next_candidate(players, count, current_index)
end

local function _get_ui_sync_ports(ports)
  local ui_sync_ports = ports and ports.ui_sync or nil
  if not (ui_sync_ports and type(ui_sync_ports.follow_camera) == "function") then
    return nil
  end
  return ui_sync_ports
end

local function _clear_follow_target(turn_runtime)
  if turn_runtime then
    turn_runtime.last_follow_player_id = nil
  end
end

local function _sync_existing_target(ui_sync_ports, state)
  if type(ui_sync_ports.sync_camera_position) == "function" then
    ui_sync_ports.sync_camera_position(state)
  end
end

local function _can_change_target(turn_runtime, ui_refreshed)
  return ui_refreshed == true or turn_runtime ~= nil
end

local function _record_follow_target(turn_runtime, current_id, ok)
  if ok and turn_runtime then
    turn_runtime.last_follow_player_id = current_id
  end
end

local function _resolve_turn_runtime(state)
  return state and runtime_state.ensure_turn_runtime(state) or nil
end

local function _is_target_changed(turn_runtime, current_id)
  return not (turn_runtime and turn_runtime.last_follow_player_id == current_id)
end

local function _is_target_pan_active(turn_runtime)
  return turn_runtime ~= nil and turn_runtime.target_pan_active == true
end

local function _apply_follow(ui_sync_ports, state, turn_runtime, current_id, ui_refreshed)
  if not _is_target_changed(turn_runtime, current_id) then
    _sync_existing_target(ui_sync_ports, state)
    return
  end
  if not _can_change_target(turn_runtime, ui_refreshed) then
    return
  end

  local ok = ui_sync_ports.follow_camera(state, current_id)
  _record_follow_target(turn_runtime, current_id, ok)
end

function turn_camera_policy.sync_follow(game, state, ports, ui_refreshed)
  local ui_sync_ports = _get_ui_sync_ports(ports)
  if not ui_sync_ports then
    return
  end

  local turn_runtime = _resolve_turn_runtime(state)
  -- 效果平移(pan)存活期内整体跳过:此时 dirty.turn 清掉 last_follow 只是
  -- visual hold 等机制的心跳,不是换目标;重放 follow 会把镜头从效果地块
  -- 拽回玩家(效果结算偶发 jitter)。release_target_pan 清标志后恢复跟随。
  if _is_target_pan_active(turn_runtime) then
    return
  end
  local current_id = _resolve_follow_player_id(game)
  if current_id == nil then
    _clear_follow_target(turn_runtime)
    return
  end

  _apply_follow(ui_sync_ports, state, turn_runtime, current_id, ui_refreshed)
end

function turn_camera_policy.reset_follow(state)
  local turn_runtime = state and runtime_state.ensure_turn_runtime(state) or nil
  if turn_runtime then
    turn_runtime.last_follow_player_id = nil
  end
end

turn_camera_policy._resolve_follow_player_id = _resolve_follow_player_id

return turn_camera_policy

