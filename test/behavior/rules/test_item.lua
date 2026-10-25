require("test.bootstrap").install_package_paths()
-- luacheck: ignore 143 (busted injects the verified luassert object)
local luassert = assert
-- luacheck: ignore 211
local support = require("test.support.shared_support")
local control = require("src.player.control")
local default_map = require("src.config.content.default_map")
local function _new_game()
  return support.new_game({ map = default_map })
end
local _open_choice = support.open_choice
local _get_choice = support.get_choice
local _tile_state = support.tile_state
local function _assert_eq(a, b, msg) luassert.is.equal(b, a, msg) end
local executor = require("src.rules.items.executor")
local choice_resolver = require("src.rules.choice.resolver")
local inventory = require("src.rules.items.inventory")
local item_ids = require("src.config.gameplay.item_ids")
local timing = require("src.config.gameplay.timing")
local land_choice_specs = require("src.rules.land.choice_specs")
local item_phase = require("src.rules.items.phase")
local item_strategy = require("src.rules.items.strategy")
local steal = require("src.rules.items.steal")
local cash_handlers = require("src.rules.chance.handlers")._cash
local monopoly_event = require("src.foundation.events")
local move_followup = require("src.turn.phases.move_followup")
local demolish = require("src.rules.items.demolish")
local target_cash_effects = require("src.rules.items.target_cash_effects")

local function _find_option_id_by_label(choice, label)
  for _, option in ipairs(choice and choice.options or {}) do
    if option.label == label then
      return option.id
    end
  end
  return nil
end

local function _install_narrow_ports(game, ui_port)
  game.ui_port = ui_port
  game.anim_gate_port = {
    wait_move_anim = ui_port and ui_port.wait_move_anim == true,
    wait_action_anim = ui_port and ui_port.wait_action_anim == true,
  }
  game.popup_port = {
    push_popup = function(_, payload, popup_opts)
      if ui_port and type(ui_port.push_popup) == "function" then
        return ui_port:push_popup(payload, popup_opts)
      end
      return false
    end,
  }
  game.tile_feedback_port = {
    on_tile_upgraded = function(_, tile_id, level)
      if ui_port and type(ui_port.on_tile_upgraded) == "function" then
        return ui_port:on_tile_upgraded(tile_id, level) == true
      end
      return false
    end,
  }
end

local function _set_ui_port(game, overrides)
  _install_narrow_ports(game, support.build_ui_port(overrides))
end

local function _setup_world_with_anim()
  local g = _new_game()
  _set_ui_port(g, { wait_action_anim = true })
  return g
end

local _config_reset = require("test.support.config_reset")



describe("TestItem", function()
  before_each(function()
    _config_reset.reset_all()
  end)
  it("test_monster_card", function()
    local g = _setup_world_with_anim()
    local p = g:current_player()
    local idx = 3
    local tile_ref = g.board:get_tile(idx)
    g:set_tile_owner(tile_ref, 2)
    g:set_tile_level(tile_ref, 2)
    p.inventory:add({ id = 2008 })
    local res = executor.use_item(g, p, 2008, {})
    -- 巨兽卡必定返回选择意图;先无条件钉住前提,再走选择流程(vacuous-branch)。
    luassert.truthy(type(res) == "table" and res.intent ~= nil, "monster should return a choice intent")
    if res.intent.kind == "need_choice" then
      _open_choice(g, res.intent.choice_spec)
    end
    local pending = _get_choice(g)
    luassert.truthy(pending and pending.kind == "demolish_target", "monster should open choice")
    res = choice_resolver.resolve(g, pending, { option_id = pending.options[1].id })
    _assert_eq(res.status, "resolved", "monster choice should resolve")
    _assert_eq(_tile_state(g, tile_ref).level, 0, "building destroyed")
    luassert.truthy(g.turn.action_anim and g.turn.action_anim.kind == "monster", "monster should queue monster action anim")
    _assert_eq(res.after_action_anim, nil, "monster should not expose move followup")
  end)

  it("test_missile_card", function()
    local g = _setup_world_with_anim()
    local p = g:current_player()
    local idx = 4
    local tile_ref = g.board:get_tile(idx)
    g:set_tile_owner(tile_ref, 2)
    g:set_tile_level(tile_ref, 1)
    g:update_player_position(g.players[2], idx)
    g.board:place_roadblock(idx)
    g.board:place_mine(idx)
    p.inventory:add({ id = 2013 })
    local res = executor.use_item(g, p, 2013, {})
    -- 导弹卡必定返回选择意图;先无条件钉住前提,再走选择流程(vacuous-branch)。
    luassert.truthy(type(res) == "table" and res.intent ~= nil, "missile should return a choice intent")
    if res.intent.kind == "need_choice" then
      _open_choice(g, res.intent.choice_spec)
    end
    local pending = _get_choice(g)
    luassert.truthy(pending and pending.kind == "item_target_player", "missile should open player target choice")
    res = choice_resolver.resolve(g, pending, { option_id = g.players[2].id })
    _assert_eq(res.status, "resolved", "missile choice should resolve")
    _assert_eq(_tile_state(g, tile_ref).level, 0, "building destroyed by missile")
    _assert_eq(g.board:has_roadblock(idx), false, "roadblock cleared")
    _assert_eq(g.board:has_mine(idx), false, "mine cleared")
    luassert.truthy(g.turn.action_anim and g.turn.action_anim.kind == "missile", "missile should queue missile action anim")
    _assert_eq(#(g.turn.action_anim_queue or {}), 0, "missile should not queue a second target-player anim")
    luassert.truthy(type(res.after_action_anim) == "table", "missile should expose move followup")
    _assert_eq(
      res.after_action_anim.next_args.log_entries[1],
      p.name .. " 发射导弹轰炸 " .. tile_ref.name .. "，建筑被摧毁，1 名玩家送医",
      "missile should defer main strike log until move followup"
    )
    _assert_eq(g:detention_remaining(g.players[2]), 0, "missile should defer hospital stay until move followup")

    local next_state, _ = move_followup.run({ game = g }, res.after_action_anim.next_args)
    _assert_eq(next_state, nil, "missile move followup should return caller continuation")
    luassert.truthy(g:detention_remaining(g.players[2]) > 0, "missile target should enter hospital after move followup")
  end)

  it("test_missile_apply_can_destroy_own_land_and_relocate_occupant", function()
    local g = _setup_world_with_anim()
    local p = g:current_player()
    local idx = 4
    local tile_ref = g.board:get_tile(idx)
    local occupant = g.players[2]

    g:set_tile_owner(tile_ref, p.id)
    g:set_player_property(p, tile_ref.id, true)
    g:set_tile_level(tile_ref, 2)
    g:update_player_position(occupant, idx)

    local res = demolish.apply(g, p, idx, {
      item_id = item_ids.missile,
      injure = true,
      title = "导弹卡",
    })

    _assert_eq(res.ok, true, "direct missile apply should succeed")
    _assert_eq(_tile_state(g, tile_ref).level, 0, "missile should destroy own land building")
    _assert_eq(occupant.position, g.board:find_first_by_type("hospital"), "occupant should relocate to hospital")
  end)

  it("test_demolish_card_no_target_rejects_and_retains_card", function()
    local g = _new_game()
    local p = g:current_player()
    p.inventory:add({ id = 2008 })

    local res = executor.use_item(g, p, 2008, { is_computer_controlled = false })
    _assert_eq(type(res), "table", "demolish without target should return a structured rejection")
    _assert_eq(res.ok, false, "demolish without target should reject instead of crashing")
    _assert_eq(res.status, "rejected", "demolish without target should carry rejected status")
    _assert_eq(p.inventory:count(), 1, "demolish without target should retain the card")
  end)

  it("test_item_phase_filters_unusable_target_items", function()
    local g = _new_game()
    local p = g:current_player()
    p.inventory:add({ id = 2008 }) -- 怪兽卡（无可拆目标）
    p.inventory:add({ id = 2011 }) -- 均富卡（目标玩家已出局）
    g.players[2].eliminated = true

    local spec = item_phase.build_passive_choice_spec(g, p, "post_action")
    _assert_eq(spec, nil, "item_phase should not expose unusable target items")
  end)

  it("test_item_phase_keeps_demolish_when_target_exists", function()
    local g = _new_game()
    local p = g:current_player()
    local idx = 3
    local tile_ref = g.board:get_tile(idx)
    g:set_tile_owner(tile_ref, 2)
    g:set_tile_level(tile_ref, 1)
    p.inventory:add({ id = 2008 })

    local spec = item_phase.build_passive_choice_spec(g, p, "post_action")
    luassert.truthy(spec and spec.options and #spec.options > 0, "item_phase should include demolish when target exists")
    _assert_eq(spec.options[1].id, 2008, "demolish item should be selectable when target exists")
  end)

  it("test_item_phase_hides_rent_cards_on_owned_land", function()
    local g = _new_game()
    local p = g:current_player()
    local idx = 3
    local tile_ref = g.board:get_tile(idx)
    g:update_player_position(p, idx)
    g:set_tile_owner(tile_ref, p.id)
    g:set_player_property(p, tile_ref.id, true)
    p.inventory:add({ id = item_ids.strong })
    p.inventory:add({ id = item_ids.free_rent })

    local spec = item_phase.build_passive_choice_spec(g, p, "post_action")
    _assert_eq(spec, nil, "owned land should not expose reactive cards in active windows")
  end)

  it("test_item_phase_hides_rent_cards_on_other_owned_land", function()
    local g = _new_game()
    local p = g:current_player()
    local idx = 3
    local tile_ref = g.board:get_tile(idx)
    g:update_player_position(p, idx)
    g:set_tile_owner(tile_ref, g.players[2].id)
    p.inventory:add({ id = item_ids.strong })
    p.inventory:add({ id = item_ids.free_rent })

    local spec = item_phase.build_passive_choice_spec(g, p, "post_action")
    _assert_eq(spec, nil, "other player land should still hide reactive cards in active windows")
  end)

  it("test_passive_spec_mixed_slots", function()
    local g = _new_game()
    local p = g:current_player()
    p.inventory:clear()
    local idx = 3
    local tile_ref = g.board:get_tile(idx)
    g:update_player_position(p, idx)
    g:set_tile_owner(tile_ref, g.players[2].id)
    g:set_player_deity(p, "poor", 3)
    p.inventory:add({ id = item_ids.send_poor })
    p.inventory:add({ id = item_ids.remote_dice })
    p.inventory:add({ id = item_ids.mine })

    local spec = item_phase.build_passive_choice_spec(g, p, "post_action", {
      next_state = "roll",
      next_args = { player = p },
    })
    luassert.truthy(spec ~= nil, "passive spec should exist with mixed available items")
    _assert_eq(spec.kind, "item_phase_passive", "passive spec kind mismatch")
    _assert_eq(spec.route_key, "item_phase_passive", "passive spec route key mismatch")
    luassert.truthy(type(spec.slot_states) == "table", "passive spec should expose slot_states")
    luassert.truthy(type(spec.options) == "table", "passive spec should expose options")

    local slot1 = spec.slot_states[1]
    local slot2 = spec.slot_states[2]
    local slot3 = spec.slot_states[3]
    luassert.truthy(type(slot1) == "table" and type(slot2) == "table" and type(slot3) == "table", "first three slot states should be present")
    _assert_eq(slot1.available, true, "send_poor should be available in post_action")
    _assert_eq(slot1.alert, true, "send_poor should mark alert bubble when available")
    _assert_eq(slot1.alert_text, "送神卡可用！", "send_poor alert text mismatch")
    _assert_eq(slot2.available, true, "mine should be available in post_action")
    _assert_eq(slot2.alert, false, "passive available slot should not alert")
    _assert_eq(slot2.alert_text, nil, "passive available slot should not expose alert text")
    _assert_eq(slot3.available, false, "remote_dice should be unavailable in post_action")
    _assert_eq(slot3.alert, false, "unavailable slot should not alert")
    _assert_eq(slot3.alert_text, nil, "unavailable slot should not expose alert text")
  end)

  it("test_passive_spec_auto_skip_empty_inventory", function()
    local g = _new_game()
    local p = g:current_player()
    p.inventory:clear()
    local spec = item_phase.build_passive_choice_spec(g, p, "pre_action", {
      next_state = "roll",
      next_args = { player = p },
    })
    _assert_eq(spec, nil, "empty inventory should auto skip passive spec")
  end)

  it("test_passive_spec_has_options_for_validator", function()
    local g = _new_game()
    local p = g:current_player()
    p.inventory:clear()
    p.inventory:add({ id = item_ids.remote_dice })
    local spec = item_phase.build_passive_choice_spec(g, p, "pre_action", {
      next_state = "roll",
      next_args = { player = p },
    })
    luassert.truthy(spec ~= nil, "passive spec should exist when item is available")
    luassert.truthy(type(spec.options) == "table" and #spec.options > 0, "passive spec options should be non-empty")
    for _, option in ipairs(spec.options) do
      luassert.truthy(option.id ~= nil, "validator option should include id")
      luassert.truthy(type(option.label) == "string" and option.label ~= "", "validator option should include label")
    end
  end)

  it("test_passive_handler_direct_execute", function()
    local g = _new_game()
    local p = g:current_player()
    p.inventory:clear()
    p.inventory:add({ id = item_ids.mine })

    local pending = _open_choice(g, luassert.truthy(item_phase.build_passive_choice_spec(g, p, "pre_action", {
      next_state = "roll",
      next_args = { player = p },
    }), "passive pre_action choice should open"))
    local res = choice_resolver.resolve(g, pending, {
      type = "choice_select",
      choice_id = pending.id,
      option_id = item_ids.mine,
      actor_role_id = p.id,
    })

    _assert_eq(res and res.stay, false, "direct execute should finish passive phase when no more options")
    _assert_eq(inventory.count(p), 0, "mine should be consumed after direct passive execute")
  end)

  it("test_passive_handler_cancel_finishes_phase", function()
    local g = _new_game()
    local p = g:current_player()
    p.inventory:clear()
    p.inventory:add({ id = item_ids.mine })

    local pending = _open_choice(g, luassert.truthy(item_phase.build_passive_choice_spec(g, p, "pre_action", {
      next_state = "roll",
      next_args = { player = p },
    }), "passive pre_action choice should open"))

    local res = choice_resolver.resolve(g, pending, {
      type = "choice_cancel",
      choice_id = pending.id,
      actor_role_id = p.id,
    })

    _assert_eq(res and res.stay, false, "cancel should finish passive phase")
    luassert.truthy(g.turn.item_phase and g.turn.item_phase.pre_action and g.turn.item_phase.pre_action.done == true, "cancel should mark phase finished")
    _assert_eq(g.turn.item_phase_active, "", "cancel should clear active item phase")
  end)

  it("test_passive_handler_marks_effect_group_after_use", function()
    local g = _new_game()
    local p = g:current_player()
    p.inventory:clear()
    p.inventory:add({ id = item_ids.dice_multiplier })

    local pending = _open_choice(g, luassert.truthy(item_phase.build_passive_choice_spec(g, p, "pre_move", {
      next_state = "roll",
      next_args = { player = p },
    }), "passive pre_move choice should open"))
    local res = choice_resolver.resolve(g, pending, {
      type = "choice_select",
      choice_id = pending.id,
      option_id = item_ids.dice_multiplier,
      actor_role_id = p.id,
    })

    _assert_eq(res and res.stay, false, "effect-group item execute should finish passive phase when no options remain")
    luassert.truthy(g.turn.used_effect_groups and g.turn.used_effect_groups.dice_multiply == true, "dice_double execute should mark dice_multiply effect group used")
  end)

  it("test_passive_handler_no_effect_group_on_cancel", function()
    local g = _new_game()
    local p = g:current_player()
    p.inventory:clear()
    p.inventory:add({ id = item_ids.remote_dice })

    local pending = _open_choice(g, luassert.truthy(item_phase.build_passive_choice_spec(g, p, "pre_action", {
      next_state = "roll",
      next_args = { player = p },
    }), "passive pre_action choice should open"))
    local res = choice_resolver.resolve(g, pending, {
      type = "choice_select",
      choice_id = pending.id,
      option_id = item_ids.remote_dice,
      actor_role_id = p.id,
    })

    luassert.truthy(res and res.stay == true, "remote dice passive execute should open follow-up choice")
    _assert_eq(g.turn.used_effect_groups and g.turn.used_effect_groups.dice_control, nil,
      "waiting follow-up should not mark dice_control effect group")
  end)

  it("test_passive_handler_resolve_returns_table_when_reopened", function()
    local g = _new_game()
    local p = g:current_player()
    p.inventory:clear()
    p.inventory:add({ id = item_ids.mine })
    p.inventory:add({ id = item_ids.remote_dice })

    local pending = _open_choice(g, luassert.truthy(item_phase.build_passive_choice_spec(g, p, "pre_action", {
      next_state = "roll",
      next_args = { player = p },
    }), "passive pre_action choice should open"))
    local res = choice_resolver.resolve(g, pending, {
      type = "choice_select",
      choice_id = pending.id,
      option_id = item_ids.mine,
      actor_role_id = p.id,
    })

    luassert.truthy(type(res) == "table", "passive handler resolve should return table when phase reopens")
    _assert_eq(res.stay, true, "passive handler resolve should return stay=true when phase reopens")
  end)

  it("test_passive_followup_completion_marks_effect_group", function()
    local g = _new_game()
    local p = g:current_player()
    p.inventory:clear()
    p.inventory:add({ id = item_ids.remote_dice })

    local pending = _open_choice(g, luassert.truthy(item_phase.build_passive_choice_spec(g, p, "pre_action", {
      next_state = "roll",
      next_args = { player = p },
    }), "passive pre_action choice should open"))
    local select_res = choice_resolver.resolve(g, pending, {
      type = "choice_select",
      choice_id = pending.id,
      option_id = item_ids.remote_dice,
      actor_role_id = p.id,
    })
    luassert.truthy(select_res and select_res.stay == true, "remote dice passive execute should open follow-up choice")
    _assert_eq(g.turn.used_effect_groups and g.turn.used_effect_groups.dice_control, nil,
      "effect group should stay unmarked before follow-up completion")

    local followup = luassert.truthy(g.turn.pending_choice, "remote dice should open follow-up choice")
    _assert_eq(followup.kind, "remote_dice_value", "remote dice follow-up kind mismatch")
    local option = luassert.truthy(followup.options and followup.options[1], "remote dice follow-up should expose options")
    local followup_res = choice_resolver.resolve(g, followup, {
      type = "choice_select",
      choice_id = followup.id,
      option_id = option.id,
      actor_role_id = p.id,
    })

    luassert.truthy(type(followup_res) == "table", "remote dice follow-up completion should return table")
    luassert.truthy(g.turn.used_effect_groups and g.turn.used_effect_groups.dice_control == true, "passive-origin follow-up completion should mark dice_control effect group")
  end)

  it("test_build_wait_choice_args_requires_resume_next_state", function()
    local ok, err = pcall(function()
      item_phase.build_wait_choice_args(nil)
    end)
    _assert_eq(ok, false, "build_wait_choice_args should assert when meta is missing")
    luassert.truthy(type(err) == "string" and string.find(err, "missing meta%.resume_next_state", 1, false), "build_wait_choice_args should explain missing resume_next_state")
  end)

  it("test_build_wait_choice_args_allows_nil_resume_next_args", function()
    local result = item_phase.build_wait_choice_args({
      resume_next_state = "landing",
      resume_next_args = nil,
    })
    _assert_eq(result.next_state, "landing", "build_wait_choice_args should forward resume_next_state")
    _assert_eq(result.next_args, nil, "build_wait_choice_args should preserve nil resume_next_args")
  end)

  it("test_build_wait_choice_args_restores_next_state_and_args", function()
    local resume_next_args = { tile_id = 12, skip_anim = true }
    local result = item_phase.build_wait_choice_args({
      resume_next_state = "move_followup",
      resume_next_args = resume_next_args,
    })
    _assert_eq(result.next_state, "move_followup", "build_wait_choice_args should restore resume_next_state")
    luassert.truthy(result.next_args == resume_next_args, "build_wait_choice_args should forward the original next_args table")
  end)

  it("test_wait_choice_arg_helpers_split_state_and_args", function()
    local resume_next_args = { tile_id = 12, skip_anim = true }
    local result = item_phase.build_wait_choice_args({
      resume_next_state = "move_followup",
      resume_next_args = resume_next_args,
    })

    _assert_eq(result.next_state, "move_followup", "build_wait_choice_args should forward resume_next_state")
    luassert.truthy(result.next_args == resume_next_args, "build_wait_choice_args should forward the original next_args table")
  end)

  it("test_item_equalize_cash", function()
    local g = _new_game()
    local user = g.players[1]
    local target = g.players[2]
    g:set_player_cash(user, 1000)
    g:set_player_cash(target, 9000)
    user.inventory:add({ id = 2011 })
    local res = executor.use_item(g, user, 2011, { is_computer_controlled = true })
    -- lint-allow: vacuous-branch 托管均富卡可能直接结算或返回选择意图,两种返回形态均合法;末尾现金断言无条件覆盖两条路径
    if type(res) == "table" and res.intent then
      if res.intent.kind == "need_choice" then
        _open_choice(g, res.intent.choice_spec)
      end
      local pending = _get_choice(g)
      luassert.truthy(pending and pending.kind == "item_target_player", "equalize should open choice")
      local first = pending.options[1]
      choice_resolver.resolve(g, pending, { option_id = first.id })
      res = true
    end
    local ok = (type(res) == "table" and type(res.ok) ~= "nil") and res.ok or res
    _assert_eq(ok, true, "equalize use ok")
    _assert_eq(g:player_cash(user), 5000, "equalize user cash")
    _assert_eq(g:player_cash(target), 5000, "equalize target cash")
  end)

  it("test_target_item_manual_direct_exec_and_duration", function()
    local g = _setup_world_with_anim()
    local user = g.players[1]
    local target = g.players[2]
    g:set_player_cash(user, 1000)
    g:set_player_cash(target, 9000)
    user.inventory:add({ id = 2011 })

    local res = executor.use_item(g, user, 2011, {})
    luassert.truthy(type(res) == "table" and res.waiting, "target item should open choice first")
    _open_choice(g, res.intent.choice_spec)
    local pending = _get_choice(g)
    luassert.truthy(pending and pending.kind == "item_target_player", "pending choice kind")

    choice_resolver.resolve(g, pending, { option_id = target.id })
    _assert_eq(_get_choice(g), nil, "choice should be resolved directly without reopening")
    _assert_eq(g:player_cash(user), 5000, "manual target item should apply to user")
    _assert_eq(g:player_cash(target), 5000, "manual target item should apply to target")
    luassert.truthy(g.turn.action_anim and g.turn.action_anim.kind == "item_target_player", "target item should queue anim")
    _assert_eq(
      g.turn.action_anim.duration,
      timing.action_anim_default_seconds or 1.0,
      "target item anim should use default duration"
    )
  end)

  it("test_steal_manual_uses_item_target_player_and_random_stolen_item", function()
    local g = _setup_world_with_anim()
    local user = g.players[1]
    local target = g.players[2]
    user.inventory:add({ id = item_ids.steal })
    target.inventory:add({ id = item_ids.tax_free })
    target.inventory:add({ id = item_ids.roadblock })

    local res = executor.use_item(g, user, item_ids.steal, {})
    luassert.truthy(type(res) == "table" and res.waiting, "steal should open choice first")
    local pending = res.intent.choice_spec
    luassert.truthy(pending and pending.kind == "item_target_player", "steal should use shared player target choice")
    _assert_eq(#pending.options, 1, "only players with items should be selectable")
    _assert_eq(pending.options[1].id, target.id, "target with items should be selectable")

    res = choice_resolver.resolve(g, _open_choice(g, pending), { option_id = target.id })
    _assert_eq(res.status, "resolved", "steal target choice should resolve")
    _assert_eq(user.inventory:count(), 1, "stealer should spend steal card and receive one item")
    _assert_eq(target.inventory:count(), 1, "target should lose one random item")
    luassert.truthy(g.turn.action_anim and g.turn.action_anim.kind == "item_target_player", "steal should queue target player anim")
    _assert_eq(#(g.turn.action_anim_queue or {}), 1, "steal should queue gained item reveal after target-player anim")
    _assert_eq(g.turn.action_anim_queue[1].kind, "item_gain_popup", "steal reveal kind mismatch")
    _assert_eq(g.turn.action_anim_queue[1].player_id, user.id, "steal reveal player mismatch")
  end)

  it("test_steal_target_candidates_exclude_empty_and_angel_players", function()
    local g = support.new_game({
      map = default_map,
      players = { "P1", "P2", "P3", "P4" },
      ai = { [2] = true, [3] = true, [4] = true },
    })
    local user = g.players[1]
    local empty = g.players[2]
    local protected = g.players[3]
    local valid = g.players[4]
    user.inventory:add({ id = item_ids.steal })
    protected.inventory:add({ id = item_ids.tax_free })
    valid.inventory:add({ id = item_ids.roadblock })
    g:set_player_deity(protected, "angel", 3)

    local candidates = g.registries.items:target_candidates(g, user, item_ids.steal)
    _assert_eq(#candidates, 1, "only valid steal target should remain")
    _assert_eq(candidates[1].id, valid.id, "candidate should be player with items and no angel")
    luassert.truthy(empty.inventory:count() == 0, "empty target setup should be empty")
  end)

  it("test_missile_target_candidates_exclude_angel_players", function()
    local g = support.new_game({
      map = default_map,
      players = { "P1", "P2", "P3", "P4" },
      ai = { [2] = true, [3] = true, [4] = true },
    })
    local user = g.players[1]
    local protected = g.players[2]
    local valid = g.players[3]
    user.inventory:add({ id = item_ids.missile })
    g:set_player_deity(protected, "angel", 3)

    local candidates = g.registries.items:target_candidates(g, user, item_ids.missile)
    _assert_eq(#candidates, 2, "missile should target unprotected other players")
    for _, candidate in ipairs(candidates) do
      luassert.truthy(candidate.id ~= user.id, "self should not be a missile target")
      luassert.truthy(candidate.id ~= protected.id, "angel player should not be a missile target")
    end
    luassert.truthy(valid ~= nil, "valid player setup should exist")
  end)

  it("test_item_target_player_choice_assigns_seat_aligned_slot_layout", function()
    local g = support.new_game({
      map = default_map,
      players = { "P1", "P2", "P3", "P4" },
      ai = { [2] = true, [3] = true, [4] = true },
    })
    -- 4 seats, current player is p1; equalize candidates exclude self → 3 candidates
    -- in seat order [p2, p3, p4], so slot_layout must be {2, 3, 4}.
    local user = g.players[1]
    g:set_player_cash(user, 1000)
    g:set_player_cash(g.players[2], 9000)
    g:set_player_cash(g.players[3], 9000)
    g:set_player_cash(g.players[4], 9000)
    user.inventory:add({ id = 2011 })

    local res = executor.use_item(g, user, 2011, {})
    luassert.truthy(type(res) == "table" and res.waiting, "equalize on p1 should open choice")
    local pending = res.intent.choice_spec
    luassert.truthy(pending and pending.kind == "item_target_player", "should be item_target_player choice")
    luassert.truthy(pending.target_slot_layout ~= nil, "item_target_player must include target_slot_layout")
    _assert_eq(#pending.options, 3, "p1 should see 3 candidate players")
    _assert_eq(pending.target_slot_layout[1], 2, "candidate 1 (p2) → slot 2")
    _assert_eq(pending.target_slot_layout[2], 3, "candidate 2 (p3) → slot 3")
    _assert_eq(pending.target_slot_layout[3], 4, "candidate 3 (p4) → slot 4")

    -- Seat-aware: when p2 is current, layout for [p1,p3,p4] is {1,3,4}.
    local g2 = support.new_game({
      map = default_map,
      players = { "P1", "P2", "P3", "P4" },
      ai = { [1] = true, [3] = true, [4] = true },
    })
    g2.turn.current_player_index = 2
    local user2 = g2.players[2]
    g2:set_player_cash(user2, 1000)
    g2:set_player_cash(g2.players[1], 9000)
    g2:set_player_cash(g2.players[3], 9000)
    g2:set_player_cash(g2.players[4], 9000)
    user2.inventory:add({ id = 2011 })
    local res2 = executor.use_item(g2, user2, 2011, {})
    luassert.truthy(type(res2) == "table" and res2.waiting, "equalize on p2 should open choice")
    local pending2 = res2.intent.choice_spec
    _assert_eq(pending2.target_slot_layout[1], 1, "p1 → slot 1")
    _assert_eq(pending2.target_slot_layout[2], 3, "p3 → slot 3")
    _assert_eq(pending2.target_slot_layout[3], 4, "p4 → slot 4")
  end)

  it("test_exile_item_defers_mountain_effect_until_move_followup", function()
    local g = _setup_world_with_anim()
    local user = g.players[1]
    local target = g.players[2]
    user.inventory:add({ id = item_ids.exile })

    local res = executor.use_item(g, user, item_ids.exile, {
      is_computer_controlled = true,
      target_id = target.id,
    })

    _assert_eq(type(res), "table", "exile should return result payload")
    _assert_eq(res.ok, true, "exile should succeed")
    luassert.truthy(type(res.after_action_anim) == "table", "exile should expose move followup continuation")
    _assert_eq(g:detention_remaining(target), 0, "exile should not apply mountain stay immediately")
    luassert.truthy(g.turn.action_anim and g.turn.action_anim.kind == "teleport_effect", "exile should queue teleport effect first")
    _assert_eq(
      res.after_action_anim.next_args.log_entries[1],
      user.name .. " 使用流放卡，将 " .. target.name .. " 送往深山，停留 2 回合",
      "exile should defer main log entry until move followup"
    )

    local next_state, _ = move_followup.run({ game = g }, res.after_action_anim.next_args)
    _assert_eq(next_state, nil, "exile move followup should return to caller continuation")
    luassert.truthy(g:detention_remaining(target) > 0, "exile should apply mountain stay after move followup")
  end)

  it("test_item_executor_fallback_item_use_anim", function()
    local g = _setup_world_with_anim()
    local p = g:current_player()
    p.inventory:add({ id = 2003 })

    local res = executor.use_item(g, p, 2003, { is_computer_controlled = true })
    luassert.truthy(type(res) == "table" and res.action_anim, "fallback item anim should be marked")
    luassert.truthy(g.turn.action_anim and g.turn.action_anim.kind == "item_use", "fallback should queue item_use anim")
    _assert_eq(
      g.turn.action_anim.duration,
      timing.action_anim_default_seconds or 1.0,
      "fallback item anim should use default duration"
    )
  end)

  it("test_item_executor_keeps_specific_anim_without_fallback", function()
    local g = _setup_world_with_anim()
    local p = g:current_player()
    p.inventory:add({ id = 2005 })

    local res = executor.use_item(g, p, 2005, { is_computer_controlled = true })
    luassert.truthy(type(res) == "table" and res.action_anim, "mine should return action anim marker")
    luassert.truthy(g.turn.action_anim and g.turn.action_anim.kind == "mine", "specific mine anim should not be replaced")
    _assert_eq(
      g.turn.action_anim.duration,
      timing.action_anim_default_seconds or 1.0,
      "specific mine anim should use default duration"
    )
  end)

  it("test_item_phase_exposes_mine_in_pre_action", function()
    local g = _new_game()
    local p = g:current_player()
    p.inventory:add({ id = item_ids.mine })

    local spec = luassert.truthy(item_phase.build_passive_choice_spec(g, p, "pre_action"), "mine should be offered in pre_action")
    _assert_eq(spec.uses_item_slots, true, "item_phase choice should expose uses_item_slots flag")
    _assert_eq(spec.pre_confirm_before_slot_pick, false,
      "item_phase choice should expose pre_confirm_before_slot_pick flag")
    local found = nil
    for _, option in ipairs(spec.options) do
      if option.id == item_ids.mine then
        found = option
        break
      end
    end
    luassert.truthy(found ~= nil, "pre_action choice should include mine")
    _assert_eq(found.confirm_title, "地雷卡", "item_phase option should expose the card name as confirm title")
    _assert_eq(found.confirm_body, "使用地雷卡，在你脚下放置地雷，任何玩家经过此地时触发地雷，被强制送进医院住院。",
      "item_phase option should expose the card description as confirm body")
  end)

  it("test_item_phase_exposes_mine_in_post_action", function()
    local g = _new_game()
    local p = g:current_player()
    p.inventory:add({ id = item_ids.mine })

    local spec = luassert.truthy(item_phase.build_passive_choice_spec(g, p, "post_action"), "mine should be offered in post_action")
    local found = nil
    for _, option in ipairs(spec.options) do
      if option.id == item_ids.mine then
        found = option
        break
      end
    end
    luassert.truthy(found ~= nil, "post_action choice should include mine")
    _assert_eq(found.confirm_title, "地雷卡", "post_action option should expose the card name as confirm title")
  end)

  it("test_item_phase_exposes_send_poor_in_pre_and_post_action", function()
    local g = _new_game()
    local p = g:current_player()
    p.inventory:add({ id = item_ids.send_poor })
    g:set_player_deity(p, "poor", 2)

    local pre_action = luassert.truthy(item_phase.build_passive_choice_spec(g, p, "pre_action"), "send_poor should be offered in pre_action")
    local pre_action_found = nil
    for _, option in ipairs(pre_action.options) do
      if option.id == item_ids.send_poor then
        pre_action_found = option
        break
      end
    end
    luassert.truthy(pre_action_found ~= nil, "pre_action choice should include send_poor")
    _assert_eq(pre_action_found.confirm_title, "送神卡", "pre_action option should expose the card name as confirm title")

    local post_action = luassert.truthy(item_phase.build_passive_choice_spec(g, p, "post_action"), "send_poor should be offered in post_action")
    local post_action_found = nil
    for _, option in ipairs(post_action.options) do
      if option.id == item_ids.send_poor then
        post_action_found = option
        break
      end
    end
    luassert.truthy(post_action_found ~= nil, "post_action choice should include send_poor")
    _assert_eq(post_action_found.confirm_title, "送神卡", "post_action option should expose the card name as confirm title")
  end)

  it("test_item_phase_run_loops_auto_repeatable_phase_until_no_action", function()
    local g = _new_game()
    local p = g:current_player()
    local auto_play_port = require("src.rules.ports.auto_play")
    local calls = 0

    support.with_patches({
      {
        target = auto_play_port,
        key = "is_computer_controlled",
        value = function()
          return true
        end,
      },
      {
        target = item_strategy,
        key = "auto_pre_action",
        value = function(_, _, phase)
          calls = calls + 1
          _assert_eq(phase, "pre_action", "auto repeatable phase should pass explicit phase to strategy")
          if calls < 3 then
            return { ok = true }
          end
          return nil
        end,
      },
    }, function()
      local result = item_phase.run({ game = g }, "pre_action", {
        player = p,
        next_state = "roll",
        next_args = { player = p },
      })
      _assert_eq(result, nil, "auto repeatable phase should resolve immediately when no waits/anim are produced")
    end)

    _assert_eq(calls, 3, "auto repeatable phase should keep probing until no further action is returned")
    luassert.truthy(g.turn.item_phase and g.turn.item_phase.pre_action and g.turn.item_phase.pre_action.done == true, "auto repeatable phase should mark done only after the final no-op probe")
  end)

  it("test_item_strategy_hides_reactive_cards_from_active_window", function()
    local g = _new_game()
    local p = g:current_player()
    local idx = 3
    local tile_ref = g.board:get_tile(idx)
    g:update_player_position(p, idx)
    p.inventory:add({ id = item_ids.strong })
    p.inventory:add({ id = item_ids.free_rent })
    p.inventory:add({ id = item_ids.roadblock })

    g:set_tile_owner(tile_ref, p.id)
    g:set_player_property(p, tile_ref.id, true)
    luassert.truthy(item_strategy.can_offer_in_phase(g, p, item_ids.strong, "post_action") == false, "strong card should stay hidden in active windows")
    luassert.truthy(item_strategy.can_offer_in_phase(g, p, item_ids.free_rent, "post_action") == false, "free_rent card should stay hidden in active windows")
    luassert.truthy(item_strategy.can_offer_in_phase(g, p, item_ids.roadblock, "post_action") == true, "roadblock should be offered when UI candidates exist")
  end)

  it("test_item_phase_run_wait_action_anim_patches_move_followup_args", function()
    local g = _new_game()
    local player = g:current_player()
    control.toggle_manual_delegation(player)
    g.turn.action_anim = { seq = 7, kind = "item_use" }
    local original_auto_pre_action = item_strategy.auto_pre_action
    item_strategy.auto_pre_action = function()
      return {
        after_action_anim = {
          next_state = "move_followup",
          next_args = {
            mode = "resume_turn_move",
          },
        },
      }
    end

    local ok, res = pcall(function()
      return item_phase.run({ game = g }, "pre_action", {
        player = player,
        next_state = "roll",
        next_args = { player = player },
      })
    end)
    item_strategy.auto_pre_action = original_auto_pre_action

    luassert.truthy(ok, res)
    luassert.truthy(type(res) == "table" and res.waiting == true, "auto item phase should wait for action anim when item queued anim")
    luassert.truthy(res.wait_action_anim == true, "auto item phase should route through wait_action_anim")
    _assert_eq(res.next_state, "move_followup", "auto item phase should preserve move_followup next state")
    _assert_eq(res.next_args.mode, "resume_turn_move", "move_followup mode should be preserved")
    _assert_eq(res.next_args.next_state, "roll", "move_followup args should receive default next state")
    _assert_eq(res.next_args.next_args.player, player, "move_followup args should receive default next args")
  end)

  it("test_board_advance_tracks_branch_and_wrap", function()
    local board = require("src.rules.board"):new({
      tile_lookup = {
        [1] = { id = 1, name = "A" },
        [2] = { id = 2, name = "B" },
        [3] = { id = 3, name = "C" },
        [4] = { id = 4, name = "D" },
      },
      path = {
        { id = 1, name = "A" },
        { id = 2, name = "B" },
        { id = 3, name = "C" },
        { id = 4, name = "D" },
      },
      branches = {
        [1] = { odd = 3, even = 2 },
      },
      map = {},
      overlays = {
        roadblocks = {},
        mines = {},
      },
    })
    local current = 1
    local branch = board.branches[current]
    luassert.truthy(branch and branch.odd and branch.even, "selected branch entry should expose odd/even targets")

    local odd_index = select(1, board:advance(current, 1, 1))
    local even_index = select(1, board:advance(current, 1, 2))
    _assert_eq(odd_index, branch.odd, "advance should use odd branch when parity is odd")
    _assert_eq(even_index, branch.even, "advance should use even branch when parity is even")

    local last = board:length()
    local wrapped_index, passed_start = board:advance(last, 2)
    _assert_eq(wrapped_index, 2, "advance should wrap around board length")
    _assert_eq(passed_start, 1, "advance should count passing start when wrapping")
  end)

  it("test_collect_from_others_caps_fee_and_rich_bonus", function()
    local handlers = {}
    local events = {}
    local anims = {}
    local common = {
      dependencies = function()
        return {
          monopoly_event = {
            chance = { applied = "chance_applied" },
          },
          number_utils = {
            format_integer_part = function(value)
              return tostring(value)
            end,
          },
        }
      end,
      queue_action_anim = function(_, anim)
        anims[#anims + 1] = anim
      end,
      emit_event = function(_, _, payload)
        events[#events + 1] = payload
      end,
      apply_cash_change = function(game, target_player, delta)
        local before = game:player_cash(target_player)
        local after = before + delta
        if after < 0 then
          after = 0
        end
        game:set_player_cash(target_player, after)
      end,
      adjust_chance_delta = function(game, player, delta)
        if delta > 0 and game:player_has_deity(player, "rich") then
          return delta * 2
        end
        if delta < 0 and game:player_has_deity(player, "poor") then
          return delta * 2
        end
        return delta
      end,
    }
    cash_handlers.register(handlers, common)

    -- #208:用真实 game,破产走真实淘汰实现，不再 stub 破产端口。
    local game = support.new_game({ players = { "P1", "P2", "P3" }, map = default_map })
    game:set_player_cash(game.players[1], 1000)
    game:set_player_cash(game.players[2], 50)
    game:set_player_cash(game.players[3], 300)
    game:set_player_deity(game.players[1], "rich")

    handlers.collect_from_others(game, game.players[1], {
      amount = 100,
      effect = "collect_from_others",
    })

    _assert_eq(game:player_cash(game.players[1]), 1250, "collector should receive each payer's actual liquid only")
    _assert_eq(game:player_cash(game.players[2]), 0, "broke payer cash should be capped at zero")
    _assert_eq(game.players[2].eliminated, true, "broke payer should be marked eliminated")
    _assert_eq(game:player_cash(game.players[3]), 100, "solvent payer should pay full doubled fee")
    _assert_eq(game.players[3].eliminated, false, "solvent payer should not be eliminated")
    _assert_eq(#anims, 1, "cash receive animation should collapse into one summary collection anim")
    _assert_eq(anims[1].amount, 250, "summary receive animation should use the total collected amount")
    _assert_eq(#events, 1, "collect_from_others should emit one summary event")
  end)

  it("test_item_phase_select_remote_dice_keeps_followup_cancelable_in_repeatable_phase", function()
    local g = _new_game()
    local p = g:current_player()
    p.inventory:add({ id = item_ids.remote_dice })

    local spec = luassert.truthy(item_phase.build_passive_choice_spec(g, p, "pre_action", {
      next_state = "roll",
      next_args = { player = p },
    }), "item_phase should open when remote dice exists")
    local pending = _open_choice(g, spec)
    local before_count = inventory.count(p)
    _assert_eq(before_count, 1, "precondition inventory count")

    local res = choice_resolver.resolve(g, pending, {
      type = "choice_select",
      choice_id = pending.id,
      option_id = item_ids.remote_dice,
      actor_role_id = p.id,
    })
    luassert.truthy(res and res.stay == true, "selecting remote dice should open follow-up choice")

    local after_pending = _get_choice(g)
    luassert.truthy(after_pending and after_pending.kind == "remote_dice_value", "follow-up choice kind should be remote_dice_value")
    _assert_eq(inventory.count(p), 1, "repeatable pre_action should defer consume until follow-up confirm")
    _assert_eq(after_pending.allow_cancel, true, "repeatable pre_action follow-up should still allow cancel")
    luassert.truthy(after_pending.meta and after_pending.meta.phase == "pre_action", "follow-up choice should carry repeatable phase context")
    luassert.truthy(after_pending.meta and after_pending.meta.item_preconsumed ~= true, "repeatable phase follow-up should not mark preconsumed")
  end)

  it("test_repeatable_phase_followup_cancel_reopens_item_phase_without_consuming", function()
    local g = _new_game()
    local p = g:current_player()
    p.inventory:add({ id = item_ids.remote_dice })

    local pending = _open_choice(g, luassert.truthy(item_phase.build_passive_choice_spec(g, p, "pre_action", {
      next_state = "roll",
      next_args = { player = p },
    }), "repeatable pre_action choice should open"))
    local select_res = choice_resolver.resolve(g, pending, {
      type = "choice_select",
      choice_id = pending.id,
      option_id = item_ids.remote_dice,
      actor_role_id = p.id,
    })
    luassert.truthy(select_res and select_res.stay == true, "selecting remote dice should enter follow-up choice")

    local followup = _get_choice(g)
    local cancel_res = choice_resolver.resolve(g, followup, {
      type = "choice_cancel",
      choice_id = followup.id,
      actor_role_id = p.id,
    })
    luassert.truthy(cancel_res and cancel_res.stay == true, "canceling repeatable follow-up should keep phase active")

    local reopened = _get_choice(g)
    luassert.truthy(reopened and reopened.kind == "item_phase_passive", "cancel should reopen item phase passive choice")
    _assert_eq(inventory.count(p), 1, "cancel should not consume remote dice")
    luassert.truthy(_find_option_id_by_label(reopened, "遥控骰子卡") ~= nil, "reopened phase should still offer remote dice")
  end)

  it("test_repeatable_phase_followup_confirm_consumes_and_reopens_item_phase", function()
    local g = _new_game()
    local p = g:current_player()
    p.inventory:add({ id = item_ids.remote_dice })
    p.inventory:add({ id = item_ids.mine })

    local pending = _open_choice(g, luassert.truthy(item_phase.build_passive_choice_spec(g, p, "pre_action", {
      next_state = "roll",
      next_args = { player = p },
    }), "repeatable pre_action choice should open"))
    local select_res = choice_resolver.resolve(g, pending, {
      type = "choice_select",
      choice_id = pending.id,
      option_id = item_ids.remote_dice,
      actor_role_id = p.id,
    })
    luassert.truthy(select_res and select_res.stay == true, "selecting remote dice should enter follow-up choice")

    local followup = _get_choice(g)
    local confirm_res = choice_resolver.resolve(g, followup, {
      type = "choice_select",
      choice_id = followup.id,
      option_id = 4,
      actor_role_id = p.id,
    })
    luassert.truthy(confirm_res and confirm_res.stay == true, "confirming repeatable pre_action follow-up should reopen item phase immediately when no anim waits")
    _assert_eq(inventory.count(p), 1, "confirming follow-up should consume exactly one item")
    local remote_values = g:peek_pending_remote_dice(p)
    luassert.truthy(remote_values and remote_values[1] == 4, "confirming follow-up should apply selected remote dice value")

    local reopened = _get_choice(g)
    luassert.truthy(reopened and reopened.kind == "item_phase_passive", "confirming repeatable follow-up should reopen item phase")
    luassert.truthy(_find_option_id_by_label(reopened, "地雷卡") ~= nil, "reopened phase should expose remaining pre_action item")
  end)

  it("test_preconsumed_followup_cancel_falls_back_to_first_option", function()
    local g = _new_game()
    local p = g:current_player()
    g.turn.item_phase_active = "pre_action"
    local pending = _open_choice(g, {
      kind = "remote_dice_value",
      route_key = "remote",
      title = "遥控骰子：选择点数",
      options = { { id = 4, label = "4" }, { id = 2, label = "2" } },
      allow_cancel = false,
      meta = {
        player_id = p.id,
        item_id = item_ids.remote_dice,
        dice_count = 1,
        item_preconsumed = true,
      },
    })

    local res = choice_resolver.resolve(g, pending, {
      type = "choice_cancel",
      choice_id = pending.id,
      actor_role_id = p.id,
    })
    _assert_eq(res and res.stay, false, "preconsumed follow-up should resolve instead of staying")
    _assert_eq(g.turn.pending_choice, nil, "preconsumed follow-up cancel should not keep choice")
    local fallback_values = g:peek_pending_remote_dice(p)
    luassert.truthy(fallback_values ~= nil, "remote dice value should still be applied")
    _assert_eq(fallback_values[1], 4, "cancel should fallback to first option value")
  end)

  it("test_tax_prompt_cancel_maps_to_skip_and_executes_pay_tax", function()
    local g = _new_game()
    local p = g:current_player()
    g:set_player_cash(p, 1000)
    local pending = _open_choice(g, {
      kind = "tax_card_prompt",
      title = "是否使用免税卡",
      options = {
        { id = "use", label = "使用" },
        { id = "skip", label = "不用" },
      },
      allow_cancel = true,
      cancel_label = "不用",
      meta = {
        player_id = p.id,
      },
    })

    local res = choice_resolver.resolve(g, pending, {
      type = "choice_cancel",
      choice_id = pending.id,
      actor_role_id = p.id,
    })

    _assert_eq(res and res.stay, false, "tax prompt cancel should resolve immediately")
    _assert_eq(g.turn.pending_choice, nil, "tax prompt cancel should clear pending choice")
    _assert_eq(g:player_cash(p), 500, "tax prompt cancel should pay tax through skip path")
  end)

  it("test_tax_prompt_exposes_confirm_copy", function()
    local choice = land_choice_specs.tax_prompt(11)
    _assert_eq(choice.route_key, "secondary_confirm", "tax prompt should expose secondary confirm route")
    _assert_eq(choice.requires_confirm, true, "tax prompt should expose confirm requirement")
    _assert_eq(choice.confirm_title, "税务局", "tax prompt should expose confirm title from use-case output")
    _assert_eq(choice.confirm_body, "这次要用免税卡吗？", "tax prompt should expose confirm body from use-case output")
  end)

  it("test_strong_rent_prompt_exposes_integer_confirm_copy", function()
    local choice = land_choice_specs.rent_prompt(11, 1, "strong", 2800.0, "福州路")
    _assert_eq(choice.route_key, "secondary_confirm", "strong rent prompt should expose secondary confirm route")
    _assert_eq(choice.requires_confirm, true, "strong rent prompt should expose confirm requirement")
    _assert_eq(choice.confirm_title, "强征卡", "strong rent prompt should expose confirm title")
    _assert_eq(choice.confirm_body, "支付 2800 强制购入 福州路",
      "strong rent prompt should render total value as integer text")
  end)

  it("test_simple_item_use_does_not_push_item_card_popup", function()
    local g = _new_game()
    local popups = {}
    local p = g:current_player()
    _set_ui_port(g, {
      push_popup = function(_, payload)
        popups[#popups + 1] = payload
      end,
    })
    p.inventory:add({ id = item_ids.tax_free })

    local res = executor.use_item(g, p, item_ids.tax_free, { is_computer_controlled = true })
    local ok = (type(res) == "table" and type(res.ok) ~= "nil") and res.ok or res
    _assert_eq(ok, true, "tax_free use ok")
    _assert_eq(#popups, 0, "simple item use should not push a card popup")
  end)

  it("test_target_item_use_does_not_push_item_card_popup", function()
    local g = _new_game()
    local popups = {}
    local user = g.players[1]
    local target = g.players[2]
    _set_ui_port(g, {
      push_popup = function(_, payload)
        popups[#popups + 1] = payload
      end,
    })
    g:set_player_cash(user, 1000)
    g:set_player_cash(target, 9000)
    user.inventory:add({ id = item_ids.share_wealth })

    local res = executor.use_item(g, user, item_ids.share_wealth, {
      is_computer_controlled = true,
      target_id = target.id,
    })
    local ok = (type(res) == "table" and type(res.ok) ~= "nil") and res.ok or res
    _assert_eq(ok, true, "target item use ok")
    _assert_eq(#popups, 0, "target item use should not push a card popup")
  end)

  it("test_remote_dice_followup_does_not_push_item_card_popup", function()
    local g = _new_game()
    local popups = {}
    local p = g:current_player()
    _set_ui_port(g, {
      push_popup = function(_, payload)
        popups[#popups + 1] = payload
      end,
    })
    g.turn.item_phase_active = "pre_action"
    p.inventory:add({ id = item_ids.remote_dice })
    local pending = _open_choice(g, {
      kind = "remote_dice_value",
      route_key = "remote",
      title = "遥控骰子：选择点数",
      options = { { id = 4, label = "4" } },
      allow_cancel = false,
      meta = {
        player_id = p.id,
        item_id = item_ids.remote_dice,
        dice_count = 1,
        item_preconsumed = false,
      },
    })

    local res = choice_resolver.resolve(g, pending, {
      type = "choice_select",
      choice_id = pending.id,
      option_id = 4,
      actor_role_id = p.id,
    })

    _assert_eq(res and res.stay, false, "remote dice follow-up should resolve immediately")
    _assert_eq(#popups, 0, "remote dice follow-up should not push a card popup")
  end)

  it("test_steal_uses_tip_without_popup", function()
    local g = _new_game()
    local popups = {}
    local tips = {}
    local stealer = g.players[1]
    local target = g.players[2]
    stealer.inventory:add({ id = item_ids.steal })
    target.inventory:add({ id = item_ids.tax_free })

    support.with_patches({
      {
        key = "GlobalAPI",
        value = {
          show_tips = function(text)
            tips[#tips + 1] = text
            return true
          end,
        },
      },
    }, function()
      _set_ui_port(g, {
        push_popup = function(_, payload)
          popups[#popups + 1] = payload
        end,
      })

      local res = steal.steal_nth_occupied(g, stealer, target, 1)
      _assert_eq(res and res.ok, true, "steal should succeed")
      _assert_eq(res and res.intent, nil, "steal success should not return popup intent")
    end)

    _assert_eq(#popups, 0, "steal success should not push popup")
    luassert.truthy(#tips >= 1, "steal success should show tip")
    luassert.truthy(string.find(tips[1], stealer.name, 1, true), "steal success tip should include stealer name")
    luassert.truthy(string.find(tips[1], target.name, 1, true), "steal success tip should include target name")
    luassert.truthy(string.find(tips[1], "免税卡", 1, true), "steal success tip should include stolen item name")
  end)

  it("test_steal_direct_success_queues_target_player_anim", function()
    local g = _setup_world_with_anim()
    local stealer = g.players[1]
    local target = g.players[2]
    stealer.inventory:add({ id = item_ids.steal })
    target.inventory:add({ id = item_ids.tax_free })

    local res = steal.steal_nth_occupied(g, stealer, target, 1)

    _assert_eq(res and res.ok, true, "steal should succeed")
    _assert_eq(res and res.action_anim, true, "steal should report queued action anim")
    luassert.truthy(g.turn.action_anim ~= nil, "steal should queue an action anim")
    _assert_eq(g.turn.action_anim.kind, "item_target_player", "steal anim kind mismatch")
    _assert_eq(g.turn.action_anim.player_id, stealer.id, "steal anim player mismatch")
    _assert_eq(g.turn.action_anim.target_player_id, target.id, "steal anim target mismatch")
    _assert_eq(g.turn.action_anim.item_id, item_ids.steal, "steal anim item id mismatch")
    _assert_eq(g.turn.action_anim.duration, timing.action_anim_default_seconds, "steal anim duration mismatch")
    _assert_eq(#(g.turn.action_anim_queue or {}), 1, "stolen item should reveal after steal anim")
    _assert_eq(g.turn.action_anim_queue[1].kind, "item_gain_popup", "stolen reveal kind mismatch")
    _assert_eq(g.turn.action_anim_queue[1].item_id, item_ids.tax_free, "stolen reveal item mismatch")
    _assert_eq(g.turn.action_anim_queue[1].source, "steal", "stolen reveal source mismatch")
  end)

  it("test_steal_failure_uses_tip_without_popup", function()
    local g = _new_game()
    local popups = {}
    local tips = {}
    local stealer = g.players[1]
    local target = g.players[2]
    stealer.inventory:add({ id = item_ids.steal })

    support.with_patches({
      {
        key = "GlobalAPI",
        value = {
          show_tips = function(text)
            tips[#tips + 1] = text
            return true
          end,
        },
      },
    }, function()
      _set_ui_port(g, {
        push_popup = function(_, payload)
          popups[#popups + 1] = payload
        end,
      })

      local res = steal.steal_nth_occupied(g, stealer, target, 1)
      _assert_eq(res and res.ok, false, "steal should fail when target has no items")
      _assert_eq(res and res.intent, nil, "steal failure should not return popup intent")
    end)

    _assert_eq(stealer.inventory:count(), 1, "steal failure should NOT consume steal card")
    _assert_eq(#popups, 0, "steal failure should not push popup")
    luassert.truthy(#tips >= 1, "steal failure should show tip")
    luassert.truthy(string.find(tips[1], stealer.name, 1, true), "steal failure tip should include stealer name")
    luassert.truthy(string.find(tips[1], target.name, 1, true), "steal failure tip should include target name")
    luassert.truthy(string.find(tips[1], "没有任何道具", 1, true), "steal failure tip should explain failure")
  end)

  it("test_steal_random_empty_target_fails_without_rng_or_consuming_card", function()
    local g = _new_game()
    local stealer = g.players[1]
    local target = g.players[2]
    stealer.inventory:add({ id = item_ids.steal })
    g.rng = {
      next_int = function()
        error("empty steal target must fail before random selection")
      end,
    }

    local res = steal.steal_random_item(g, stealer, target)

    _assert_eq(res and res.ok, false, "empty random steal should fail")
    _assert_eq(stealer.inventory:count(), 1, "empty random steal should not consume steal card")
    _assert_eq(target.inventory:count(), 0, "empty random steal target should stay empty")
  end)

  it("test_steal_with_full_inventory_succeeds_by_freeing_the_steal_card_slot", function()
    -- CONTEXT「偷窃入包」:满背包必然含偷窃卡自身,自耗先腾出这一格,
    -- 偷来的道具再进这一格 —— 背包已满不构成偷窃障碍,格数前后不变。
    local g = _new_game()
    local stealer = g.players[1]
    local target = g.players[2]
    stealer.inventory:add({ id = item_ids.steal })
    while stealer.inventory:count() < 5 do
      local ok = stealer.inventory:add({ id = item_ids.tax_free })
      luassert.truthy(ok == true, "preload stealer inventory failed")
    end
    target.inventory:add({ id = item_ids.roadblock })

    local res = steal.steal_nth_occupied(g, stealer, target, 1)

    _assert_eq(res and res.ok, true, "full-bag steal must succeed")
    _assert_eq(stealer.inventory:count(), 5, "bag stays full: steal card out, stolen item in")
    luassert.truthy(stealer.inventory:find_index(function(it)
      return it.id == item_ids.steal
    end) == nil, "steal card must be consumed to free its slot")
    luassert.truthy(stealer.inventory:find_index(function(it)
      return it.id == item_ids.roadblock
    end) ~= nil, "stolen roadblock must take the freed slot")
    _assert_eq(target.inventory:count(), 0, "target must lose the stolen item")
  end)

  it("test_rich_item_emits_deity_feedback_event", function()
    local g = _new_game()
    local p = g:current_player()
    local emitted = {}

    support.with_patches({
      {
        target = monopoly_event,
        key = "emit",
        value = function(kind, payload, opts)
          emitted[#emitted + 1] = { kind = kind, payload = payload }
          return true
        end,
      },
    }, function()
      p.inventory:add({ id = item_ids.rich })
      local res = executor.use_item(g, p, item_ids.rich, { is_computer_controlled = true })
      local ok = (type(res) == "table" and type(res.ok) ~= "nil") and res.ok or res
      _assert_eq(ok, true, "rich item use ok")
    end)

    luassert.truthy(#emitted >= 1, "rich item should emit at least one event")
    _assert_eq(emitted[1].kind, monopoly_event.feedback.deity_applied, "rich item should emit deity feedback event")
    _assert_eq(emitted[1].payload.deity_type, "rich", "rich item should emit rich deity type")
    _assert_eq(emitted[1].payload.player_id, p.id, "rich item should emit current player id")
  end)

  it("test_PIN: tax card drains target to zero and eliminates on non-positive", function()
    local g = _new_game()
    local user, target = g.players[1], g.players[2]
    g:set_player_cash(target, 100)  -- fee = floor(100*0.5) = 50; 两次不足以清零,构造精确边界:
    g:set_player_cash(target, 1)    -- fee = floor(1*0.5) = 0 → 扣 0,cash 仍 1,不淘汰
    target_cash_effects.tax.apply(g, user, target)
    luassert.truthy(target.eliminated ~= true, "fee floors to 0 at cash=1, no bankruptcy")

    g:set_player_cash(target, 2)    -- fee = floor(2*0.5) = 1 → cash 1,不淘汰
    target_cash_effects.tax.apply(g, user, target)
    luassert.truthy(g:player_cash(target) == 1, "cash 2 → pays 1 → left with 1")
  end)

-- Merged from test_item_strategy.lua -------------------------------------------------

  it("test_auto_pre_action_returns_use_flow_result_for_target_items", function()
    local g = _new_game()
    local actor = g.players[2]
    local target = g.players[1]
    actor.inventory:add({ id = item_ids.steal })
    target.inventory:add({ id = item_ids.roadblock })

    local result = item_strategy.auto_pre_action(g, actor, "pre_action")

    luassert.truthy(type(result) == "table", "auto target item should return a use-flow result")
    luassert.truthy(result.ok == true, "auto target item should apply successfully")
    luassert.truthy(result.status == "applied", "auto target item should be normalized as applied")
    luassert.truthy(result.actor_id == actor.id, "auto target item result should carry actor id")
    luassert.truthy(result.item_id == item_ids.steal, "auto target item result should carry item id")
    luassert.truthy(result.item_consumed == true, "auto target item should consume the item")
  end)

  it("test_try_use_item_cond_false_returns_nil", function()
    local game = { turn = { phase = "pre_action" } }
    local player = { id = 1, status = { inventory = {} } }
    local called_cond = false
    local cond = function()
      called_cond = true
      return false
    end
    local result = item_strategy._try_use_item(game, player, 1, cond, false)
    luassert.truthy(result == nil, "should return nil when cond returns false")
    luassert.truthy(called_cond == true, "should have called cond")
  end)

  it("test_try_use_item_no_inventory_returns_nil", function()
    local game = { turn = { phase = "pre_action" } }
    local player = {
      id = 1,
      inventory = {
        items = {},
        find_index = function()
          return nil
        end,
      },
    }
    local result = item_strategy._try_use_item(game, player, item_ids.dice_multiplier, nil, false)
    luassert.truthy(result == nil, "should return nil when item not in inventory")
  end)

  it("test_try_use_item_not_ai_usable_returns_nil", function()
    local game = { turn = { phase = "post_action" } }
    local player = { id = 1, status = { inventory = {} } }
    local result = item_strategy._try_use_item(game, player, item_ids.dice_multiplier, nil, false)
    luassert.truthy(result == nil, "should return nil when item not AI-usable in phase")
  end)

  it("test_try_use_item_returns_waiting_payload", function()
    local inventory_module = require("src.rules.items.inventory")
    local use_flow = require("src.rules.items.use_flow")
    local original_cfg = inventory_module.cfg
    local original_begin_item_use = use_flow.begin_item_use
    inventory_module.cfg = function()
      return { offer_in_phases = { "pre_action" } }
    end
    use_flow.begin_item_use = function(_, actor_id, item_id, opts)
      luassert.truthy(actor_id == 1, "expected actor id")
      luassert.truthy(item_id == item_ids.dice_multiplier, "expected item id")
      luassert.truthy(opts.phase == "pre_action", "expected phase")
      luassert.truthy(opts.is_computer_controlled == true, "expected is_computer_controlled flag")
      luassert.truthy(opts.auto_play == true, "expected auto_play flag")
      return { ok = true, waiting = true, status = "waiting_choice", source = "test" }
    end

    local ok, err = pcall(function()
      local game = { turn = { phase = "pre_action" } }
      local player = { id = 1 }
      local result = item_strategy._try_use_item(game, player, item_ids.dice_multiplier, nil, true)
      luassert.truthy(type(result) == "table", "should return waiting table")
      luassert.truthy(result.source == "test", "should preserve use-flow payload")
    end)

    inventory_module.cfg = original_cfg
    use_flow.begin_item_use = original_begin_item_use
    if not ok then
      error(err)
    end
  end)

  it("test_try_use_item_returns_nil_for_rejected_flow_result", function()
    local inventory_module = require("src.rules.items.inventory")
    local use_flow = require("src.rules.items.use_flow")
    local original_cfg = inventory_module.cfg
    local original_begin_item_use = use_flow.begin_item_use
    inventory_module.cfg = function()
      return { offer_in_phases = { "pre_action" } }
    end
    use_flow.begin_item_use = function()
      return { ok = false, status = "rejected", reason = "item_not_in_inventory" }
    end

    local ok, err = pcall(function()
      local game = { turn = { phase = "pre_action" } }
      local player = { id = 1 }
      local result = item_strategy._try_use_item(game, player, item_ids.dice_multiplier, nil, false)
      luassert.truthy(result == nil, "should ignore rejected use-flow result")
    end)

    inventory_module.cfg = original_cfg
    use_flow.begin_item_use = original_begin_item_use
    if not ok then
      error(err)
    end
  end)


end)
