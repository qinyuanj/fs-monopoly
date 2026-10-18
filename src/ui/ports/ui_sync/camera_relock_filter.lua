-- 相机重锁滤波:按 role 记基线,对发给宿主的 lock 取值做三档滤波。
-- 原 ui_sync/camera.lua 的滤波机件;camera.lua 保留编排与公共面。
local runtime_ui = require("src.ui.render.support.runtime_ui")

local M = {}

-- sync 稳态重锁的三档滤波(#451 真机取证,165274 行打点/局):
--   < 0.01   取值微漂移(get_position 永不收敛,1e-5/tick):不重发,否则宿主每 tick
--            重启插值,稳态也抖(H2,占整局 lock 的 56%);
--   0.01~0.6 正常行走(实测峰值 0.48/tick):原样透传;
--   0.6~6    落格 snap 瞬移(实测 2~5 格带 Y 回弹,landing→action 阶段切换必现):
--            按 0.6/tick 滑行逼近,直接跟=镜头瞬移 jitter(H1);
--   > 6      卡牌/入狱传送与换人(数十格):立即切,滑行会拖数秒。
-- 基线是每个 role 最近一次实际发给宿主的 lock 取值:follow/pan 的直接 lock 会
-- 重基(换人后首 tick 不会拿旧基线误判成传送),reset 回自己时清位。
local SYNC_RELOCK_EPS = 0.01
local SYNC_GLIDE_MAX_STEP = 0.6
local SYNC_TELEPORT_MIN_DIST = 6.0

local _sync_lock_baseline = {}

-- pcall 读分量:取不出(宿主对象读字段报错)时返回 nil,成功返回 x,y,z。
local function _read_pos_xyz(pos)
  local ok, x, y, z = pcall(function()
    return pos.x, pos.y, pos.z
  end)
  if not ok then
    return nil
  end
  return x, y, z
end

function M.pos_components(pos)
  if pos == nil then
    return nil
  end
  local x, y, z = _read_pos_xyz(pos)
  if x == nil or y == nil or z == nil then
    return nil
  end
  return x, y, z
end

-- 基线按 role 身份而不是 role 对象做 key:真机上 role 是 CampRole userdata,
-- 沙盒禁止 userdata 当 table key(真机 2026-08-11 报错:table index can only
-- be a string/integer/real)。拿不到 role_id 时退 tostring(role) 保住对象级隔离。
local function _baseline_key(role)
  local role_id = runtime_ui.resolve_role_id(role)
  if role_id ~= nil then
    return role_id
  end
  return tostring(role)
end

function M.record_baseline(role, pos)
  local x, y, z = M.pos_components(pos)
  if x == nil then
    return
  end
  local key = _baseline_key(role)
  local baseline = _sync_lock_baseline[key]
  if baseline == nil then
    baseline = {}
    _sync_lock_baseline[key] = baseline
  end
  baseline[1], baseline[2], baseline[3] = x, y, z
end

function M.clear_baseline(role)
  _sync_lock_baseline[_baseline_key(role)] = nil
end

-- 透传档:正常行走步长(≤0.6)与传送级跳变(>6)原样发送,只有落格 snap 走滑行。
local function _is_passthrough_dist(dist)
  return dist <= SYNC_GLIDE_MAX_STEP or dist > SYNC_TELEPORT_MIN_DIST
end

-- 返回要发送的取值,nil 表示本 tick 去重不重发。分量取不出时透传保持旧行为。
-- 距离按分量手算而不用 Vector3:length():测试环境 test_env 的 Vector3 stub
-- 是纯表无 :length(),而这里必须覆盖测试;真机两者等价。
function M.filter_value(role, target_pos)
  local x, y, z = M.pos_components(target_pos)
  if x == nil then
    return target_pos
  end
  local last = _sync_lock_baseline[_baseline_key(role)]
  if last == nil then
    return target_pos
  end
  local dx, dy, dz = x - last[1], y - last[2], z - last[3]
  local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
  if dist < SYNC_RELOCK_EPS then
    return nil
  end
  if _is_passthrough_dist(dist) then
    return target_pos
  end
  local scale = SYNC_GLIDE_MAX_STEP / dist
  return math.Vector3(last[1] + dx * scale, last[2] + dy * scale, last[3] + dz * scale)
end

-- 新局开局钩子:全清滤波基线,防止跨局同 role_id 首帧被误去重(#454)。
-- 基线是模块级存活表;新游戏开始前须清空,否则上局末帧位置与新局首帧重合时,
-- 首帧 <0.01 阈值判断命中去重,镜头停在旧位置直到目标移动才自愈。
function M.reset()
  _sync_lock_baseline = {}
end

return M

