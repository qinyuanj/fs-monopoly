local prefab = require("Data.Prefab")
local host_runtime_resolver = require("src.ui.render.support.host_runtime_resolver")

local building_effects = {}

local _resolve_host_runtime = host_runtime_resolver.from_state

local function _assert_building_args(scene, building_index)
  assert(scene ~= nil, "missing scene")
  assert(building_index ~= nil, "missing building_index")
end

local function _reset_building_text(scene, building_index)
  local txt = scene.building_txt and scene.building_txt[building_index] or nil
  if txt and txt.set_billboard_text then
    txt.set_billboard_text("  ")
  end
end

function building_effects.clear_building_units(scene, building_index, deps)
  _assert_building_args(scene, building_index)
  local host_runtime = _resolve_host_runtime(scene, deps)
  local groups = scene.building_unit_groups
  if type(groups) == "table" and groups[building_index] then
    host_runtime.destroy_unit_with_children(groups[building_index], true)
    groups[building_index] = nil
  end
  _reset_building_text(scene, building_index)
  return true
end

local _offset_coords = {
  [1] = { x = 0.0, y = 1.5, z = 0.0 },
  [2] = { x = 0.0, y = 1.5, z = 0.0 },
  [3] = { x = 1.0, y = 1.5, z = 0.0 },
}

local _ref_keys = {
  [1] = "一级建筑",
  [2] = "二级建筑",
  [3] = "三级建筑",
}

local function _offset_for_level(level)
  local coords = _offset_coords[level]
  if coords == nil then
    return nil
  end
  return math.Vector3(coords.x, coords.y, coords.z)
end

local function _validate_spawn_args(scene, building_index, level)
  assert(scene ~= nil, "missing scene")
  assert(building_index ~= nil, "missing building_index")
  assert(level ~= nil, "missing building level")
end

local function _resolve_spawn_context(scene, building_index, level, deps)
  local host_runtime = _resolve_host_runtime(scene, deps)
  local buildings = assert(scene.buildings, "missing scene.buildings")
  local groups = assert(scene.building_unit_groups, "missing scene.building_unit_groups")
  building_effects.clear_building_units(scene, building_index, deps)
  if buildings[building_index] == nil then
    return nil
  end
  local pos = buildings[building_index].get_position()
  local ref_key = _ref_keys[level]
  local group_id = prefab.group[ref_key]
  if group_id == nil then
    return nil
  end
  local offset = _offset_for_level(level)
  if offset == nil then
    return nil
  end
  return { host_runtime = host_runtime, groups = groups, idx = building_index,
           pos = pos, ref_key = ref_key, group_id = group_id, offset = offset }
end

local function _apply_building_text(scene, idx, ref_key)
  local txt = scene.building_txt and scene.building_txt[idx] or nil
  if txt and txt.set_billboard_text then
    txt.set_billboard_text(ref_key)
  end
end

function building_effects.spawn_upgrade_building_units(scene, root_quaternion, building_index, level, deps)
  _validate_spawn_args(scene, building_index, level)
  local ctx = _resolve_spawn_context(scene, building_index, level, deps)
  if ctx == nil then
    return false
  end
  local unit = ctx.host_runtime.create_unit_group(ctx.group_id, ctx.pos + ctx.offset, root_quaternion)
  if unit == nil then
    return false
  end
  ctx.groups[ctx.idx] = unit
  _apply_building_text(scene, ctx.idx, ctx.ref_key)
  return true
end

return building_effects

