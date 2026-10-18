local runtime_ports = require("src.foundation.ports.runtime_ports")
local runtime_state = require("src.ui.state.runtime")
local runtime_ui = require("src.ui.render.support.runtime_ui")
local camera_target = require("src.ui.ports.ui_sync.camera_target")
local camera_lock = require("src.ui.ports.ui_sync.camera_lock")
local relock_filter = require("src.ui.ports.ui_sync.camera_relock_filter")

local camera_sync = {}

-- camera helper 是可选的宿主对象：拿不到就整段跳过，拿到了才谈 follow。
local function _point_camera_helper_at(player_id)
  local camera = runtime_ports.resolve_camera_helper()
  if camera == nil then
    return
  end
  camera.target_role_id = player_id
  if type(camera.follow) == "function" then
    camera.follow(player_id)
  end
end

-- 相机是 role 级的（Role.set_camera_lock_position 只作用于那一个客户端）：跟随要
-- 对每个在场 role 各算一次——目标是它自己就 reset 回自己,不是就锁到目标位置。
-- 不能只处理「本机 role」:单 role 兜底链路在 client_role 缺位时会退成「当前
-- 行动玩家」,而 follow 的目标恰恰就是当前行动玩家,两者恒等 → 每回合都走
-- reset_to_self,镜头永远焊在自己身上(真机 2026-07-25 复现)。
local function _apply_follow_for_role(state, role, role_id, player_id, read_target_pos)
  if role == nil then
    return false
  end
  if role_id ~= nil and role_id == player_id then
    return camera_lock.reset_to_self(state, role)
  end
  -- 旁观 role 直接改锁新目标,不先 reset 回自己:稳态路径(sync_camera_position)
  -- 每 tick 无 reset 重锁已证明宿主支持直接换绑,reset 会让镜头先跳回自己再跳
  -- 到新目标,表现为每次换人的瞬间跳变。
  -- 改锁走滤波(sync_lock):dirty.turn 心跳会在阶段切换时重放 follow,
  -- 此时目标没变但落格 snap 已瞬移 2~5 格,直锁=镜头瞬跳(#451 第三轮取证:
  -- glide 0 次、snap 跳变原样出现在发送序列)。滤波后 snap 滑行逼近,
  -- 真换人(数十格)由 teleport 档保住立即切。
  local target_pos = read_target_pos()
  if target_pos == nil then
    camera_lock.reset_to_self(state, role)
    return false
  end
  return camera_lock.sync_lock(state, role, target_pos)
end

-- 宿主 role 列表拿不到时（无 UI 的 headless 链路）退回单 role 语义。
local function _resolve_host_roles()
  local roles = runtime_ports.resolve_roles()
  if type(roles) ~= "table" or #roles == 0 then
    return nil
  end
  return roles
end

local function _for_each_host_role(roles, fn)
  local any_ok = false
  for _, role in ipairs(roles) do
    if fn(role, runtime_ui.resolve_role_id(role)) then
      any_ok = true
    end
  end
  return any_ok
end

function camera_sync.follow_camera(state, player_id)
  if player_id == nil then
    return false
  end
  _point_camera_helper_at(player_id)

  local read_target_pos = camera_target.make_target_pos_reader(state, player_id)
  local roles = _resolve_host_roles()
  if roles ~= nil then
    return _for_each_host_role(roles, function(role, role_id)
      return _apply_follow_for_role(state, role, role_id, player_id, read_target_pos)
    end)
  end

  local local_role, local_role_id = camera_target.resolve_local_role(state)
  return _apply_follow_for_role(state, local_role, local_role_id, player_id, read_target_pos)
end

local function _target_role_id(camera)
  return camera and camera.target_role_id or nil
end

-- 目标角色本人不跟随(相机已在其身上)。
local function _skip_following_target(role_id, target_id)
  return role_id ~= nil and role_id == target_id
end

function camera_sync.sync_camera_position(state)
  local camera = runtime_ports.resolve_camera_helper()
  local target_id = _target_role_id(camera)
  if target_id == nil then
    return false
  end
  local read_target_pos = camera_target.make_target_pos_reader(state, target_id)
  local roles = _resolve_host_roles()
  if roles ~= nil then
    return _for_each_host_role(roles, function(role, role_id)
      if _skip_following_target(role_id, target_id) then
        return false
      end
      return camera_lock.sync_lock(state, role, read_target_pos())
    end)
  end

  local local_role, local_role_id = camera_target.resolve_local_role(state)
  if local_role == nil or target_id == local_role_id then
    return false
  end
  return camera_lock.sync_lock(state, local_role, read_target_pos())
end

function camera_sync.pan_camera_to_position(state, target_pos)
  if target_pos == nil then
    return false
  end
  local local_role = camera_target.resolve_local_role(state)
  if local_role == nil then
    return false
  end
  local camera = runtime_ports.resolve_camera_helper()
  if camera then
    camera.target_role_id = nil
  end
  camera_lock.reset_to_self(state, local_role)
  local ok = camera_lock.lock_to_position(state, local_role, target_pos)
  if ok then
    -- pan 存活期置位：效果结算期间 dirty.turn 脉冲(visual hold 等)会清
    -- last_follow_player_id,若不放行标志,sync_follow 会重放 follow 把镜头
    -- 从效果地块拽回玩家,表现为效果结算时的偶发 jitter。release 时清位。
    runtime_state.ensure_turn_runtime(state).target_pan_active = true
  end
  return ok
end

function camera_sync.release_target_pan(state)
  if state == nil then
    return false
  end
  local turn_runtime = runtime_state.ensure_turn_runtime(state)
  turn_runtime.last_follow_player_id = nil
  turn_runtime.target_pan_active = nil
  return true
end

-- 新局开局钩子:全清滤波基线,防止跨局同 role_id 首帧被误去重(#454)。
function camera_sync.reset_baseline()
  relock_filter.reset()
end

return camera_sync

--[[ mutate4lua-manifest
version=4
projectHash=f3cd8a77aa217f1c
scope.0.id=chunk:src/ui/ports/ui_sync/camera.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=163
scope.0.semanticHash=32b0dababc4c10e8
scope.1.id=function:_point_camera_helper_at
scope.1.kind=function
scope.1.startLine=11
scope.1.endLine=20
scope.1.semanticHash=c837bb3f2d778c3b
scope.2.id=function:_apply_follow_for_role
scope.2.kind=function
scope.2.startLine=27
scope.2.endLine=47
scope.2.semanticHash=c31d91115b4b4ff6
scope.3.id=function:_resolve_host_roles
scope.3.kind=function
scope.3.startLine=50
scope.3.endLine=56
scope.3.semanticHash=549eafd686810046
scope.4.id=function:_for_each_host_role
scope.4.kind=function
scope.4.startLine=58
scope.4.endLine=66
scope.4.semanticHash=932aec0872b09eb5
scope.5.id=function:camera_sync.follow_camera
scope.5.kind=function
scope.5.startLine=68
scope.5.endLine=84
scope.5.semanticHash=3e27eb0f9848f91c
scope.6.id=function:<anonymous>
scope.6.kind=function
scope.6.startLine=77
scope.6.endLine=79
scope.6.semanticHash=aefddfb103cf0f12
scope.7.id=function:_target_role_id
scope.7.kind=function
scope.7.startLine=86
scope.7.endLine=88
scope.7.semanticHash=616a2ca60599c94f
scope.8.id=function:_skip_following_target
scope.8.kind=function
scope.8.startLine=91
scope.8.endLine=93
scope.8.semanticHash=bff1c13a9f016483
scope.9.id=function:camera_sync.sync_camera_position
scope.9.kind=function
scope.9.startLine=95
scope.9.endLine=117
scope.9.semanticHash=648d389b0fb46a02
scope.10.id=function:<anonymous>#2
scope.10.kind=function
scope.10.startLine=104
scope.10.endLine=109
scope.10.semanticHash=449ac7be823c0e20
scope.11.id=function:camera_sync.pan_camera_to_position
scope.11.kind=function
scope.11.startLine=119
scope.11.endLine=140
scope.11.semanticHash=d10f4a333fd3836c
scope.12.id=function:camera_sync.release_target_pan
scope.12.kind=function
scope.12.startLine=142
scope.12.endLine=150
scope.12.semanticHash=9471ab3c0a5a740c
scope.13.id=function:camera_sync.reset_baseline
scope.13.kind=function
scope.13.startLine=153
scope.13.endLine=155
scope.13.semanticHash=fa86f4a0c97ffab8
]]
