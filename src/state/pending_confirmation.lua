-- 二次确认屏的唯一状态存放点（GLOSSARY.md「二次确认屏」：关键操作前防误触的
-- 弹窗/全屏，显示期间属于阻断状态）。
--
-- 两个来源共用同一块屏（choice_openers.open_pre_confirm_screen）：
--   * choice_select   —— 选项点击后的二次确认
--   * item_phase_ask  —— 道具阶段入口询问
-- （item_slot 来源随槽位预确认死分支退场,见 #154:道具槽点击是直接使用,不走二次确认。）
--
-- 单记录语义：同一时刻至多一个 pending confirmation；任何来源的 enter 都会
-- 顶掉已有记录（屏是同一块，后开的屏定义当前待确认内容）。confirm/cancel 弹出
-- 并返回记录；item_phase_ask 来源额外维护「本次询问已确认」闩锁，confirm 置位、
-- cancel/reset 清除。
--
-- 存放于 state._pending_confirmation；该键的结构是本模块私有实现，
-- 其它层（含 turn 层超时子系统）一律经由本模块接口读写。
local pending_confirmation = {}

pending_confirmation.SOURCE_CHOICE_SELECT = "choice_select"
pending_confirmation.SOURCE_ITEM_PHASE_ASK = "item_phase_ask"

local _VALID_SOURCES = {
  [pending_confirmation.SOURCE_CHOICE_SELECT] = true,
  [pending_confirmation.SOURCE_ITEM_PHASE_ASK] = true,
}

local function _store(state)
  if type(state) ~= "table" then
    return nil
  end
  local store = state._pending_confirmation
  if type(store) ~= "table" then
    return nil
  end
  return store
end

local function _active(state)
  local store = _store(state)
  return store and store.active or nil
end

local function _prune(state)
  local store = _store(state)
  if store and store.active == nil and store.item_phase_confirmed == nil then
    state._pending_confirmation = nil
  end
end

local function _pop_active(state)
  local store = _store(state)
  local record = store and store.active or nil
  if store then
    store.active = nil
  end
  return record
end

function pending_confirmation.enter(state, source, payload)
  if type(state) ~= "table" or _VALID_SOURCES[source] ~= true then
    return false
  end
  payload = payload or {}
  local store = _store(state)
  if not store then
    store = {}
    state._pending_confirmation = store
  end
  store.active = {
    source = source,
    intent = payload.intent,
    option_id = payload.option_id,
    source_screen = payload.source_screen,
  }
  return true
end

local function _settle(state, item_phase_confirmed)
  local record = _pop_active(state)
  if record and record.source == pending_confirmation.SOURCE_ITEM_PHASE_ASK then
    _store(state).item_phase_confirmed = item_phase_confirmed
  end
  _prune(state)
  return record
end

function pending_confirmation.confirm(state)
  return _settle(state, true)
end

function pending_confirmation.cancel(state)
  return _settle(state, nil)
end

-- 丢弃当前记录而不触发 confirm/cancel 语义（force-skip、passive 屏切换用）。
-- 给了 source 时只清除匹配来源的记录。
function pending_confirmation.clear(state, source)
  local record = _active(state)
  if record == nil then
    return
  end
  if source ~= nil and record.source ~= source then
    return
  end
  _pop_active(state)
  _prune(state)
end

function pending_confirmation.is_active(state)
  return _active(state) ~= nil
end

function pending_confirmation.is_source_active(state, source)
  local record = _active(state)
  return record ~= nil and record.source == source
end

-- 行为测试公共查询接缝：test_pending_confirmation 经这些查询观测来源替换、
-- 载荷保留和 confirm/cancel 的清理结果，不读取私有存放字段。
function pending_confirmation.active_source(state)
  local record = _active(state)
  return record and record.source or nil
end

function pending_confirmation.stored_intent(state)
  local record = _active(state)
  return record and record.intent or nil
end

function pending_confirmation.option_id(state)
  local record = _active(state)
  return record and record.option_id or nil
end

function pending_confirmation.source_screen(state)
  local record = _active(state)
  return record and record.source_screen or nil
end

function pending_confirmation.is_item_phase_confirmed(state)
  local store = _store(state)
  return store ~= nil and store.item_phase_confirmed == true
end

function pending_confirmation.reset_item_phase_confirmed(state)
  local store = _store(state)
  if store then
    store.item_phase_confirmed = nil
    _prune(state)
  end
end

return pending_confirmation

