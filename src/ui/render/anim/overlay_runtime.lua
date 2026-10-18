local runtime_constants = require("src.config.gameplay.runtime_constants")
local host_runtime_resolver = require("src.ui.render.support.host_runtime_resolver")

local runtime = {}

local _resolve_host_runtime = host_runtime_resolver.from_state

local function _ensure_overlays(scene)
  if not scene.overlay_units then
    scene.overlay_units = { roadblocks = {}, mines = {} }
  end
  return scene.overlay_units
end

local function _get_overlay_bucket(overlays, kind)
  if kind == "roadblock" then
    return overlays.roadblocks
  end
  if kind == "mine" then
    return overlays.mines
  end
  return nil
end

-- 调用方(_spawn_entry)只在 group_id/unit_id 非 nil 时才进这两条路径,
-- id 的 nil assert 是不可达死防御(#262 删除);pos 仍可经 spawn_transient 缺省。
local function _spawn_unit_group(host_runtime, group_id, pos)
  assert(pos ~= nil, "missing pos")
  return host_runtime.create_unit_group(group_id, pos, runtime_constants.q_zero)
end

local function _resolve_unit_scale(scale)
  return scale or runtime_constants.v3_one
end

-- Second return says whether the handle came from the host pool, so the
-- matching teardown can release instead of destroy it.
local function _acquire_pooled_unit(host_runtime, unit_id, pos, scale)
  local handle = host_runtime.acquire_unit(unit_id, pos, runtime_constants.q_zero, scale)
  return handle, handle ~= nil
end

local function _spawn_unit(host_runtime, unit_id, pos, scale)
  assert(pos ~= nil, "missing pos")
  local unit_scale = _resolve_unit_scale(scale)
  if type(host_runtime.acquire_unit) == "function" then
    return _acquire_pooled_unit(host_runtime, unit_id, pos, unit_scale)
  end
  return host_runtime.create_unit_with_scale(unit_id, pos, runtime_constants.q_zero, unit_scale), false
end

-- entry 恒为 _spawn_entry 产物(handle 恒在),空守卫是死防御(#262 删除:
-- or->and 变异体在 nil 输入索引报错,而 nil 输入本就不可达)。
local function _destroy_unit(host_runtime, entry)
  if entry.kind == "group" then
    host_runtime.destroy_unit_with_children(entry.handle, true)
    return
  end
  if entry.pooled and type(host_runtime.release_unit) == "function" then
    host_runtime.release_unit(entry.unit_id, entry.handle)
    return
  end
  host_runtime.destroy_unit(entry.handle)
end

-- Overlays and transient VFX are decorative: drop physics/interact so a spawned
-- handle never collides with pawns or steals taps.
local function _make_decorative(handle)
  if type(handle.set_physics_active) == "function" then
    handle.set_physics_active(false)
  end
  if type(handle.disable_interact) == "function" then
    handle.disable_interact()
  end
end

local function _spawn_entry(host_runtime, group_id, unit_id, pos, scale)
  if group_id then
    local handle = _spawn_unit_group(host_runtime, group_id, pos)
    if not handle then
      return nil
    end
    _make_decorative(handle)
    return { kind = "group", handle = handle }
  end
  if unit_id then
    local handle, pooled = _spawn_unit(host_runtime, unit_id, pos, scale)
    if not handle then
      return nil
    end
    _make_decorative(handle)
    return { kind = "unit", handle = handle, unit_id = unit_id, pooled = pooled }
  end
  return nil
end

local function _schedule_transient_destroy(host_runtime, entry, duration)
  if duration and duration > 0 then
    host_runtime.schedule(duration, function()
      _destroy_unit(host_runtime, entry)
    end)
    return
  end
  _destroy_unit(host_runtime, entry)
end

local function _clear_bucket_entry(host_runtime, bucket, tile_index)
  local entry = bucket[tile_index]
  if not entry then
    return
  end
  _destroy_unit(host_runtime, entry)
  bucket[tile_index] = nil
end

local function _assert_overlay_slot(scene, kind, tile_index)
  assert(scene ~= nil, "missing board_scene")
  assert(kind ~= nil, "missing kind")
  assert(tile_index ~= nil, "missing tile_index")
end

function runtime.clear_overlay(scene, kind, tile_index, deps)
  _assert_overlay_slot(scene, kind, tile_index)
  local host_runtime = _resolve_host_runtime(scene, deps)
  local overlays = _ensure_overlays(scene)
  local bucket = _get_overlay_bucket(overlays, kind)
  if not bucket then
    return
  end
  _clear_bucket_entry(host_runtime, bucket, tile_index)
end

function runtime.spawn_overlay(scene, kind, tile_index, group_id, unit_id, pos, scale, deps)
  _assert_overlay_slot(scene, kind, tile_index)
  assert(pos ~= nil, "missing pos")

  local host_runtime = _resolve_host_runtime(scene, deps)
  local overlays = _ensure_overlays(scene)
  local bucket = _get_overlay_bucket(overlays, kind)
  if not bucket then
    return false
  end
  _clear_bucket_entry(host_runtime, bucket, tile_index)

  local entry = _spawn_entry(host_runtime, group_id, unit_id, pos, scale)
  if entry == nil then
    return false
  end
  bucket[tile_index] = entry
  return true
end

local function _transient_host_runtime(deps)
  return _resolve_host_runtime(deps and deps.scene or nil, deps)
end

function runtime.spawn_transient(group_id, unit_id, pos, duration, deps)
  if not group_id and not unit_id then
    return
  end
  local host_runtime = _transient_host_runtime(deps)
  local entry = _spawn_entry(host_runtime, group_id, unit_id, pos)
  if not entry then
    return
  end
  _schedule_transient_destroy(host_runtime, entry, duration)
end

return runtime

