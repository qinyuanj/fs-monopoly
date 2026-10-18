-- 待决选择的回合边界不变量:唯一权威。
-- 待决选择是回合内概念:动画播放期间可以挂起等待,但
-- 回合推进到下一位玩家时必然已经消失 —— wait_choice 是硬闸门,脚本走到
-- end_turn 必先穿过它,超时/force_skip 也在推进前主动清空。
--
-- 残留是缺陷,不是状态:action_button_wait 只问 pending_choice 在不在、不问
-- 它归谁,所以任何残留都会把 choice 门控带进下一位玩家的回合,对方的行动入口
-- 被拦到只能等倒计时(5ce62507 / 8d128c2f 都是这个形状)。
--
-- 不变量此前只靠约定维持:phases/registry 的 _phase_end 显式清了 market_prompt
-- / post_action / item_phase / used_effect_groups,唯独不清 pending_choice。
-- 测试期红灯让整类残留变成确定性失败;生产期不崩,warn 留证后清掉残留自愈。
local logger = require("src.foundation.log")
local dirty_tracker = require("src.state.dirty_tracker")

local lifecycle = {}

local function _describe(pending)
  local meta = pending.meta or {}
  return table.concat({
    "kind=" .. tostring(pending.kind),
    "id=" .. tostring(pending.id),
    "owner=" .. tostring(pending.owner_role_id),
    "meta.phase=" .. tostring(meta.phase),
    "meta.item_id=" .. tostring(meta.item_id),
    "meta.player_id=" .. tostring(meta.player_id),
  }, " ")
end

local function _pending_choice(game)
  local turn = game and game.turn or nil
  if turn and turn.pending_choice then
    return turn.pending_choice, turn
  end
  return nil
end

-- 测试模式下残留即断言失败;常规模式记 warn 后由调用方清理。
local function _assert_or_warn(detail)
  if logger.is_test_mode() then
    error("pending choice survived into the next turn: " .. detail, 2)
  end
  logger.warn("pending choice survived into the next turn, clearing:", detail)
end

function lifecycle.assert_cleared_on_turn_advance(game)
  local pending, turn = _pending_choice(game)
  if pending == nil then
    return
  end

  _assert_or_warn(_describe(pending))
  turn.pending_choice = nil
  dirty_tracker.mark(game.dirty, "turn")
end

return lifecycle

