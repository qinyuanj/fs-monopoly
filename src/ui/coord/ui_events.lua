local nodes = require("Data.UIManagerNodes")

local function _collect_canvas_names(node_entries)
  local names = {}
  for _, entry in pairs(node_entries) do
    if type(entry) == "table" and entry[2] == "ECanvas" then
      names[#names + 1] = entry[1]
    end
  end
  table.sort(names)
  return names
end

local function _build_event_maps(canvas_names)
  local show, hide = {}, {}
  for _, name in ipairs(canvas_names) do
    show[name] = "显示" .. name
    hide[name] = "隐藏" .. name
  end
  return show, hide
end

local canvas_names = _collect_canvas_names(nodes)
local show_events, hide_events = _build_event_maps(canvas_names)

local ui_events = {
  canvas_names = canvas_names,
  show = show_events,
  hide = hide_events,
  roles = nil,
}


function ui_events.set_roles(roles)
  ui_events.roles = roles
end

function ui_events.send_to_all(event_name, payload)
  assert(event_name ~= nil, "missing event_name")
  local roles = ui_events.roles
  if not roles then
    return
  end
  local data = payload or {}
  for _, role in ipairs(roles) do
    role.send_ui_custom_event(event_name, data)
  end
end

function ui_events.send_to_role(role, event_name, payload)
  assert(role ~= nil, "missing role")
  assert(event_name ~= nil, "missing event_name")
  if not role.send_ui_custom_event then
    return
  end
  role.send_ui_custom_event(event_name, payload or {})
end

return ui_events

