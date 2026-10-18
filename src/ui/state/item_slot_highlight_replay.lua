local role_id_utils = require("src.foundation.identity")
local pickable_signature = require("src.ui.state.item_slot_pickable_signature")
local tables = require("src.foundation.tables")

-- 可用槽位高亮重放的展示状态(#594)。这里只做记忆与判定,不发宿主事件:
-- ui.coord 消费 plan_refresh 的三态计划去驱动动画。
--
-- 记忆锚定「可选槽位编号集合」而非卡牌身份或窗口快照:同槽换卡、choice_id
-- 翻新、窗口开关与阶段空翻都不改变集合,故不重放。
local M = {}

-- 三态计划:整组重播 / 只清除旧高亮 / 什么都不做。
M.PLAN_REPLAY = "replay"
M.PLAN_RESET = "reset"
M.PLAN_NONE = "none"

-- 生命周期事件种类。确认使用道具冻结重放,槽位命令解冻,选择被取消/结束/
-- 替换时按 choice_id 匹配解冻。
local _LIFECYCLE_KINDS = {
  confirm_item_use = true,
  slot_command = true,
  choice_released = true,
}

-- 缺失的一侧写成明确的独立身份,而不是字符串哨兵:真实 id "none" 不能与
-- 「无本机角色」撞车,所以缺失侧用独立前缀。
local _MISSING = "\0missing"

local function _identity_key(value)
  local normalized = role_id_utils.normalize(value)
  if normalized == nil then
    return _MISSING
  end
  return "\1" .. tostring(normalized)
end

local function _perspective_key(perspective)
  return _identity_key(perspective.role_id) .. _identity_key(perspective.display_player_id)
end

local function _memory_store(state)
  return tables.ensure_absent_field(state, "_item_slot_highlight_replay")
end

local function _memory_of(state, perspective)
  return _memory_store(state)[_perspective_key(perspective)]
end

local function _ensure_memory(state, perspective)
  return tables.ensure_absent_field(_memory_store(state), _perspective_key(perspective))
end

local function _assert_boolean_slots(slot_pickable)
  for _, can_pick in ipairs(slot_pickable) do
    assert(can_pick == true or can_pick == false, "slot_pickable must hold booleans")
  end
end

local function _assert_public_args(state, perspective)
  assert(type(state) == "table", "missing presentation state")
  assert(type(perspective) == "table", "missing display perspective")
end

-- 无记忆(nil)与记住了空集合("")是不同状态,读侧统一走这里。
local function _signature_in(memory)
  return memory and memory.signature or nil
end

-- 快照校验。没有快照返回 nil —— 不能冒充空集合。
local function _signature_or_nil(slot_pickable)
  if slot_pickable == nil then
    return nil
  end
  assert(type(slot_pickable) == "table", "slot_pickable must be an array or nil")
  _assert_boolean_slots(slot_pickable)
  return pickable_signature.of(slot_pickable)
end

-- 首次观察空集合只清除旧高亮;此后集合变化(含变为空)都整组重播。
local function _plan_for_change(remembered, signature)
  if remembered == signature then
    return M.PLAN_NONE
  end
  if remembered == nil and signature == "" then
    return M.PLAN_RESET
  end
  return M.PLAN_REPLAY
end

-- 冻结判定:同一视角、同一待决选择在确认后不重放,直到槽位命令或该选择被释放。
local function _is_frozen(memory)
  return memory ~= nil and memory.frozen_choice_id ~= nil
end

-- 冻结期间的计划:永不整组重播,但集合真的变了要清除旧高亮 —— 旧高亮框指向的
-- 槽位已经不是可选的了,留在屏上是错的视觉(#595 场景 012)。集合没变则什么都
-- 不做,不反复清除。照记新集合:否则解冻时会补一次陈旧重放,而槽位命令本身
-- 只解冻、不强制重放。
local function _plan_while_frozen(memory, signature)
  local remembered = _signature_in(memory)
  memory.signature = signature
  -- 没有旧记忆时屏上没有陈旧高亮框可清,发 reset 只是无谓地打断确认中的视觉。
  if remembered ~= nil and remembered ~= signature then
    return M.PLAN_RESET
  end
  return M.PLAN_NONE
end

function M.apply_lifecycle(state, perspective, event)
  _assert_public_args(state, perspective)
  assert(type(event) == "table", "missing lifecycle event")
  assert(_LIFECYCLE_KINDS[event.kind] == true,
    "unknown lifecycle kind: " .. tostring(event.kind))
  local memory = _ensure_memory(state, perspective)
  if event.kind == "confirm_item_use" then
    memory.frozen_choice_id = event.choice_id
    return
  end
  -- 槽位命令无条件解冻(玩家已经动过手);选择释放只解除匹配该选择的冻结,
  -- 故新选择替换旧冻结后,迟到的旧选择关闭不会误解冻(#595 场景 017)。
  if event.kind == "slot_command"
    or tostring(memory.frozen_choice_id) == tostring(event.choice_id) then
    memory.frozen_choice_id = nil
  end
end

function M.plan_refresh(state, perspective, slot_pickable)
  _assert_public_args(state, perspective)
  local signature = _signature_or_nil(slot_pickable)
  -- 暂时没有槽位快照:不动计划也不改记忆。
  if signature == nil then
    return M.PLAN_NONE
  end
  local memory = _memory_of(state, perspective)
  if _is_frozen(memory) then
    return _plan_while_frozen(memory, signature)
  end
  local plan = _plan_for_change(_signature_in(memory), signature)
  if plan ~= M.PLAN_NONE then
    _ensure_memory(state, perspective).signature = signature
  end
  return plan
end

-- #596:phase-advance 的「集合真的变了才发全局重置」判定。与逐视角重放记忆不同,
-- 这是一条全局去重线(编辑器侧弹起态需要被复位),故不带 perspective。
--
-- 无快照与空集合是两个不同状态:前者「还不知道」,后者「确实没有可选槽」。旧实现
-- 用字符串哨兵 "none" 区分,那会与真实签名撞车;这里靠「有没有记录过」与
-- signature 是否为 nil 表达,语义不再依赖任何魔法字符串。
function M.needs_phase_advance_reset(state, slot_pickable)
  assert(type(state) == "table", "missing presentation state")
  local signature = _signature_or_nil(slot_pickable)
  local seen = state._item_slot_phase_advance
  -- seen == nil 是「从未记录」,与「记录过一次无快照」(seen.signature == nil)
  -- 不同:首次观察必须发一次重置,故只有记录过且签名相同才去重。
  if seen ~= nil and seen.signature == signature then
    return false
  end
  state._item_slot_phase_advance = { signature = signature }
  return true
end

-- GLOSSARY「可用槽位高亮重放」的逐视角记忆查询，供冻结/隔离行为性质测试观察。
function M.remembered_signature(state, perspective)
  _assert_public_args(state, perspective)
  return _signature_in(_memory_of(state, perspective))
end

return M

