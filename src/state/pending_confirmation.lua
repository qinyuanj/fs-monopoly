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

function pending_confirmation.confirm(state)
  local record = _pop_active(state)
  if record and record.source == pending_confirmation.SOURCE_ITEM_PHASE_ASK then
    _store(state).item_phase_confirmed = true
  end
  _prune(state)
  return record
end

function pending_confirmation.cancel(state)
  local record = _pop_active(state)
  if record and record.source == pending_confirmation.SOURCE_ITEM_PHASE_ASK then
    _store(state).item_phase_confirmed = nil
  end
  _prune(state)
  return record
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

--[[ mutate4lua-manifest
version=4
projectHash=02a822c90293a0eb
scope.0.id=chunk:src/state/pending_confirmation.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=152
scope.0.semanticHash=90abe6730d4f6a9e
scope.1.id=function:_store
scope.1.kind=function
scope.1.startLine=26
scope.1.endLine=35
scope.1.semanticHash=abf463ed46af8fe6
scope.2.id=function:_active
scope.2.kind=function
scope.2.startLine=37
scope.2.endLine=40
scope.2.semanticHash=9225cfe7b87d962b
scope.3.id=function:_prune
scope.3.kind=function
scope.3.startLine=42
scope.3.endLine=47
scope.3.semanticHash=ca537ea2c124dc24
scope.4.id=function:_pop_active
scope.4.kind=function
scope.4.startLine=49
scope.4.endLine=56
scope.4.semanticHash=f66bf3e480433840
scope.5.id=function:pending_confirmation.enter
scope.5.kind=function
scope.5.startLine=58
scope.5.endLine=75
scope.5.semanticHash=73777f34fa4f5619
scope.6.id=function:pending_confirmation.confirm
scope.6.kind=function
scope.6.startLine=77
scope.6.endLine=84
scope.6.semanticHash=ad3824395b179e91
scope.7.id=function:pending_confirmation.cancel
scope.7.kind=function
scope.7.startLine=86
scope.7.endLine=93
scope.7.semanticHash=a34b681eae81e1c6
scope.8.id=function:pending_confirmation.clear
scope.8.kind=function
scope.8.startLine=97
scope.8.endLine=107
scope.8.semanticHash=dd4ef25440b3ee18
scope.9.id=function:pending_confirmation.is_active
scope.9.kind=function
scope.9.startLine=109
scope.9.endLine=111
scope.9.semanticHash=41ca328ef191d311
scope.10.id=function:pending_confirmation.is_source_active
scope.10.kind=function
scope.10.startLine=113
scope.10.endLine=116
scope.10.semanticHash=2cd7b2a52950da7e
scope.11.id=function:pending_confirmation.active_source
scope.11.kind=function
scope.11.startLine=118
scope.11.endLine=121
scope.11.semanticHash=9225cfe7b87d962b
scope.12.id=function:pending_confirmation.stored_intent
scope.12.kind=function
scope.12.startLine=123
scope.12.endLine=126
scope.12.semanticHash=9225cfe7b87d962b
scope.13.id=function:pending_confirmation.option_id
scope.13.kind=function
scope.13.startLine=128
scope.13.endLine=131
scope.13.semanticHash=9225cfe7b87d962b
scope.14.id=function:pending_confirmation.source_screen
scope.14.kind=function
scope.14.startLine=133
scope.14.endLine=136
scope.14.semanticHash=9225cfe7b87d962b
scope.15.id=function:pending_confirmation.is_item_phase_confirmed
scope.15.kind=function
scope.15.startLine=138
scope.15.endLine=141
scope.15.semanticHash=883230f506e0c097
scope.16.id=function:pending_confirmation.reset_item_phase_confirmed
scope.16.kind=function
scope.16.startLine=143
scope.16.endLine=149
scope.16.semanticHash=0c4ce1994ff9b387
]]
