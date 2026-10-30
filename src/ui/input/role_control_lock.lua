local role_id_utils = require("src.foundation.identity")
local runtime_state = require("src.ui.state.runtime")
local tables = require("src.foundation.tables")

local lock_policy = {}

-- 角色名册也含观战者；只有局内匹配玩家明确淘汰时，才放弃其单位句柄。
local function _is_eliminated(state, role_id)
  local players = state.game and state.game.players or {}
  for _, player in ipairs(players) do
    if role_id_utils.equals(player.id, role_id) and player.eliminated == true then
      return true
    end
  end
  return false
end

local function _discard_eliminated_locks(state, lock_state)
  for role_id in pairs(lock_state.by_role) do
    if _is_eliminated(state, role_id) then
      -- 破产已销毁单位，不能经释放锁路径回读或移除 Buff。
      lock_state.by_role[role_id] = nil
    end
  end
end

local function _resolve_lock_state(state)
  local lock_state = state.role_control_lock
  if lock_state then
    return lock_state
  end
  lock_state = {
    by_role = {},
  }
  state.role_control_lock = lock_state
  return lock_state
end

local function _can_apply(unit)
  return unit
    and unit.get_state_count
    and unit.add_state
    and unit.remove_state
end

local function _remove_lock(unit, buff_id)
  if not unit then
    return
  end
  local count = unit.get_state_count(buff_id)
  if count and count > 0 then
    unit.remove_state(buff_id)
  end
end

-- unit 上还没有 buff 时才由我们加，并记 owned；已经有 buff 说明是别处加的，
-- 沿用原 owned 判定（归一成布尔）。
local function _acquire_lock(entry, unit, buff_id)
  local count = unit.get_state_count(buff_id)
  if count == 0 then
    unit.add_state(buff_id)
    entry.owned = true
  else
    entry.owned = entry.owned == true
  end
  entry.unit = unit
end

-- 已拥有旧单位锁时:新单位不同则先移除旧锁,同单位保持。
local function _should_remove_lock(entry, unit)
  return entry.unit and entry.unit ~= unit and entry.owned
end

local function _lock_entry(lock_state, normalized_role_id)
  return role_id_utils.read(lock_state.by_role, normalized_role_id) or {}
end

local function _sync_role_lock(lock_state, role_id, unit, buff_id)
  local normalized_role_id = role_id_utils.normalize(role_id)
  if normalized_role_id == nil then
    return
  end
  local entry = _lock_entry(lock_state, normalized_role_id)
  if _should_remove_lock(entry, unit) then
    _remove_lock(entry.unit, buff_id)
  end

  if not unit then
    role_id_utils.write(lock_state.by_role, normalized_role_id, nil)
    return
  end

  _acquire_lock(entry, unit, buff_id)
  role_id_utils.write(lock_state.by_role, normalized_role_id, entry)
end

local function _release_all(lock_state, buff_id)
  for role_id, entry in pairs(lock_state.by_role) do
    if entry and entry.owned and entry.unit then
      _remove_lock(entry.unit, buff_id)
    end
    lock_state.by_role[role_id] = nil
  end
end

local _sync_state, _sync_lock_state, _sync_exempt_by_role, _sync_buff_id, _sync_runtime, _sync_seen_roles
local _seen_roles = {}

local function _begin_sync_context(state, lock_state, exempt_by_role, buff_id, runtime)
  _sync_state = state
  _sync_lock_state = lock_state
  _sync_exempt_by_role = exempt_by_role
  _sync_buff_id = buff_id
  _sync_runtime = runtime
  _sync_seen_roles = _seen_roles
end

local function _end_sync_context()
  _sync_state = nil
  _sync_lock_state = nil
  _sync_exempt_by_role = nil
  _sync_buff_id = nil
  _sync_runtime = nil
end

local function _remove_owned_lock(entry, buff_id)
  if entry and entry.owned and entry.unit then
    _remove_lock(entry.unit, buff_id)
  end
end

local function _prune_unseen_roles(lock_state, buff_id)
  for role_id, entry in pairs(lock_state.by_role) do
    if not _seen_roles[role_id] then
      _remove_owned_lock(entry, buff_id)
      lock_state.by_role[role_id] = nil
    end
  end
end

local function _resolve_ctrl_unit(role)
  return role.get_ctrl_unit and role.get_ctrl_unit() or nil
end

local function _apply_seen_role_lock(role, role_id)
  local unit = _resolve_ctrl_unit(role)
  local exempt = role_id_utils.read(_sync_exempt_by_role, role_id) == true
  if exempt or not unit then
    _sync_role_lock(_sync_lock_state, role_id, nil, _sync_buff_id)
    return
  end
  if not _can_apply(unit) then
    runtime_state.log_once(_sync_state, "warn", "role_control_lock:missing_buff_api_" .. tostring(role_id), "ctrl_unit missing BuffStateComp:", tostring(role_id))
    return
  end
  _sync_role_lock(_sync_lock_state, role_id, unit, _sync_buff_id)
end

local function _sync_role_callback(role)
  if not role then
    runtime_state.log_once(_sync_state, "warn", "role_control_lock:missing_roles", "role_control_lock missing role list")
    return
  end
  local role_id = role_id_utils.normalize(_sync_runtime.resolve_role_id(role) or tostring(role))
  if role_id == nil or _is_eliminated(_sync_state, role_id) then
    return
  end
  _sync_seen_roles[role_id] = true
  _apply_seen_role_lock(role, role_id)
end

local function _assert_sync_args(state, deps)
  assert(state ~= nil, "missing state")
  assert(deps ~= nil and deps.runtime ~= nil, "missing deps.runtime")
end

local function _resolve_buff_id()
  return Enums and Enums.BuffState and Enums.BuffState.BUFF_FORBID_CONTROL or nil
end

-- 遍历当前所有角色重建锁，然后回收这一轮没见到的角色。
local function _sync_locked_roles(state, lock_state, exempt_by_role, buff_id, runtime)
  tables.clear(_seen_roles)
  _begin_sync_context(state, lock_state, exempt_by_role, buff_id, runtime)

  runtime.for_each_role_or_global(_sync_role_callback)

  _end_sync_context()
  _prune_unseen_roles(lock_state, buff_id)
end

function lock_policy.sync(state, enabled, deps)
  _assert_sync_args(state, deps)
  local runtime = deps.runtime
  local lock_state = _resolve_lock_state(state)
  _discard_eliminated_locks(state, lock_state)
  local exempt_by_role = state.role_control_lock_exempt_by_role or {}
  local buff_id = _resolve_buff_id()
  if not buff_id then
    runtime_state.log_once(state, "warn", "role_control_lock:missing_buff_enum", "missing Enums.BuffState.BUFF_FORBID_CONTROL")
    return
  end

  if enabled ~= true then
    _release_all(lock_state, buff_id)
    return
  end

  _sync_locked_roles(state, lock_state, exempt_by_role, buff_id, runtime)
end

return lock_policy

