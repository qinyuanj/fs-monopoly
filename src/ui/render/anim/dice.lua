local number_utils = require("src.foundation.number")
local effect_timeline = require("src.ui.render.support.effect_timeline")

local dice = {}

local function _resolve_face_value(value)
  local face = number_utils.to_integer(value)
  if face and face >= 1 and face <= 6 then
    return face
  end
  return nil
end

local function _resolve_roll_face(anim)
  if not anim then
    return nil
  end
  local rolls = anim.rolls
  local first = type(rolls) == "table" and rolls[1] or nil
  local first_face = _resolve_face_value(first)
  if first_face then
    return first_face
  end
  return _resolve_face_value(anim.total)
end

local function _set_face_nodes_visibility(face_nodes, face)
  for index, node in ipairs(face_nodes or {}) do
    node.visible = face == index
  end
end

local function _set_roll_screen_visible(nodes, visible)
  nodes.screen.visible = visible
  nodes.spin.visible = visible
  _set_face_nodes_visibility(nodes.faces, nil)
end

local function _show_roll_result(nodes, face)
  nodes.spin.visible = false
  if face then
    _set_face_nodes_visibility(nodes.faces, face)
  end
end

local function _cleanup_roll_screen(nodes, ui_events, dice_nodes)
  local hide_event = ui_events.hide[dice_nodes.canvas]
  if hide_event then
    ui_events.send_to_all(hide_event, {})
  end
  _set_roll_screen_visible(nodes, false)
end

local function _resolve_roll_screen_opts(opts)
  return assert(opts and opts.runtime, "missing runtime"),
    assert(opts and opts.dice_screen_nodes, "missing dice_screen_nodes"),
    assert(opts and opts.ui_events, "missing opts.ui_events")
end

local function _resolve_roll_timing(duration, hold_seconds)
  return duration or 0, hold_seconds or 0
end

local function _resolve_roll_display_face(anim)
  return _resolve_roll_face(anim) or 1
end

local function _query_roll_nodes(runtime, dice_nodes)
  local nodes = {
    screen = runtime.query_node(dice_nodes.canvas),
    spin = runtime.query_node(dice_nodes.spin),
    faces = {},
  }
  for index, name in ipairs(dice_nodes.faces) do
    nodes.faces[index] = runtime.query_node(name)
  end
  return nodes
end

local function _play_roll_dice_for_role(runtime, dice_nodes, ui_events, duration, hold_seconds, face, opts)
  local nodes = _query_roll_nodes(runtime, dice_nodes)
  effect_timeline.play({
    schedule = opts.schedule,
    show = function()
      _set_roll_screen_visible(nodes, true)
    end,
    steps = {
      {
        delay = duration,
        run = function()
          ui_events.send_to_all("重置骰子旋转", {})
          _show_roll_result(nodes, face)
        end,
      },
    },
    cleanup_delay = duration + hold_seconds,
    cleanup = function()
      _cleanup_roll_screen(nodes, ui_events, dice_nodes)
    end,
  })
end

function dice.play_roll_dice_screen(anim, duration, hold_seconds, opts)
  local runtime, dice_nodes, ui_events = _resolve_roll_screen_opts(opts)
  duration, hold_seconds = _resolve_roll_timing(duration, hold_seconds)
  local face = _resolve_roll_display_face(anim)
  local show_event = ui_events.show[dice_nodes.canvas]
  if show_event then
    ui_events.send_to_all(show_event, {})
  end
  ui_events.send_to_all("重置骰子旋转", {})
  ui_events.send_to_all("旋转骰子", {})
  runtime.for_each_role_or_global(function()
    _play_roll_dice_for_role(runtime, dice_nodes, ui_events, duration, hold_seconds, face, opts)
  end)
end

return dice

