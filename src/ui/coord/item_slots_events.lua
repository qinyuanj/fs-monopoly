local runtime = require("src.ui.render.support.runtime_ui")
local ui_events = require("src.ui.coord.ui_events")

local M = {}

local _empty_event_payload = {}

local function _emit_ui_event(event_name)
  local role = runtime.get_client_role()
  if role then
    ui_events.send_to_role(role, event_name, _empty_event_payload)
    return
  end
  ui_events.send_to_all(event_name, _empty_event_payload)
end

local function _emit_slot_animation(index, event_prefix)
  _emit_ui_event(event_prefix .. tostring(index))
end

function M.emit_global_reset_animation()
  _emit_ui_event("重置高亮")
end

function M.emit_pickable_slot_animation(slot_pickable)
  M.emit_global_reset_animation()
  for index, can_pick in ipairs(slot_pickable) do
    if not can_pick then
      _emit_slot_animation(index, "重置高亮道具槽位牌")
    end
  end
  for index, can_pick in ipairs(slot_pickable) do
    if can_pick then
      _emit_slot_animation(index, "高亮道具槽位牌")
    end
  end
end

return M

