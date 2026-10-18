local scene_ui = {}

function scene_ui.set_scene_ui_visible(layer, role, visible)
  if not (GameAPI and type(GameAPI.set_scene_ui_visible) == "function") then
    return false
  end
  return pcall(GameAPI.set_scene_ui_visible, layer, role, visible == true)
end

function scene_ui.destroy_scene_ui(layer)
  if not (GameAPI and type(GameAPI.destroy_scene_ui) == "function") then
    return false
  end
  return pcall(GameAPI.destroy_scene_ui, layer)
end

local function _has_set_visible()
  return GameAPI and type(GameAPI.set_scene_ui_visible) == "function"
end

function scene_ui.has_scene_ui_support()
  return _has_set_visible() and true or false
end

local function _has_eui_lookup()
  return GameAPI ~= nil and type(GameAPI.get_eui_node_at_scene_ui) == "function"
end

local function _complete_args(layer, node_id)
  return layer ~= nil and node_id ~= nil
end

function scene_ui.get_eui_node_at_scene_ui(layer, node_id)
  if not _has_eui_lookup() then
    return nil
  end
  if not _complete_args(layer, node_id) then
    return nil
  end
  local ok, result = pcall(GameAPI.get_eui_node_at_scene_ui, layer, node_id)
  if not ok then
    return nil
  end
  return result
end

return scene_ui

