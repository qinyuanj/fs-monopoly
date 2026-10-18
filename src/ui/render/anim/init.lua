local timing = require("src.config.gameplay.timing")
local registry = require("src.ui.render.anim.registry")
local handlers = require("src.ui.render.anim.handlers")
local default_handlers = require("src.ui.render.anim.defaults")
local host_runtime_ports = require("src.ui.seams.host_runtime")
local runtime_ui = require("src.ui.render.support.runtime_ui")
local effect_track = require("src.ui.render.support.effect_track")
local tip_chain = require("src.ui.render.anim.tip_chain")

local action_anim = {}

local function _timing_or(value, fallback)
  if value ~= nil then
    return value
  end
  return fallback
end

local durations = {
  missile = 1.2,
  monster = 1.2,
}
local start_delays = {
  missile = _timing_or(timing.demolish_effect_start_delay_seconds, 0.2),
  monster = _timing_or(timing.demolish_effect_start_delay_seconds, 0.2),
}

local function _resolve_runtime_bundle(state, opts)
  if opts and opts.runtime_bundle then
    return opts.runtime_bundle
  end
  if state and state.presentation_runtime then
    return state.presentation_runtime
  end
  return {
    runtime = runtime_ui,
    host_runtime = host_runtime_ports,
    ui_events = {
      show = {},
      hide = {},
      send_to_all = function() end,
    },
  }
end

action_anim.clear_overlay = handlers.clear_overlay

local function _base_duration(anim, default_duration)
  return anim.duration or durations[anim.kind] or default_duration
end

local function _start_delay_of(anim)
  return start_delays[anim.kind] or 0
end

local function _resolve_duration(anim)
  local default_duration = timing.action_anim_default_seconds or 1.0
  local base_duration = _base_duration(anim, default_duration)
  if base_duration <= 0 then
    base_duration = default_duration
  end
  local duration = effect_track.scaled_duration(base_duration)
  local start_delay = _start_delay_of(anim)
  if start_delay > 0 then
    duration = duration + start_delay
  end
  return duration
end

local function _camera_sync_of(runtime_bundle)
  return runtime_bundle and runtime_bundle.camera_sync or nil
end

local function _camera_method(camera_sync, name)
  return camera_sync and camera_sync[name] or nil
end

local function _build_handler_opts(runtime_bundle, host_runtime)
  local camera_sync = _camera_sync_of(runtime_bundle)
  return {
    runtime = runtime_bundle.runtime,
    ui_events = runtime_bundle.ui_events,
    schedule = host_runtime and host_runtime.schedule or nil,
    runtime_bundle = runtime_bundle,
    hold_seconds = default_handlers.roll_face_hold_seconds(),
    clear_overlay = action_anim.clear_overlay,
    pan_camera_to_position = _camera_method(camera_sync, "pan_camera_to_position"),
    release_target_pan = _camera_method(camera_sync, "release_target_pan"),
  }
end

-- handler 派发:start_delay > 0 且可排期时延迟执行,否则同步直跑。
local function _dispatch_handler(state, anim, duration, handler, runtime_bundle, host_runtime)
  local start_delay = start_delays[anim.kind] or 0
  if start_delay > 0 and host_runtime and type(host_runtime.schedule) == "function" then
    host_runtime.schedule(start_delay, function()
      handler(state, anim, duration, _build_handler_opts(runtime_bundle, host_runtime))
    end)
    return duration
  end
  return handler(state, anim, duration, _build_handler_opts(runtime_bundle, host_runtime))
end

function action_anim.play(state, anim, opts)
  assert(anim ~= nil, "missing anim")
  assert(state ~= nil, "missing state")
  default_handlers.register()
  local runtime_bundle = _resolve_runtime_bundle(state, opts)
  local host_runtime = runtime_bundle.host_runtime
  local duration = _resolve_duration(anim)
  local handler = registry.resolve(anim.kind)
  tip_chain.emit(state, anim, host_runtime, duration)
  if handler then
    return _dispatch_handler(state, anim, duration, handler, runtime_bundle, host_runtime)
  end
  return duration
end

return action_anim

