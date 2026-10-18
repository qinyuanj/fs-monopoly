-- 输入侧 → 刷新层的高亮生命周期事件队列(#595)。
--
-- 为什么需要它:输入侧知道「发生了什么」(确认使用 / 槽位命令 / 某个选择被
-- 关闭)但还不知道展示视角——视角要到刷新期才解析出来。此前这条信息压在单个
-- 扁平旗标 _skip_item_slot_highlight_replay_choice_id 上,刷新层只能二选一地
-- 猜:旗标在 → 确认,旗标不在 → 槽位命令。于是「旧选择迟到关闭」被误读成
-- 槽位命令而错误解冻(场景 017 要求保持冻结,只清旧高亮)。
--
-- 队列只搬运事件种类与选择标识,不含视角、不做判定:视角由刷新层补齐,判定
-- 仍住 item_slot_highlight_replay。顺序保留,因为冻结/解冻是时序语义。
local M = {}

local _QUEUE_FIELD = "_item_slot_highlight_lifecycle_queue"

-- 输入侧登记一次事件。kind 的合法取值由 item_slot_highlight_replay 断言,
-- 这里不重复校验:那边是判定真源,两处校验会各自漂移。
function M.push(state, kind, choice_id)
  assert(type(state) == "table", "missing presentation state")
  assert(type(kind) == "string", "lifecycle kind must be a string")
  local queue = state[_QUEUE_FIELD]
  if queue == nil then
    queue = {}
    state[_QUEUE_FIELD] = queue
  end
  queue[#queue + 1] = { kind = kind, choice_id = choice_id }
end

-- 取走当前所有事件并清空。取走而非只读:每个事件只应被应用一次,留在状态里
-- 会在下一次刷新重复冻结/解冻。
function M.drain(state)
  assert(type(state) == "table", "missing presentation state")
  local queue = state[_QUEUE_FIELD]
  if queue == nil then
    return nil
  end
  state[_QUEUE_FIELD] = nil
  return queue
end

return M

