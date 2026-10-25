require("test.bootstrap").install_package_paths()
-- busted injects luassert fields on assert.
-- luacheck: ignore 143
local luassert = assert
local function _assert_equal(actual, expected, message)
  luassert.is.same(expected, actual, message)
end
local support = require("test.support.shared_support")
local phase = require("src.rules.items.phase")
local resolver = require("src.rules.choice.resolver")
local availability = require("src.rules.items.availability")
local inventory = require("src.rules.items.inventory")
local item_ids = require("src.config.gameplay.item_ids")
local control = require("src.player.control")

local use_flow = require("src.rules.items.use_flow")
local phase_registry = require("src.turn.phases.registry")
local scheduler = require("src.turn.scheduler")

describe("TestItemEffectGroups", function()

local function new_game(mode, item_id)
  local g = support.new_game({ ai = mode == "replacement" and { [1] = true } or {} })
  local p = g:current_player()
  control.initialize(p)
  if mode == "manual" then control.toggle_manual_delegation(p) end
  if mode == "afk" then control.enable_afk_delegation(p) end
  p.inventory:clear()
  p.inventory:add({ id = item_id })
  p.inventory:add({ id = item_id })
  return g, p
end

local function run_phase(g, p, phase_name)
  return phase.run({ game = g }, phase_name or "pre_action", {
    player = p, next_state = "roll", next_args = { player = p },
  })
end

local function select_item(g, item_id)
  return resolver.resolve(g, assert(g.turn.pending_choice), { option_id = item_id })
end

local function _test_remote_dice_locks_only_after_success_and_keeps_the_pending_points()
  for _, mode in ipairs({ "direct", "replacement", "manual", "afk" }) do
    local g, p = new_game(mode, item_ids.remote_dice)
    run_phase(g, p)
    -- lint-allow: vacuous-branch 控制模式矩阵:仅 direct 模式需手动选卡并断言中间态,其余模式托管自动结算,循环尾部公共断言无条件覆盖
    if mode == "direct" then
      select_item(g, item_ids.remote_dice)
      luassert.is_nil(g.turn.used_effect_groups.dice_control)
      _assert_equal(inventory.count(p), 2)
      select_item(g, 3)
      _assert_equal(g:peek_pending_remote_dice(p), { 3 })
    end
    local points = {}
    for index, value in ipairs(g:peek_pending_remote_dice(p)) do points[index] = value end
    _assert_equal(inventory.count(p), 1, mode)
    _assert_equal(p.inventory.items[2].id, item_ids.remote_dice, mode)
    _assert_equal(g.turn.used_effect_groups.dice_control, true, mode)
    local rejected = use_flow.begin_item_use(g, p, item_ids.remote_dice, { phase = "pre_action" })
    luassert.is_false(rejected.ok, mode)
    _assert_equal(rejected.reason, "effect_group_used", mode)
    _assert_equal(g:peek_pending_remote_dice(p), points, mode)
    _assert_equal(p.inventory.items[2].id, item_ids.remote_dice, mode)
  end
end

local function _test_cancel_and_illegal_phase_do_not_lock_a_later_success()
  local g, p = new_game("direct", item_ids.remote_dice)
  local rejected = use_flow.begin_item_use(g, p, item_ids.remote_dice, { phase = "post_action" })
  luassert.is_false(rejected.ok)
  luassert.is_nil(g.turn.used_effect_groups.dice_control)
  run_phase(g, p)
  select_item(g, item_ids.remote_dice)
  local followup = assert(g.turn.pending_choice)
  local invalid_choice = use_flow.resolve_item_use_choice(g, followup, { option_id = 7 })
  luassert.is_false(invalid_choice.ok)
  _assert_equal(inventory.count(p), 2)
  luassert.is_nil(g.turn.used_effect_groups.dice_control)
  resolver.resolve(g, followup, { type = "choice_cancel", choice_id = followup.id })
  _assert_equal(inventory.count(p), 2)
  luassert.is_nil(g.turn.used_effect_groups.dice_control)
  select_item(g, item_ids.remote_dice)
  select_item(g, 4)
  _assert_equal(g:peek_pending_remote_dice(p), { 4 })
  _assert_equal(g.turn.used_effect_groups.dice_control, true)
end

local function _test_rejected_effect_keeps_its_consumption_policy_and_allows_a_later_grouped_card()
  local g, p = new_game("direct", item_ids.remote_dice)
  p.inventory:add({ id = item_ids.monster })
  local rejected = use_flow.begin_item_use(g, p, item_ids.monster)
  luassert.is_false(rejected.ok)
  _assert_equal(rejected.status, "rejected")
  _assert_equal(p.inventory.items[3].id, item_ids.monster)
  _assert_equal(g.turn.used_effect_groups, {})
  run_phase(g, p)
  select_item(g, item_ids.remote_dice)
  select_item(g, 5)
  _assert_equal(g:peek_pending_remote_dice(p), { 5 })
  _assert_equal(g.turn.used_effect_groups.dice_control, true)
  _assert_equal(p.inventory.items[2].id, item_ids.remote_dice)
end

local function _test_different_groups_can_succeed_in_the_same_turn()
  for _, mode in ipairs({ "direct", "replacement", "manual", "afk" }) do
    local g, p = new_game(mode, item_ids.remote_dice)
    p.inventory:add({ id = item_ids.dice_multiplier })
    run_phase(g, p)
    -- lint-allow: vacuous-branch 控制模式矩阵:仅 direct 模式需手动选卡(select_item 内含 pending_choice 断言),其余模式自动结算、循环尾部断言无条件覆盖
    if mode == "direct" then
      select_item(g, item_ids.remote_dice)
      select_item(g, 2)
    end
    run_phase(g, p, "pre_move")
    -- lint-allow: vacuous-branch 控制模式矩阵:仅 direct 模式需手动选卡(select_item 内含 pending_choice 断言),其余模式自动结算、循环尾部断言无条件覆盖
    if mode == "direct" then select_item(g, item_ids.dice_multiplier) end
    _assert_equal(inventory.count(p), 1, mode)
    _assert_equal(p.inventory.items[2].id, item_ids.remote_dice, mode)
    _assert_equal(g.turn.used_effect_groups, { dice_control = true, dice_multiply = true }, mode)
    _assert_equal(g:player_pending_dice_multiplier(p), 2, mode)
  end
end

local function _test_real_turn_cleanup_restores_the_group_on_the_next_own_turn()
  local g, p = new_game("direct", item_ids.dice_multiplier)
  run_phase(g, p, "pre_move")
  select_item(g, item_ids.dice_multiplier)
  local phases = phase_registry.build_default_phases()
  local runtime = scheduler:new(g, {
    start = function(turn_mgr)
      if g.turn.current_player_index == 1 and not g.turn.used_effect_groups.dice_multiply then
        return nil
      end
      return phases.end_turn(turn_mgr, { player = g:current_player() })
    end,
  })
  local timer = require("src.turn.policies.timer")
  runtime:run_turn()
  for _ = 1, 2 do
    timer.update_inter_turn_wait_timer(g, g.turn, 10, function() runtime:run_turn() end)
  end
  _assert_equal(g:current_player(), p)
  local allowed = availability.can_offer_in_phase(g, p, item_ids.dice_multiplier, "pre_move")
  luassert.is_true(allowed)
  run_phase(g, p, "pre_move")
  select_item(g, item_ids.dice_multiplier)
  _assert_equal(inventory.count(p), 0)
  _assert_equal(g.turn.used_effect_groups.dice_multiply, true)
end

local function _test_all_control_modes_keep_the_second_multiplier_in_its_slot()
  for _, mode in ipairs({ "direct", "replacement", "manual", "afk" }) do
    local g, p = new_game(mode, item_ids.dice_multiplier)
    run_phase(g, p, "pre_move")
    -- lint-allow: vacuous-branch 控制模式矩阵:仅 direct 模式需手动选卡(select_item 内含 pending_choice 断言),其余模式自动结算、循环尾部断言无条件覆盖
    if mode == "direct" then select_item(g, item_ids.dice_multiplier) end
    _assert_equal(inventory.count(p), 1, mode)
    _assert_equal(p.inventory.items[1], false, mode)
    _assert_equal(p.inventory.items[2].id, item_ids.dice_multiplier, mode)
    _assert_equal(g.turn.used_effect_groups.dice_multiply, true, mode)
    _assert_equal(g:player_pending_dice_multiplier(p), 2, mode)
    local allowed, reason = availability.can_offer_in_phase(g, p, item_ids.dice_multiplier, "pre_move")
    luassert.is_false(allowed, mode)
    _assert_equal(reason, "effect_group_used", mode)
  end
end

it("test_remote_dice_locks_only_after_success_and_keeps_the_pending_points", _test_remote_dice_locks_only_after_success_and_keeps_the_pending_points)
it("test_cancel_and_illegal_phase_do_not_lock_a_later_success", _test_cancel_and_illegal_phase_do_not_lock_a_later_success)
it("test_rejected_effect_keeps_its_consumption_policy_and_allows_a_later_grouped_card", _test_rejected_effect_keeps_its_consumption_policy_and_allows_a_later_grouped_card)
it("test_different_groups_can_succeed_in_the_same_turn", _test_different_groups_can_succeed_in_the_same_turn)
it("test_real_turn_cleanup_restores_the_group_on_the_next_own_turn", _test_real_turn_cleanup_restores_the_group_on_the_next_own_turn)
it("test_all_control_modes_keep_the_second_multiplier_in_its_slot", _test_all_control_modes_keep_the_second_multiplier_in_its_slot)
end)
