require("test.bootstrap").install_package_paths()
-- luacheck: ignore 143 (busted injects the verified luassert object)
local luassert = assert
-- Mutation-closure pins for src/rules/items/handlers.lua.
-- The item-use handlers are registered into the item registry and exercised
-- through integration in item_spec, which leaves the dispatch-layer branch and
-- literal mutations alive. This spec drives the exported handle_* functions
-- directly, patching the injected ports (effects.apply_target, inventory,
-- action_anim_port, auto_play, demolish, roadblock, remote_dice, event_feed)
-- so each branch is observable in isolation:
--   * handle_target_player_item target_id validation (nil / self / eliminated /
--     not-in-candidates) and the apply orchestration helpers
--     (_resolve_apply_ok shapes, _maybe_consume_item skips, _finalize_apply,
--     _apply_share_wealth_context, _queue_target_player_anim payload),
--   * _run_item_choice_flow empty / ai / human branches,
--   * handle_remote_dice ai feed-publish guard and choice spec,
--   * handle_roadblock ai vs manual candidate source and choice spec,
--   * handle_demolish cfg dispatch (monster / missile) and missing-cfg assert.
-- Routed by architect (agent_context/rules-mutation-bootstrap-debt.md).
--
local support = require("test.support.shared_support")
local default_map = require("src.config.content.default_map")
local event_kinds = require("src.config.gameplay.event_kinds")
local item_ids = require("src.config.gameplay.item_ids")
local timing = require("src.config.gameplay.timing")
local config_reset = require("test.support.config_reset")

local handlers = require("src.rules.items.handlers")
local effects = require("src.rules.items.post_effects")
local inventory = require("src.rules.items.inventory")
local action_anim_port = require("src.foundation.ports.action_anim")
local auto_play_port = require("src.rules.ports.auto_play")
local demolish = require("src.rules.items.demolish")
local roadblock = require("src.rules.items.roadblock")
local remote_dice = require("src.rules.items.remote_dice")
local event_feed = require("src.rules.ports.event_feed")
local settlement = require("src.rules.items.settlement")

local function _assert_eq(a, b, msg) luassert.is.equal(b, a, msg) end
local _with_patches = support.with_patches
local _anim_duration = timing.action_anim_default_seconds or 1.0

local function _game(players)
  return support.new_game({ map = default_map, players = players or { "P1", "P2" } })
end

-- handle_target_player_item target_id validation:target_id 校验用上下文。
local function _ctx(g, target_id)
  local other = g.players[2]
  return {
    resolve_target_candidates = function() return { other } end,
    target_id = target_id,
  }
end

-- apply orchestration helpers:经 handle_target_player_item 驱动
-- _apply_target_player_item,patched effects.apply_target 控制结果形状。
local function _run(g, item_id, apply_res, extra_ctx)
  local other = g.players[2]
  local consumed, queued_payload
  local ctx = { resolve_target_candidates = function() return { other } end, target_id = other.id }
  for k, v in pairs(extra_ctx or {}) do ctx[k] = v end
  local result
  _with_patches({
    { target = effects, key = "apply_target", value = function() return apply_res end },
    { target = inventory, key = "consume", value = function() consumed = true; return true end },
    { target = action_anim_port, key = "queue", value = function(_, payload) queued_payload = payload; return true end },
  }, function()
    result = handlers.handle_target_player_item(g, g.players[1], item_id, ctx)
  end)
  return result, consumed, queued_payload, ctx
end

-- handle_remote_dice ai 分支:收集 event_feed 发布物。
local function _run_ai(g, value, target_tile, apply_res)
  local published = {}
  _with_patches({
    { target = auto_play_port, key = "pick_remote_dice_value", value = function() return value, target_tile end },
    { target = inventory, key = "consume", value = function() return true end },
    { target = remote_dice, key = "apply", value = function() return apply_res end },
    { target = event_feed, key = "publish", value = function(_, entry) published[#published + 1] = entry end },
  }, function()
    handlers.handle_remote_dice(g, g.players[1], item_ids.remote_dice, { is_computer_controlled = true })
  end)
  return published
end

-- handle_demolish cfg dispatch:捕获 demolish.use 收到的参数。
local function _capture_use(g, item_id, context)
  local captured
  g.players[1].inventory:add({ id = item_id })
  _with_patches({
    -- 假 applier 也要履行 applier_owned 契约:apply 成功前必须经 consume_fn 提交消耗
    { target = demolish, key = "use", value = function(_, _, idx, consume_fn, opts)
        captured = { idx = idx, consume_fn = consume_fn, opts = opts }
        luassert.truthy(consume_fn() == true, "consume_fn must commit")
        return { ok = true }
      end },
  }, function()
    handlers.handle_demolish(g, g.players[1], item_id, context or {})
  end)
  return captured
end

-- --------------------------------------------------------------------------
-- item handlers — handle_target_player_item target_id validation
-- --------------------------------------------------------------------------


describe("TestItemHandlersTargetIdValidation", function()
  before_each(function()
    config_reset.reset_all()
  end)
  it("test_rejects_a_target_id_that_resolves_to_no_player", function()
    local g = _game()
    local res = handlers.handle_target_player_item(g, g.players[1], item_ids.exile, _ctx(g, 999999))
    _assert_eq(res, false, "an unresolved target id is rejected")
  end)

  it("test_rejects_targeting_yourself", function()
    local g = _game()
    local p = g.players[1]
    local res = handlers.handle_target_player_item(g, p, item_ids.exile, _ctx(g, p.id))
    _assert_eq(res, false, "self-target is rejected")
  end)

  it("test_rejects_an_eliminated_target", function()
    local g = _game()
    g.players[2].eliminated = true
    local res = handlers.handle_target_player_item(g, g.players[1], item_ids.exile, _ctx(g, g.players[2].id))
    _assert_eq(res, false, "an eliminated target is rejected")
  end)

  it("test_rejects_a_valid_target_that_is_absent_from_the_candidate_list", function()
    local g = _game()
    local res = handlers.handle_target_player_item(g, g.players[1], item_ids.exile, {
      resolve_target_candidates = function() return {} end, -- candidate list excludes the target
      target_id = g.players[2].id,
    })
    _assert_eq(res, false, "a target missing from the candidates is rejected")
  end)

-- --------------------------------------------------------------------------
-- item handlers — apply orchestration helpers
-- --------------------------------------------------------------------------
end)


describe("TestItemHandlersApplyOrchestration", function()
  before_each(function()
    config_reset.reset_all()
  end)
  it("test_a_table_result_with_ok_true_consumes_the_item_and_queues_the_target_anim", function()
    local g = _game()
    local res, consumed, payload = _run(g, item_ids.exile, { ok = true })
    _assert_eq(consumed, true, "a successful apply consumes the item")
    _assert_eq(res.ok, true, "the result is stamped ok")
    _assert_eq(res.action_anim, true, "the queued anim flag is set on the result")
    _assert_eq(payload.kind, "item_target_player", "the queued anim is an item_target_player anim")
    _assert_eq(payload.player_id, g.players[1].id, "the anim carries the user id")
    _assert_eq(payload.target_player_id, g.players[2].id, "the anim carries the target id")
    _assert_eq(payload.item_id, item_ids.exile, "the anim carries the item id")
    -- #293:item_name(→nil 变异)未测。
    _assert_eq(payload.item_name, inventory.item_name(item_ids.exile), "the anim carries the item name")
    _assert_eq(payload.duration, _anim_duration, "the anim uses the default duration")
  end)

  it("test_a_table_result_with_ok_false_aborts_before_consuming_or_queueing", function()
    local g = _game()
    local res, consumed, payload = _run(g, item_ids.exile, { ok = false })
    _assert_eq(consumed, nil, "a failed apply does not consume the item")
    _assert_eq(payload, nil, "a failed apply queues no anim")
    _assert_eq(res.ok, false, "the failing result is returned verbatim")
  end)

  it("test_a_bare_true_result_is_treated_as_ok_and_finalized_into_a_table", function()
    local g = _game()
    local res, consumed = _run(g, item_ids.exile, true)
    _assert_eq(consumed, true, "a bare-true result still consumes")
    _assert_eq(res.ok, true, "a non-table result is wrapped with ok=true")
    _assert_eq(res.action_anim, true, "the wrapper records the queued anim")
  end)

  it("test_a_table_result_with_no_ok_field_defaults_to_applied", function()
    local g = _game()
    -- _resolve_apply_ok returns true for a table that omits a boolean ok, so
    -- the apply proceeds to consume/queue/finalize rather than aborting.
    local res, consumed, payload = _run(g, item_ids.exile, { note = "no ok field" })
    _assert_eq(consumed, true, "a table without an explicit ok is treated as applied and consumes")
    _assert_eq(res.ok, true, "_finalize_apply stamps ok=true onto the ok-less table")
    _assert_eq(payload ~= nil, true, "the target anim is queued for an ok-less success")
  end)

  it("test_a_result_flagged_item_consumed_skips_the_consume_step", function()
    local g = _game()
    local _, consumed = _run(g, item_ids.exile, { ok = true, item_consumed = true })
    _assert_eq(consumed, nil, "an already-consumed result must not double-consume")
  end)

  it("test_an_apply_that_already_queued_its_own_anim_is_not_re_queued", function()
    local g = _game()
    local res, _, payload = _run(g, item_ids.exile, { ok = true, action_anim = true })
    _assert_eq(payload, nil, "the handler must not queue a second anim")
    _assert_eq(res.action_anim, true, "the apply's own anim flag is preserved")
  end)

  it("test_share_wealth_seeds_the_cash_receive_context_other_items_leave_it_untouched", function()
    local g1 = _game()
    local _, _, _, share_ctx = _run(g1, item_ids.share_wealth, { ok = true })
    _assert_eq(share_ctx.share_wealth_cash_receive_mode, "item_target_player_only",
      "share_wealth routes cash receive through the target-player anim")
    _assert_eq(share_ctx.suppress_cash_receive_anim, true, "share_wealth suppresses the default cash-receive anim")

    local g2 = _game()
    local _, _, _, other_ctx = _run(g2, item_ids.exile, { ok = true })
    _assert_eq(other_ctx.share_wealth_cash_receive_mode, nil,
      "a non-share item leaves the share_wealth context unset")
  end)

-- --------------------------------------------------------------------------
-- item handlers — choice flow branches
-- --------------------------------------------------------------------------
end)


describe("TestItemHandlersChoiceFlowBranches", function()
  before_each(function()
    config_reset.reset_all()
  end)
  it("test_an_empty_candidate_list_short_circuits_to_false", function()
    local g = _game()
    local res = handlers.handle_target_player_item(g, g.players[1], item_ids.exile, {
      resolve_target_candidates = function() return {} end,
    })
    _assert_eq(res, false, "no candidates yields false")
  end)

  it("test_an_ai_actor_applies_against_the_auto_picked_target", function()
    local g = _game()
    local other = g.players[2]
    local picked, consumed, settlement_opts
    local res
    _with_patches({
      { target = auto_play_port, key = "pick_target_player", value = function() picked = true; return other end },
      { target = effects, key = "apply_target", value = function() return { ok = true } end },
      { target = inventory, key = "consume", value = function() consumed = true; return true end },
      { target = action_anim_port, key = "queue", value = function() return true end },
      { target = settlement, key = "execute", value = function(_, _, _, _, opts)
          settlement_opts = opts
          consumed = true
          return { ok = true }
        end },
    }, function()
      res = handlers.handle_target_player_item(g, g.players[1], item_ids.exile, {
        resolve_target_candidates = function() return { other } end,
        is_computer_controlled = true,
      })
    end)
    _assert_eq(picked, true, "the ai branch resolves a target via auto_play")
    _assert_eq(consumed, true, "the ai application consumes the item")
    _assert_eq(res.ok, true, "the ai application reports ok")
    -- #293:opts→nil 时的 fallback_reason 默认值(→and 变异)未测。
    _assert_eq(settlement_opts.fallback_reason, "invalid_target", "nil opts defaults the fallback reason")
  end)

  it("test_a_human_actor_returns_a_waiting_choice_spec_with_the_target_options", function()
    local g = _game()
    local p, other = g.players[1], g.players[2]
    local res = handlers.handle_target_player_item(g, p, item_ids.exile, {
      resolve_target_candidates = function() return { other } end,
    })
    luassert.is.same(true, res.waiting, "a human actor waits on a choice")
    _assert_eq(res.intent.kind, "need_choice", "the intent requests a choice")
    local spec = res.intent.choice_spec
    _assert_eq(spec.kind, "item_target_player", "the choice spec is an item_target_player choice")
    _assert_eq(spec.route_key, "player", "the route key dispatches to the player picker")
    _assert_eq(spec.pre_confirm_on_select, false, "selection does not pre-confirm")
    _assert_eq(spec.owner_role_id, p.id, "the choice is owned by the acting player")
    _assert_eq(spec.title, inventory.item_name(item_ids.exile) .. "：选择目标玩家", "the title names the item")
    _assert_eq(spec.allow_cancel, true, "the choice is cancelable")
    _assert_eq(spec.cancel_label, "取消", "the cancel label is pinned")
    _assert_eq(spec.meta.item_id, item_ids.exile, "the meta carries the item id")
    _assert_eq(spec.meta.player_id, p.id, "the meta carries the acting player id")
    _assert_eq(spec.options[1].id, other.id, "the candidate is offered as an option")
    _assert_eq(spec.options[1].label, other.name, "the option is labeled with the candidate name")
    luassert.is.same(1, #spec.body_lines, "one body line per candidate")
  end)

-- --------------------------------------------------------------------------
-- item handlers — handle_remote_dice
-- --------------------------------------------------------------------------
end)


describe("TestItemHandlersRemoteDice", function()
  before_each(function()
    config_reset.reset_all()
  end)
  it("test_ai_publishes_a_remote_dice_feed_entry_when_a_target_tile_is_chosen", function()
    local g = _game()
    local published = _run_ai(g, 4, { name = "财神庙" }, { ok = true })
    _assert_eq(#published, 1, "a successful targeted ai dice publishes one feed entry")
    _assert_eq(published[1].kind, event_kinds.remote_dice_target,
      "the target-tile entry uses the log-only kind so it never pops a second tip (#109)")
    luassert.truthy(published[1].text:find("财神庙", 1, true), "the feed text names the target tile")
  end)

  it("test_ai_publishes_nothing_when_no_target_tile_is_chosen", function()
    local g = _game()
    local published = _run_ai(g, 4, nil, { ok = true })
    _assert_eq(#published, 0, "without a target tile there is no feed entry")
  end)

  it("test_ai_publishes_nothing_when_the_dice_application_fails", function()
    local g = _game()
    local published = _run_ai(g, 4, { name = "财神庙" }, { ok = false })
    _assert_eq(#published, 0, "a failed dice application suppresses the feed entry")
  end)

  it("test_a_human_actor_returns_the_remote_dice_value_choice_spec", function()
    local g = _game()
    local res = handlers.handle_remote_dice(g, g.players[1], item_ids.remote_dice, {})
    local spec = res.intent.choice_spec
    _assert_eq(spec.kind, "remote_dice_value", "the choice spec is a remote_dice_value choice")
    _assert_eq(spec.route_key, "remote", "the route key dispatches to the remote picker")
    _assert_eq(spec.title, "遥控骰子：选择点数", "the title is pinned")
    _assert_eq(spec.cancel_label, "放弃", "the cancel label is pinned")
    _assert_eq(#spec.options, 6, "all six dice faces are offered")
  end)

  it("test_candidates_start_at_one_and_are_stringified_as_labels", function()
    -- #293:candidates 首项 1→0 变异、options label tostring→nil 变异未测。
    local g = _game()
    local res = handlers.handle_remote_dice(g, g.players[1], item_ids.remote_dice, {})
    local spec = res.intent.choice_spec
    _assert_eq(spec.options[1].id, 1, "the first dice face is 1")
    _assert_eq(spec.options[6].id, 6, "the last dice face is 6")
    _assert_eq(spec.options[1].label, "1", "option labels are stringified values")
    _assert_eq(spec.options[6].label, "6", "all labels carry their stringified value")
  end)

  it("test_remote_dice_ai_path_consumes_before_apply", function()
    -- #293:settlement execute 的 consume "before_apply"(→nil 变异)未测。
    local g = _game()
    local captured_opts
    _with_patches({
      { target = auto_play_port, key = "pick_remote_dice_value", value = function() return 4, nil end },
      { target = inventory, key = "consume", value = function() return true end },
      { target = remote_dice, key = "apply", value = function() return { ok = true } end },
      { target = settlement, key = "execute", value = function(_, _, _, _, opts)
          captured_opts = opts
          return { ok = true }
        end },
    }, function()
      handlers.handle_remote_dice(g, g.players[1], item_ids.remote_dice, { is_computer_controlled = true })
    end)
    _assert_eq(captured_opts.consume, "before_apply", "remote_dice ai path consumes before applying")
  end)

-- --------------------------------------------------------------------------
-- item handlers — handle_roadblock
-- --------------------------------------------------------------------------
end)


describe("TestItemHandlersRoadblock", function()
  before_each(function()
    config_reset.reset_all()
  end)
  it("test_an_ai_actor_sources_auto_candidates_within_radius_3_and_applies_the_best", function()
    local g = _game()
    local auto_radius, manual_called, applied_idx
    _with_patches({
      { target = roadblock, key = "auto_candidates", value = function(_, _, radius)
          auto_radius = radius
          return { { idx = 5, label = "L5" } }
        end },
      { target = roadblock, key = "manual_candidates", value = function() manual_called = true; return {} end },
      { target = roadblock, key = "pick_best", value = function() return { idx = 5 } end },
      { target = inventory, key = "consume", value = function() return true end },
      { target = roadblock, key = "apply", value = function(_, _, idx) applied_idx = idx; return { ok = true } end },
    }, function()
      handlers.handle_roadblock(g, g.players[1], item_ids.roadblock, { is_computer_controlled = true })
    end)
    _assert_eq(auto_radius, 3, "ai roadblock placement scans a radius of 3")
    _assert_eq(manual_called, nil, "the ai branch does not use manual candidates")
    _assert_eq(applied_idx, 5, "the best candidate index is applied")
  end)

  it("test_a_human_actor_sources_manual_candidates_within_radius_3_and_returns_a_choice_spec", function()
    local g = _game()
    local manual_radius
    local res
    _with_patches({
      { target = roadblock, key = "manual_candidates", value = function(_, _, radius)
          manual_radius = radius
          return { { idx = 5, label = "L5" } }
        end },
    }, function()
      res = handlers.handle_roadblock(g, g.players[1], item_ids.roadblock, {})
    end)
    _assert_eq(manual_radius, 3, "human roadblock placement scans a radius of 3")
    local spec = res.intent.choice_spec
    _assert_eq(spec.kind, "roadblock_target", "the choice spec is a roadblock_target choice")
    _assert_eq(spec.route_key, "target", "the route key dispatches to the target picker")
    _assert_eq(spec.title, "路障卡：选择位置", "the title is pinned")
    _assert_eq(spec.cancel_label, "放弃", "the cancel label is pinned")
  end)

  it("test_no_placeable_position_short_circuits_to_false", function()
    local g = _game()
    local res
    _with_patches({
      { target = roadblock, key = "auto_candidates", value = function() return {} end },
    }, function()
      res = handlers.handle_roadblock(g, g.players[1], item_ids.roadblock, { is_computer_controlled = true })
    end)
    _assert_eq(res, false, "no roadblock candidates yields false")
  end)

  it("test_roadblock_ai_path_consumes_before_apply", function()
    -- #293:roadblock settlement execute 的 consume "before_apply"(→nil 变异)未测。
    local g = _game()
    local captured_opts
    _with_patches({
      { target = roadblock, key = "auto_candidates", value = function() return { { idx = 5, label = "L5" } } end },
      { target = roadblock, key = "pick_best", value = function() return { idx = 5 } end },
      { target = inventory, key = "consume", value = function() return true end },
      { target = roadblock, key = "apply", value = function() return { ok = true } end },
      { target = settlement, key = "execute", value = function(_, _, _, _, opts)
          captured_opts = opts
          return { ok = true }
        end },
    }, function()
      handlers.handle_roadblock(g, g.players[1], item_ids.roadblock, { is_computer_controlled = true })
    end)
    _assert_eq(captured_opts.consume, "before_apply", "roadblock ai path consumes before applying")
  end)

-- --------------------------------------------------------------------------
-- item handlers — handle_demolish cfg dispatch
-- --------------------------------------------------------------------------
end)


describe("TestItemHandlersDemolishCfgDispatch", function()
  before_each(function()
    config_reset.reset_all()
  end)
  it("test_the_monster_card_demolishes_within_range_3_without_injuring", function()
    local g = _game()
    local cap = _capture_use(g, item_ids.monster, { is_computer_controlled = true })
    _assert_eq(cap.idx, 3, "demolish scans a range of 3")
    _assert_eq(cap.opts.item_id, item_ids.monster, "the item id flows through")
    _assert_eq(cap.opts.injure, false, "the monster card does not injure")
    _assert_eq(cap.opts.title, "怪兽卡", "the monster card title is pinned")
    _assert_eq(cap.opts.is_computer_controlled, true, "the ai flag flows through")
  end)

  it("test_the_missile_card_injures_and_carries_its_own_title", function()
    local g = _game()
    local cap = _capture_use(g, item_ids.missile, {})
    _assert_eq(cap.opts.injure, true, "the missile card injures")
    _assert_eq(cap.opts.title, "导弹卡", "the missile card title is pinned")
    _assert_eq(cap.opts.is_computer_controlled, nil, "an absent ai flag stays nil")
  end)

  it("test_an_unknown_demolish_item_id_is_rejected", function()
    local g = _game()
    local ok = pcall(function()
      handlers.handle_demolish(g, g.players[1], item_ids.share_wealth, {})
    end)
    _assert_eq(ok, false, "a non-demolish item has no cfg and asserts")
  end)

-- --------------------------------------------------------------------------
-- item handlers — handle_target_player_item guard closure (#259)
-- --------------------------------------------------------------------------
end)

describe("TestItemHandlersGuardClosure", function()
  it("test_rejects_a_context_without_resolve_target_candidates", function()
    -- kills handle_target_player_item's "missing resolve_target_candidates" -> nil.
    local g = _game()
    luassert.has_error(function()
      handlers.handle_target_player_item(g, g.players[1], item_ids.exile, {})
    end, "missing resolve_target_candidates")
  end)
end)
