local runtime_state = require("src.state.runtime")
local landing_visual_hold = require("src.state.visual_hold")
local logger = require("src.foundation.log")
local input_lock = require("src.state.input_lock")

local runtime = {}

local function _ui_sync_ports(ports)
  return ports and ports.ui_sync or nil
end

local function _has_sync_methods(ui_sync_ports)
  return ui_sync_ports ~= nil and ui_sync_ports.get_ui_state ~= nil and ui_sync_ports.set_input_blocked ~= nil
end

function runtime.sync_input_blocked(state, phase, ports)
  local ui_sync_ports = _ui_sync_ports(ports)
  if not _has_sync_methods(ui_sync_ports) then
    return false
  end
  local ui = ui_sync_ports.get_ui_state(state)
  if not ui then
    return false
  end
  local input_blocked = input_lock.is_phase_input_blocked(phase)
  if not ui_sync_ports.set_input_blocked(state, input_blocked) then
    return false
  end
  return true
end

local function _move_anim_just_finished(board_runtime, phase)
  return board_runtime.board_last_phase == "wait_move_anim" and phase ~= "wait_move_anim"
end

local function _should_unlock_next_turn(turn_runtime, phase)
  return turn_runtime.next_turn_locked
    and turn_runtime.next_turn_lock_phase
    and phase
    and phase ~= turn_runtime.next_turn_lock_phase
end

function runtime.sync_phase_flags(state, phase)
  local board_runtime = runtime_state.ensure_board_runtime(state)
  local turn_runtime = runtime_state.ensure_turn_runtime(state)
  if _move_anim_just_finished(board_runtime, phase) then
    board_runtime.board_sync_pending = true
  end
  if _should_unlock_next_turn(turn_runtime, phase) then
    turn_runtime.next_turn_locked = false
    turn_runtime.next_turn_lock_phase = phase
  end
  board_runtime.board_last_phase = phase
end

local function _build_memoized_port(state, cache_key, port_builder)
  assert(type(state) == "table", "missing state")
  local cached = state[cache_key]
  if type(cached) == "table" then return cached end
  local port = port_builder()
  state[cache_key] = port
  return port
end

function runtime.build_board_scene_port(state)
  return _build_memoized_port(state, "_board_scene_port", function()
    return { get_board_scene = function() return state.board_scene end }
  end)
end

function runtime.build_popup_port(state)
  return _build_memoized_port(state, "_popup_port", function()
    return {
      push_popup = function(_, payload, opts)
        return landing_visual_hold.run_or_defer(state, state.game, "popup", function()
          if type(state.push_popup) == "function" then return state:push_popup(payload, opts) end
          return false
        end)
      end,
    }
  end)
end

function runtime.build_tip_output_port(state)
  return _build_memoized_port(state, "_tip_output_port", function()
    return {
      enqueue = function(_, intent)
        if type(state.show_tip) == "function" then return state:show_tip(intent) == true end
        logger.warn("[tip_output_port]", "state.show_tip not installed, falling back to tip_queue direct")
        return require("src.foundation.tips").enqueue(intent)
      end,
    }
  end)
end

function runtime.build_tile_feedback_port(state)
  return _build_memoized_port(state, "_tile_feedback_port", function()
    return {
      on_tile_upgraded = function(_, tile_id)
        local game = state.game
        if game == nil or game.board_visual_feedback_port == nil then return false end
        return game.board_visual_feedback_port.sync_many(game, { tile_ids = { tile_id } })
      end,
    }
  end)
end

local function _sync_many_args(arg1, arg2, arg3, port)
  if arg3 ~= nil or (type(arg1) == "table" and arg1 == port) then
    return arg2, arg3
  end
  return arg1, arg2
end

local function _board_visual_sync_deferred(state, payload)
  return function()
    if type(state.on_board_visual_sync) == "function" then
      return state:on_board_visual_sync(payload) == true
    end
    return false
  end
end

function runtime.build_board_visual_feedback_port(state)
  return _build_memoized_port(state, "_board_visual_feedback_port", function()
    local port = {}
    port.sync_many = function(arg1, arg2, arg3)
      local game, payload = _sync_many_args(arg1, arg2, arg3, port)
      local current_game = game or state.game
      if current_game ~= nil then state.game = current_game end
      return landing_visual_hold.run_or_defer(
        state, current_game, "board_visual_sync", _board_visual_sync_deferred(state, payload))
    end
    return port
  end)
end

function runtime.build_anim_gate_port(state)
  return _build_memoized_port(state, "_anim_gate_port", function()
    return { wait_move_anim = state.wait_move_anim == true, wait_action_anim = state.wait_action_anim == true }
  end)
end

return runtime

