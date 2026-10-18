local events = require("src.ui.coord.item_slots_events")
local replay_state = require("src.ui.state.item_slot_highlight_replay")
local replay_coord = require("src.ui.coord.item_slot_highlight_replay_coord")
local highlight_lifecycle = require("src.ui.state.item_slot_highlight_lifecycle_queue")

local M = {}

-- #594:展示视角 = 本机角色 + 展示玩家,身份归一化住 ui.state 侧。
local function _replay_perspective(ctx)
  return { role_id = ctx.role_id, display_player_id = ctx.display_player_id }
end

-- 把输入侧登记的事件补上展示视角后逐个应用。判定仍住 ui.state,这里只搬运。
-- 事件留在状态里会在后续刷新迟到生效,把冻结/解冻挪到错误的时刻(#595)。
-- 输入侧登记时还不知道展示视角(视角在刷新期才解析),所以队列只带种类与
-- 选择标识,视角在这里补齐。按登记顺序应用——冻结/解冻是时序语义。
local function _apply_queued_lifecycle(state, perspective)
  local queued = highlight_lifecycle.drain(state)
  if queued == nil then
    return
  end
  for _, event in ipairs(queued) do
    replay_state.apply_lifecycle(state, perspective, event)
  end
end

-- #459:0.35s 外框延迟门控随外框一并退役,签名变化即重放,即时反馈。
-- #594:判定收归 ui.state 的 item_slot_highlight_replay,这里只投递计划。
-- #595:旧的「确认 suppress」三态旗标删除——冻结语义由生命周期事件表达
-- (confirm_item_use / slot_command / choice_released),ask 与 passive 不再
-- 分叉,刷新只有一条路径:应用队列 → 计算计划 → 投递。
function M.refresh_highlight_state(state, ctx, slot_pickable)
  local perspective = _replay_perspective(ctx)
  _apply_queued_lifecycle(state, perspective)
  replay_coord.deliver(
    replay_state.plan_refresh(state, perspective, slot_pickable),
    slot_pickable)
end

local function _current_turn(state)
  return state and state.game and state.game.turn or nil
end

-- #362 D3:phase-advance hook 锚定可选槽集合签名——集合实际变化(含变为空)
-- 才发全局「重置高亮」;phase/窗口开关空翻、槽位没变 → 不发,高亮框不回位。
-- 集合变空时的清场兜底保留(编辑器侧弹起态仍需要被复位)。
-- #596:去重判定移到 ui.state,这里只保留「回合存在才发」的宿主侧门与投递。
function M.maybe_emit_phase_advance_reset(state, slot_pickable)
  if _current_turn(state) == nil then
    return
  end
  if replay_state.needs_phase_advance_reset(state, slot_pickable) then
    events.emit_global_reset_animation()
  end
end

return M

