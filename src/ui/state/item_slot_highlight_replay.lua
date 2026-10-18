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

--[[ mutate4lua-manifest
version=4
projectHash=e31205a51accdf9b
scope.0.id=chunk:src/ui/state/item_slot_highlight_replay.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=170
scope.0.semanticHash=ac540a5c7af990e1
scope.1.id=function:_identity_key
scope.1.kind=function
scope.1.startLine=29
scope.1.endLine=35
scope.1.semanticHash=51c996b6afb220cb
scope.2.id=function:_perspective_key
scope.2.kind=function
scope.2.startLine=37
scope.2.endLine=39
scope.2.semanticHash=405b4039a8c39341
scope.3.id=function:_memory_store
scope.3.kind=function
scope.3.startLine=41
scope.3.endLine=43
scope.3.semanticHash=a9c1c4b362850cf7
scope.4.id=function:_memory_of
scope.4.kind=function
scope.4.startLine=45
scope.4.endLine=47
scope.4.semanticHash=7b090746eee82f02
scope.5.id=function:_ensure_memory
scope.5.kind=function
scope.5.startLine=49
scope.5.endLine=51
scope.5.semanticHash=9733108c88c00d07
scope.6.id=function:_assert_boolean_slots
scope.6.kind=function
scope.6.startLine=53
scope.6.endLine=57
scope.6.semanticHash=c72bf7a4a1958e24
scope.7.id=function:_assert_public_args
scope.7.kind=function
scope.7.startLine=59
scope.7.endLine=62
scope.7.semanticHash=2e79bcfa1ac4fdea
scope.8.id=function:_signature_in
scope.8.kind=function
scope.8.startLine=65
scope.8.endLine=67
scope.8.semanticHash=616a2ca60599c94f
scope.9.id=function:_signature_or_nil
scope.9.kind=function
scope.9.startLine=70
scope.9.endLine=77
scope.9.semanticHash=5f3fe0fd79be3da4
scope.10.id=function:_plan_for_change
scope.10.kind=function
scope.10.startLine=80
scope.10.endLine=88
scope.10.semanticHash=af3b133fa40941b6
scope.11.id=function:_is_frozen
scope.11.kind=function
scope.11.startLine=91
scope.11.endLine=93
scope.11.semanticHash=dbd06b1d73637673
scope.12.id=function:_plan_while_frozen
scope.12.kind=function
scope.12.startLine=99
scope.12.endLine=107
scope.12.semanticHash=4c283fd86d810366
scope.13.id=function:M.apply_lifecycle
scope.13.kind=function
scope.13.startLine=109
scope.13.endLine=125
scope.13.semanticHash=a10872aa406a980f
scope.14.id=function:M.plan_refresh
scope.14.kind=function
scope.14.startLine=127
scope.14.endLine=143
scope.14.semanticHash=8dc9ef5c07142657
scope.15.id=function:M.needs_phase_advance_reset
scope.15.kind=function
scope.15.startLine=151
scope.15.endLine=162
scope.15.semanticHash=3aaa51b04c25ed67
scope.16.id=function:M.remembered_signature
scope.16.kind=function
scope.16.startLine=164
scope.16.endLine=167
scope.16.semanticHash=ba098355991e6e77
]]
