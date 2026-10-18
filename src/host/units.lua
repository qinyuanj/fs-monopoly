local unit_lifecycle = {}

local function _has_game_api(method_name)
  return GameAPI and type(GameAPI[method_name]) == "function"
end

local function _call_create(method_name, ...)
  if not _has_game_api(method_name) then
    return nil, "missing GameAPI." .. method_name
  end
  return GameAPI[method_name](...)
end

local function _call_destroy(method_name, ...)
  if not _has_game_api(method_name) then
    return false
  end
  GameAPI[method_name](...)
  return true
end

function unit_lifecycle.create_unit_group(group_id, pos, rotation)
  return _call_create("create_unit_group", group_id, pos, rotation)
end

function unit_lifecycle.create_unit_with_scale(unit_id, pos, rotation, scale)
  return _call_create("create_unit_with_scale", unit_id, pos, rotation, scale)
end

function unit_lifecycle.destroy_unit_with_children(handle, include_children)
  return _call_destroy("destroy_unit_with_children", handle, include_children == true)
end

function unit_lifecycle.destroy_unit(handle)
  return _call_destroy("destroy_unit", handle)
end

return unit_lifecycle

