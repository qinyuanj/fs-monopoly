-- Regression pin (wayfinder: item-multi-use-regression, ticket 01).
-- Baseline: 掷骰前的可选行动窗口里，玩家可连续使用任意数量合法道具；
-- 唯一数量限制是同组道具单回合一次（used_effect_groups）。用完一张
-- 非掷骰道具后窗口必须重新开放，直到玩家主动结束或超时才推进。
-- luacheck: std +busted
require("test.bootstrap").install_package_paths()
local luassert = assert
local support = require("test.support.shared_support")
local turn_runtime = require("src.turn.scheduler")
local inventory = require("src.rules.items.inventory")
local item_ids = require("src.config.gameplay.item_ids")
local item_phase = require("src.rules.items.phase")
local config_reset = require("test.support.config_reset")

describe("TestItemWindowMultiUse", function()

before_each(function()
  config_reset.reset_all()
end)

-- 动画门打开（宿主口径 wait_action_anim = true）：带动画的道具（天使/地雷/导弹…）
-- 用掉后 action_anim 正在播，重开的道具窗口一度被 finish_choice 连带清掉，
-- 表现为“用一张卡之后就不能再用卡”。窗口必须活到动画收尾之后。
local function _anim_enabled_game()
  local g = support.new_game()
  g.anim_gate_port = { wait_move_anim = true, wait_action_anim = true }
  return g
end

local function _wait_choice_engine(g, flow)
  g.turn_runtime = turn_runtime:new(g, {
    start = function()
      return "wait_choice", { next_state = "after_items", next_args = {} }
    end,
    after_items = function()
      flow.resumed = true
      return nil
    end,
  })
end

local function _assert_window_survives_anim_item(phase, used_item_id, kept_item_id, label)
  local g = _anim_enabled_game()
  local flow = { resumed = false }
  _wait_choice_engine(g, flow)
  local p = g:current_player()
  p.inventory:clear()
  p.inventory:add({ id = used_item_id })
  p.inventory:add({ id = kept_item_id })

  local spec = item_phase.build_passive_choice_spec(g, p, phase, {
    next_state = "after_items",
    next_args = {},
  })
  luassert.truthy(spec, phase .. " item window should open with two usable items")
  local window = support.open_choice(g, spec)
  g:advance_turn()

  g:dispatch_action({
    type = "choice_select",
    choice_id = window.id,
    option_id = used_item_id,
    actor_role_id = p.id,
  })

  luassert.truthy(g.turn.action_anim ~= nil, label .. " should queue an action anim (fixture precondition)")
  luassert.truthy(flow.resumed == false, label .. " must not advance the turn while a legal item remains")
  local reopened = g.turn.pending_choice
  luassert.truthy(reopened ~= nil and reopened.kind == "item_phase_passive",
    label .. " item window must survive the action anim, not be finished away")
  luassert.truthy(inventory.count(p) == 1, label .. " should leave the second item usable")
end

-- 主用例 real turn machine 掷骰 → 移动 → 落地走 game.rng（→ 全局 math.random）。
-- 兄弟 spec 消耗不定数量的 RNG（尤见 startup_profile_spec 的
-- _reload_app_init_with_stubs 与 chance_executor_spec 的抽卡），在并行 LPT 分桶里
-- 排进同一 worker 时会让进入本用例的 RNG 状态漂移、落地格随之改变、玩家可能拾得
-- 道具而使 inventory.count 断言假红。进入每例的 RNG 重播现由 test/helper.lua 套件级
-- 统一负责(每例 test/start 重播 test_env.DEFAULT_SEED),取代原先此处的 randomseed(1)
-- band-aid(#45/#46)。守卫见 test/behavior/foundation/test_rng_reset_isolation.lua。
-- 全真实回合机：phase start 自己打开 pre_action 窗口（wait_action 挂起），
-- 与实际游戏同一条链路。这是钉症状的主用例。
it("test_real_turn_machine_keeps_the_item_window_open_across_consecutive_item_uses", function()
  local g = support.new_game()
  local p = g:current_player()
  p.inventory:clear()
  p.inventory:add({ id = item_ids.mine })
  p.inventory:add({ id = item_ids.angel })

  g:advance_turn()

  local window = g.turn.pending_choice
  luassert.truthy(window ~= nil and window.kind == "item_phase_passive",
    "turn start should open the pre_action item window")

  g:dispatch_action({
    type = "choice_select",
    choice_id = window.id,
    option_id = item_ids.mine,
    actor_role_id = p.id,
  })

  local reopened = g.turn.pending_choice
  luassert.truthy(reopened ~= nil, "item window should reopen after a non-dice item use, not advance the turn")
  luassert.truthy(reopened.kind == "item_phase_passive", "reopened window should still be the passive item window")

  g:dispatch_action({
    type = "choice_select",
    choice_id = reopened.id,
    option_id = item_ids.angel,
    actor_role_id = p.id,
  })

  luassert.truthy(inventory.count(p) == 0, "both items should be consumed within the same turn")
end)

-- followup 道具是本阶段最后一张可用牌：阶段落定（无窗可重开）时，已结算的
-- 跟随选择必须被清掉。残留的 pending_choice 会把 choice 门控带进后续流程/
-- 下一位玩家的回合——行动按钮被拦、只能干等倒计时（偶现"没询问直接跳过"报障）。
it("test_followup_item_as_the_last_card_clears_the_resolved_followup_choice", function()
  local g = support.new_game()
  local flow = { resumed = false }
  g.turn_runtime = turn_runtime:new(g, {
    start = function()
      return "wait_choice", { next_state = "after_items", next_args = {} }
    end,
    after_items = function()
      flow.resumed = true
      return nil
    end,
  })
  local p = g:current_player()
  p.inventory:clear()
  p.inventory:add({ id = item_ids.roadblock })

  local spec = item_phase.build_passive_choice_spec(g, p, "post_action", {
    next_state = "after_items",
    next_args = {},
  })
  luassert.truthy(spec, "post_action item window should open with the roadblock")
  local window = support.open_choice(g, spec)
  g:advance_turn()

  g:dispatch_action({
    type = "choice_select",
    choice_id = window.id,
    option_id = item_ids.roadblock,
    actor_role_id = p.id,
  })
  local followup = g.turn.pending_choice
  luassert.truthy(followup ~= nil and followup.kind == "roadblock_target",
    "roadblock should open its target follow-up choice")

  local option = followup.options[1]
  luassert.truthy(option, "roadblock follow-up should offer tiles")
  g:dispatch_action({
    type = "choice_select",
    choice_id = followup.id,
    option_id = option.id,
    actor_role_id = p.id,
  })

  luassert.truthy(inventory.count(p) == 0, "roadblock should be consumed")
  luassert.truthy(flow.resumed == true, "phase with no remaining cards should let the turn resume")
  luassert.truthy(g.turn.pending_choice == nil,
    "resolved roadblock_target must not linger as pending_choice after the phase finishes")
end)

-- followup 链路：路障需要跟随选格子，走 item_completions 完成链
-- （与地雷/天使的立即执行链不同）。完成后窗口同样必须重开。
it("test_real_turn_machine_reopens_the_window_after_a_followup_item_completes", function()
  local g = support.new_game()
  local p = g:current_player()
  p.inventory:clear()
  p.inventory:add({ id = item_ids.roadblock })
  p.inventory:add({ id = item_ids.mine })

  g:advance_turn()
  local window = g.turn.pending_choice
  luassert.truthy(window ~= nil and window.kind == "item_phase_passive",
    "turn start should open the pre_action item window")

  g:dispatch_action({
    type = "choice_select",
    choice_id = window.id,
    option_id = item_ids.roadblock,
    actor_role_id = p.id,
  })

  local followup = g.turn.pending_choice
  luassert.truthy(followup ~= nil and followup.kind == "roadblock_target",
    "roadblock should open its target follow-up choice")

  local option = followup.options[1]
  luassert.truthy(option, "roadblock follow-up should offer tiles")
  g:dispatch_action({
    type = "choice_select",
    choice_id = followup.id,
    option_id = option.id,
    actor_role_id = p.id,
  })

  local reopened = g.turn.pending_choice
  luassert.truthy(reopened ~= nil and reopened.kind == "item_phase_passive",
    "item window should reopen after the follow-up completes, not advance the turn")
  luassert.truthy(inventory.count(p) == 1, "mine should remain usable after the roadblock was consumed")
end)

-- RED（已知缺陷，修复票的红灯）：post_action 窗口 + followup/target 道具
-- 用完后窗口应重开（地雷仍可用），当前被 item_completions.lua 的
-- phase=="post_action" 早退分支直接 finish，回合推进（flow.resumed==true 处红）。
-- 修复时把 pending 换回 it。
it("test_post_action_window_reopens_after_a_followup_item_completes", function()
  local g = support.new_game()
  local flow = { resumed = false }
  g.turn_runtime = turn_runtime:new(g, {
    start = function()
      return "wait_choice", { next_state = "after_items", next_args = {} }
    end,
    after_items = function()
      flow.resumed = true
      return nil
    end,
  })
  local p = g:current_player()
  p.inventory:clear()
  p.inventory:add({ id = item_ids.roadblock })
  p.inventory:add({ id = item_ids.mine })

  local spec = item_phase.build_passive_choice_spec(g, p, "post_action", {
    next_state = "after_items",
    next_args = {},
  })
  luassert.truthy(spec, "post_action item window should open with two usable items")
  local window = support.open_choice(g, spec)
  g:advance_turn()

  g:dispatch_action({
    type = "choice_select",
    choice_id = window.id,
    option_id = item_ids.roadblock,
    actor_role_id = p.id,
  })
  local followup = g.turn.pending_choice
  luassert.truthy(followup ~= nil and followup.kind == "roadblock_target",
    "roadblock should open its target follow-up choice")

  local option = followup.options[1]
  luassert.truthy(option, "roadblock follow-up should offer tiles")
  g:dispatch_action({
    type = "choice_select",
    choice_id = followup.id,
    option_id = option.id,
    actor_role_id = p.id,
  })

  luassert.truthy(flow.resumed == false,
    "post_action followup completion must not advance the turn while legal items remain")
  local reopened = g.turn.pending_choice
  luassert.truthy(reopened ~= nil and reopened.kind == "item_phase_passive",
    "post_action item window should reopen after the follow-up completes")
  luassert.truthy(inventory.count(p) == 1, "mine should remain usable after the roadblock was consumed")
end)

it("test_post_action window survives 天使卡 while its action anim plays", function()
  _assert_window_survives_anim_item("post_action", item_ids.angel, item_ids.mine, "天使卡 (post_action)")
end)

it("test_pre_action window survives 地雷卡 while its action anim plays", function()
  _assert_window_survives_anim_item("pre_action", item_ids.mine, item_ids.angel, "地雷卡 (pre_action)")
end)

-- 缩窄用例：合成 turn_runtime 直接挂 wait_choice，只覆盖 dispatch→resolve→reopen
-- 子链路。真实用例红、这条绿时，断裂点在两者的差集（wait_action 转移 / decide 策略）。
it("test_wait_choice_sub_chain_reopens_the_window_after_a_non_dice_item", function()
  local g = support.new_game()
  local flow = { resumed = false }
  g.turn_runtime = turn_runtime:new(g, {
    start = function()
      return "wait_choice", { next_state = "after_items", next_args = {} }
    end,
    after_items = function()
      flow.resumed = true
      return nil
    end,
  })
  local p = g:current_player()
  p.inventory:clear()
  p.inventory:add({ id = item_ids.mine })
  p.inventory:add({ id = item_ids.angel })

  local spec = item_phase.build_passive_choice_spec(g, p, "pre_action", {
    next_state = "after_items",
    next_args = {},
  })
  luassert.truthy(spec, "pre_action item window should open with two usable items")
  local choice = support.open_choice(g, spec)

  g:advance_turn()
  luassert.truthy(g.turn.phase == "wait_choice", "turn should wait on the item window")

  g:dispatch_action({
    type = "choice_select",
    choice_id = choice.id,
    option_id = item_ids.mine,
    actor_role_id = p.id,
  })

  luassert.truthy(flow.resumed == false, "using one item must not advance the turn past the item window")
  local reopened = g.turn.pending_choice
  luassert.truthy(reopened ~= nil, "item window should reopen after a non-dice item use")
  luassert.truthy(reopened.kind == "item_phase_passive", "reopened window should still be the passive item window")

  g:dispatch_action({
    type = "choice_select",
    choice_id = reopened.id,
    option_id = item_ids.angel,
    actor_role_id = p.id,
  })

  luassert.truthy(inventory.count(p) == 0, "both items should be consumed within the same turn")
end)


end)
