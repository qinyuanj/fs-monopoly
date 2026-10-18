require("test.bootstrap").install_package_paths()
-- luacheck: ignore 143 (busted injects the verified luassert object)
local luassert = assert
do
  local support = require("test.support.shared_support")
  local default_map = require("src.config.content.default_map")
  local item_ids = require("src.config.gameplay.item_ids")
  local demolish = require("src.rules.items.demolish")
  local inventory = require("src.rules.items.inventory")
  local intent_output_port = require("src.rules.ports.intent_output")
  local flow_context = require("src.rules.items.use_flow_context")
  local flow_result = require("src.rules.items.use_flow_result")
  local remote_dice = require("src.rules.items.remote_dice")
  local resolvers = require("src.rules.items.use_flow_resolvers")
  local roadblock = require("src.rules.items.roadblock")
  local settlement = require("src.rules.items.settlement")
  local use_flow = require("src.rules.items.use_flow")

  local function _new_game()
    return support.new_game({ map = default_map })
  end

  local function _assert_eq(actual, expected, msg)
    luassert.truthy(actual == expected, tostring(msg) .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
  end

  local function _with_item_handler(game, item_id, handler, fn)
    local handlers = luassert.truthy(game.registries and game.registries.items and game.registries.items.handlers,
      "missing item handlers")
    local previous = handlers[item_id]
    handlers[item_id] = handler
    local ok, result = pcall(fn)
    handlers[item_id] = previous
    if not ok then
      error(result, 0)
    end
    return result
  end

  local function _with_patches(patches, fn)
    local previous = {}
    for index, patch in ipairs(patches) do
      previous[index] = patch.target[patch.key]
      patch.target[patch.key] = patch.value
    end

    local ok, result = pcall(fn)
    for index = #patches, 1, -1 do
      local patch = patches[index]
      patch.target[patch.key] = previous[index]
    end
    if not ok then
      error(result, 0)
    end
    return result
  end

  local _config_reset = require("test.support.config_reset")



  describe("TestItemUseFlow", function()
    before_each(function()
      _config_reset.reset_all()
    end)
    it("test_begin_rejects_missing_game_before_item_checks", function()
      local result = use_flow.begin_item_use(nil, nil, item_ids.mine, {})

      _assert_eq(result.ok, false, "missing game should reject")
      _assert_eq(result.reason, "missing_game", "missing game reason")
    end)

    it("test_begin_rejects_missing_actor_with_stable_reason", function()
      local g = _new_game()

      local result = use_flow.begin_item_use(g, 9999, item_ids.mine, { phase = "pre_action" })

      _assert_eq(result.ok, false, "missing actor should reject")
      _assert_eq(result.status, "rejected", "missing actor status")
      _assert_eq(result.reason, "missing_actor", "missing actor reason")
    end)

    it("test_begin_rejects_missing_item_config_and_absent_inventory_before_executing_effect", function()
      local g = _new_game()
      local player = g:current_player()
      local missing_item_id = 999999
      player.inventory:add({ id = missing_item_id })

      local missing_cfg = use_flow.begin_item_use(g, player.id, missing_item_id, {})
      local missing_inventory = use_flow.begin_item_use(g, player.id, item_ids.mine, { phase = "pre_action" })

      _assert_eq(missing_cfg.ok, false, "missing cfg should reject")
      _assert_eq(missing_cfg.reason, "missing_item_cfg", "missing cfg reason")
      _assert_eq(missing_inventory.ok, false, "absent inventory item should reject")
      _assert_eq(missing_inventory.reason, "item_not_in_inventory", "absent inventory reason")
    end)

    it("test_begin_rejects_item_outside_current_phase_before_executing_effect", function()
      local g = _new_game()
      local player = g:current_player()
      player.inventory:add({ id = item_ids.remote_dice })

      local result = use_flow.begin_item_use(g, player.id, item_ids.remote_dice, { phase = "post_action" })

      _assert_eq(result.ok, false, "phase mismatch should reject")
      _assert_eq(result.reason, "offer_in_phases_not_allowed", "phase mismatch reason")
      _assert_eq(inventory.count(player), 1, "rejected item should remain")
    end)

    it("test_begin_accepts_table_actors_and_games_without_find_player_by_id", function()
      local g = _new_game()
      local player = g.players[1]
      player.inventory:add({ id = item_ids.mine })
      player.inventory:add({ id = item_ids.mine })

      _with_item_handler(g, item_ids.mine, function()
        return { ok = true, action_anim = true }
      end, function()
        local table_actor = use_flow.begin_item_use(g, player, item_ids.mine, { is_computer_controlled = false })
        local fallback_game = {
          anim_gate_port = {},
          players = g.players,
          registries = g.registries,
          turn = g.turn,
        }
        local fallback_actor = use_flow.begin_item_use(fallback_game, player.id, item_ids.mine, { is_computer_controlled = false })

        _assert_eq(table_actor.ok, true, "table actor should apply")
        _assert_eq(fallback_actor.ok, true, "fallback player scan should apply")
      end)
    end)

    it("test_context_resolves_actors_through_finder_before_players_fallback", function()
      local finder_player = { id = 7 }
      local fallback_player = { id = 7 }
      local calls = 0
      local game = {
        players = { fallback_player },
        find_player_by_id = function(_, actor_id)
          calls = calls + 1
          _assert_eq(actor_id, 7, "finder actor id")
          return finder_player
        end,
      }

      local resolved = flow_context.resolve_actor(game, 7)

      _assert_eq(resolved, finder_player, "finder player should win")
      _assert_eq(calls, 1, "finder should be called once")
    end)

    it("test_context_counts_zero_matching_items_without_offset", function()
      local g = _new_game()
      local player = g.players[1]
      inventory.clear(player)
      player.inventory:add({ id = item_ids.roadblock })

      _assert_eq(flow_context.count_item(player, item_ids.mine), 0, "absent item count")
      player.inventory:add({ id = item_ids.mine })
      _assert_eq(flow_context.count_item(player, item_ids.mine), 1, "single item count")
    end)

    it("test_begin_preserves_failed_effect_reasons_and_bare_failure_fallback", function()
      local g = _new_game()
      local player = g.players[1]
      player.inventory:add({ id = item_ids.mine })
      player.inventory:add({ id = item_ids.mine })

      _with_item_handler(g, item_ids.mine, function(_, _, _, context)
        if context.fail_bare then
          return { ok = false }
        end
        return { ok = false, reason = "handler_blocked", item_consumed = true }
      end, function()
        local reason = use_flow.begin_item_use(g, player.id, item_ids.mine, {})
        local bare = use_flow.begin_item_use(g, player.id, item_ids.mine, {
          fail_bare = true,
        })

        _assert_eq(reason.ok, false, "handler reason should reject")
        _assert_eq(reason.reason, "handler_blocked", "handler reason should be preserved")
        _assert_eq(reason.item_consumed, true, "explicit consumed marker should be preserved")
        _assert_eq(bare.ok, false, "bare failure should reject")
        _assert_eq(bare.reason, "no_candidates", "bare failure takes the flow's fallback reason")
      end)
    end)

    it("test_begin_uses_fallback_rejection_reason_for_false_effect_results", function()
      local g = _new_game()
      local player = g.players[1]
      player.inventory:add({ id = item_ids.mine })

      _with_item_handler(g, item_ids.mine, function()
        return false
      end, function()
        local result = use_flow.begin_item_use(g, player.id, item_ids.mine, {})

        _assert_eq(result.ok, false, "false handler result should reject")
        _assert_eq(result.reason, "no_candidates", "false handler fallback reason")
      end)
    end)

    it("test_begin_treats_successful_raw_effect_shapes_as_applied", function()
      local g = _new_game()
      local player = g.players[1]
      player.inventory:add({ id = item_ids.mine })

      _with_item_handler(g, item_ids.mine, function(_, _, _, context)
        if context.table_without_ok then
          return { action_anim = true }
        end
        return true
      end, function()
        local plain_true = use_flow.begin_item_use(g, player.id, item_ids.mine, {})
        local table_without_ok = use_flow.begin_item_use(g, player.id, item_ids.mine, {
          table_without_ok = true,
        })

        _assert_eq(plain_true.ok, true, "plain true result should apply")
        _assert_eq(plain_true.status, "applied", "plain true status")
        _assert_eq(table_without_ok.ok, true, "table without ok should apply")
        _assert_eq(table_without_ok.status, "applied", "table without ok status")
      end)
    end)

    it("test_normalizes_waiting_effect_metadata", function()
      local g = _new_game()
      local player = g.players[1]
      player.inventory:add({ id = item_ids.mine })
      local choice_spec = {
        kind = "item_target_player",
        options = { { id = player.id, label = player.name } },
      }

      local waiting = flow_result.normalize_effect({
        waiting = true,
        ok = false,
        intent = { choice_spec = choice_spec },
      }, player, item_ids.mine)

      _assert_eq(waiting.status, "waiting_choice", "waiting result status")
      _assert_eq(waiting.actor_id, player.id, "waiting result actor id")
      _assert_eq(waiting.choice_spec, choice_spec, "waiting result choice spec")
      _assert_eq(waiting.item_consumed, false, "waiting result should not consume")
    end)

    it("test_passes_settled_results_through_untouched", function()
      local g = _new_game()
      local player = g.players[1]
      local settled = settlement.execute(g, player, item_ids.mine, function()
        return { ok = false, reason = "blocked" }
      end, { fallback_reason = "fallback", context_preconsumed = true })

      _assert_eq(flow_result.normalize_effect(settled, player, item_ids.mine), settled,
        "settled results should pass through unchanged")
    end)

    it("test_errors_for_unsettled_non_waiting_effect_results", function()
      local g = _new_game()
      local player = g.players[1]
      -- 非 settled 也非 waiting 的结果必须抛错;不对具体消息做精确匹配避免脆断言。
      local ok, err = pcall(flow_result.normalize_effect, { ok = true }, player, item_ids.mine)
      _assert_eq(ok, false, "unsettled non-waiting result should error")
      luassert.truthy(type(err) == "string" and err:find("unsettled item effect result", 1, true), "error should include unsettled item effect result prefix, got: " .. tostring(err))
    end)

    it("test_begin_returns_structured_waiting_choice_for_manual_target_item", function()
      local g = _new_game()
      local user = g.players[1]
      local target = g.players[2]
      user.inventory:add({ id = item_ids.steal })
      target.inventory:add({ id = item_ids.roadblock })

      local result = use_flow.begin_item_use(g, user.id, item_ids.steal, { phase = "pre_action" })

      _assert_eq(result.ok, true, "steal begin should be accepted")
      _assert_eq(result.status, "waiting_choice", "steal should wait for target choice")
      _assert_eq(result.item_consumed, false, "waiting choice should not consume item")
      luassert.truthy(result.choice_spec and result.choice_spec.kind == "item_target_player", "steal should expose target-player choice")
      _assert_eq(result.choice_spec.options[1].id, target.id, "target with item should be offered")
    end)

    it("test_resolve_target_player_choice_applies_item_through_shared_flow", function()
      local g = _new_game()
      local user = g.players[1]
      local target = g.players[2]
      user.inventory:add({ id = item_ids.steal })
      target.inventory:add({ id = item_ids.roadblock })
      target.inventory:add({ id = item_ids.tax_free })

      local begin = use_flow.begin_item_use(g, user.id, item_ids.steal, { phase = "pre_action" })
      local choice = support.open_choice(g, begin.choice_spec)

      local result = use_flow.resolve_item_use_choice(g, choice, {
        type = "choice_select",
        choice_id = choice.id,
        option_id = target.id,
        actor_role_id = user.id,
      })

      _assert_eq(result.ok, true, "target choice should apply")
      _assert_eq(result.status, "applied", "target choice status")
      _assert_eq(result.item_consumed, true, "steal card should be consumed")
      _assert_eq(support.count_item(user, item_ids.steal), 0, "steal card should leave inventory")
      _assert_eq(inventory.count(target), 1, "target should lose one item")
    end)

    it("test_resolve_rejects_choices_that_do_not_belong_to_the_selected_item_use", function()
      local g = _new_game()
      local user = g.players[1]
      user.inventory:add({ id = item_ids.remote_dice })
      local choice = support.open_choice(g, {
        kind = "remote_dice_value",
        options = { { id = 4, label = "4" } },
        meta = {
          player_id = user.id,
          item_id = item_ids.roadblock,
          dice_count = 1,
        },
      })

      local result = use_flow.resolve_item_use_choice(g, choice, {
        type = "choice_select",
        choice_id = choice.id,
        option_id = 4,
        actor_role_id = user.id,
      }, {
        item_id = item_ids.remote_dice,
      })

      _assert_eq(result.ok, false, "wrong item metadata should reject")
      _assert_eq(result.reason, "item_mismatch", "wrong item reason")
      _assert_eq(support.count_item(user, item_ids.remote_dice), 1, "rejected choice should not consume item")
    end)

    it("test_resolve_accepts_numeric_submissions_for_string_like_option_ids", function()
      local g = _new_game()
      local user = g.players[1]
      user.inventory:add({ id = item_ids.remote_dice })
      local choice = support.open_choice(g, {
        kind = "remote_dice_value",
        options = { "4" },
        meta = {
          player_id = user.id,
          item_id = item_ids.remote_dice,
          dice_count = 1,
        },
      })

      local result = use_flow.resolve_item_use_choice(g, choice, {
        type = "choice_select",
        choice_id = choice.id,
        option_id = 4,
        actor_role_id = user.id,
      })

      _assert_eq(result.ok, true, "string option should accept numeric submission")
      _assert_eq(result.status, "applied", "string option numeric submission status")
      _assert_eq(support.count_item(user, item_ids.remote_dice), 0, "accepted string option should consume item")
    end)

    it("test_resolve_accepts_numeric_submissions_for_table_options_with_string_ids", function()
      local g = _new_game()
      local user = g.players[1]
      user.inventory:add({ id = item_ids.remote_dice })
      local choice = support.open_choice(g, {
        kind = "remote_dice_value",
        options = { { id = "4", label = "4" } },
        meta = {
          player_id = user.id,
          item_id = item_ids.remote_dice,
          dice_count = 1,
        },
      })

      local result = use_flow.resolve_item_use_choice(g, choice, {
        type = "choice_select",
        choice_id = choice.id,
        option_id = 4,
        actor_role_id = user.id,
      })

      _assert_eq(result.ok, true, "table string option id should accept numeric submission")
      _assert_eq(result.status, "applied", "table string option numeric submission status")
      _assert_eq(support.count_item(user, item_ids.remote_dice), 0, "accepted table string option should consume item")
    end)

    it("test_resolve_accepts_string_item_ids_in_caller_context_when_choice_metadata_is_numeric", function()
      local g = _new_game()
      local user = g.players[1]
      user.inventory:add({ id = item_ids.remote_dice })
      local choice = support.open_choice(g, {
        kind = "remote_dice_value",
        options = { { id = 4, label = "4" } },
        meta = {
          player_id = user.id,
          item_id = item_ids.remote_dice,
          dice_count = 1,
        },
      })

      local result = use_flow.resolve_item_use_choice(g, choice, {
        type = "choice_select",
        choice_id = choice.id,
        option_id = 4,
        actor_role_id = user.id,
      }, {
        item_id = tostring(item_ids.remote_dice),
      })

      _assert_eq(result.ok, true, "string context item id should match numeric choice metadata")
      _assert_eq(result.status, "applied", "string context item id status")
      _assert_eq(support.count_item(user, item_ids.remote_dice), 0, "matched string context item id should consume item")
    end)

    it("test_resolver_falls_back_to_game_dice_count_for_remote_dice_choices", function()
      local g = _new_game()
      local user = g.players[1]
      user.inventory:add({ id = item_ids.remote_dice })
      local captured = {}
      g.player_dice_count = function(_, player)
        captured.dice_player = player
        return 2
      end

      _with_patches({
        {
          target = remote_dice,
          key = "apply",
          value = function(game, player, dice_count, option_id)
            captured.game = game
            captured.player = player
            captured.dice_count = dice_count
            captured.option_id = option_id
            return { ok = true }
          end,
        },
      }, function()
        local result = resolvers.resolve(g, {
          kind = "remote_dice_value",
        }, {
          option_id = 5,
        }, {}, {
          item_id = item_ids.remote_dice,
        }, user, item_ids.remote_dice)

        _assert_eq(result.ok, true, "remote dice resolver should apply")
        _assert_eq(captured.game, g, "remote dice game")
        _assert_eq(captured.player, user, "remote dice player")
        _assert_eq(captured.dice_player, user, "remote dice count player")
        _assert_eq(captured.dice_count, 2, "remote dice count fallback")
        _assert_eq(captured.option_id, 5, "remote dice selected value")
        _assert_eq(support.count_item(user, item_ids.remote_dice), 0, "remote dice should consume item")
      end)
    end)

    it("test_resolver_rejects_invalid_roadblock_choices_before_consuming_item", function()
      local g = _new_game()
      local user = g.players[1]
      user.inventory:add({ id = item_ids.roadblock })

      _with_patches({
        {
          target = roadblock,
          key = "is_ui_candidate",
          value = function()
            return false
          end,
        },
        {
          target = roadblock,
          key = "apply",
          value = function()
            error("roadblock apply should not run")
          end,
        },
      }, function()
        local result = resolvers.resolve(g, {
          kind = "roadblock_target",
        }, {
          option_id = 9999,
        }, {}, {
          item_id = item_ids.roadblock,
        }, user, item_ids.roadblock)

        _assert_eq(result.ok, false, "invalid roadblock target should reject")
        _assert_eq(result.reason, "invalid_target", "invalid roadblock reason")
        _assert_eq(support.count_item(user, item_ids.roadblock), 1, "invalid roadblock should not consume item")
      end)
    end)

    it("test_resolver_dispatches_demolish_raw_result_intent", function()
      local g = _new_game()
      local user = g.players[1]
      user.inventory:add({ id = item_ids.monster })
      local raw_intent = { kind = "push_popup", payload = { title = "done" } }
      local dispatches = {}
      local captured = {}

      _with_patches({
        {
          target = demolish,
          key = "apply",
          value = function(game, player, option_id, opts)
            captured.game = game
            captured.player = player
            captured.option_id = option_id
            captured.item_id = opts and opts.item_id or nil
            return { ok = true, intent = raw_intent }
          end,
        },
        {
          target = intent_output_port,
          key = "dispatch",
          value = function(game, payload)
            dispatches[#dispatches + 1] = { game = game, payload = payload }
          end,
        },
      }, function()
        local result = resolvers.resolve(g, {
          kind = "demolish_target",
        }, {
          option_id = 12,
        }, {}, {
          item_id = item_ids.monster,
        }, user, item_ids.monster)

        _assert_eq(result.ok, true, "demolish resolver should apply")
        _assert_eq(captured.game, g, "demolish game")
        _assert_eq(captured.player, user, "demolish player")
        _assert_eq(captured.option_id, 12, "demolish target")
        _assert_eq(captured.item_id, item_ids.monster, "demolish item id")
        _assert_eq(#dispatches, 1, "demolish should dispatch one intent")
        _assert_eq(dispatches[1].game, g, "demolish dispatch game")
        _assert_eq(dispatches[1].payload, raw_intent, "demolish dispatch intent")
        _assert_eq(support.count_item(user, item_ids.monster), 0, "demolish should consume item")
      end)
    end)

    it("test_resolve_rejects_malformed_choice_submissions_before_applying_effects", function()
      local g = _new_game()
      local user = g.players[1]
      user.inventory:add({ id = item_ids.remote_dice })
      local choice = support.open_choice(g, {
        kind = "remote_dice_value",
        options = { { id = 4, label = "4" } },
        meta = {
          player_id = user.id,
          item_id = item_ids.remote_dice,
          dice_count = 1,
        },
      })

      local missing_game = use_flow.resolve_item_use_choice(nil, choice, { option_id = 4 })
      local missing_choice = use_flow.resolve_item_use_choice(g, nil, { option_id = 4 })
      local missing_action = use_flow.resolve_item_use_choice(g, choice, nil)
      local choice_mismatch = use_flow.resolve_item_use_choice(g, choice, {
        choice_id = choice.id + 1,
        option_id = 4,
        actor_role_id = user.id,
      })
      local actor_mismatch = use_flow.resolve_item_use_choice(g, choice, {
        choice_id = choice.id,
        option_id = 4,
        actor_role_id = user.id + 1,
      })
      local invalid_option = use_flow.resolve_item_use_choice(g, choice, {
        choice_id = choice.id,
        option_id = 7,
        actor_role_id = user.id,
      })

      _assert_eq(missing_game.reason, "missing_game", "missing game reason")
      _assert_eq(missing_choice.reason, "missing_choice", "missing choice reason")
      _assert_eq(missing_action.reason, "missing_action", "missing action reason")
      _assert_eq(choice_mismatch.reason, "choice_mismatch", "choice mismatch reason")
      _assert_eq(actor_mismatch.reason, "actor_mismatch", "actor mismatch reason")
      _assert_eq(invalid_option.reason, "invalid_option", "invalid option reason")
      _assert_eq(support.count_item(user, item_ids.remote_dice), 1, "malformed choices should not consume")
    end)

    it("test_resolve_rejects_missing_actors_and_unsupported_choice_kinds", function()
      local g = _new_game()
      local user = g.players[1]
      local missing_actor_choice = support.open_choice(g, {
        kind = "remote_dice_value",
        options = { { id = 4, label = "4" } },
        meta = {
          player_id = 9999,
          item_id = item_ids.remote_dice,
          dice_count = 1,
        },
      })
      local unsupported_choice = support.open_choice(g, {
        kind = "unsupported_item_choice",
        options = { { id = "only", label = "Only" } },
        meta = {
          player_id = user.id,
          item_id = item_ids.remote_dice,
        },
      })

      local missing_actor = use_flow.resolve_item_use_choice(g, missing_actor_choice, {
        choice_id = missing_actor_choice.id,
        option_id = 4,
      })
      local unsupported = use_flow.resolve_item_use_choice(g, unsupported_choice, {
        choice_id = unsupported_choice.id,
        option_id = "only",
        actor_role_id = user.id,
      })

      _assert_eq(missing_actor.reason, "missing_actor", "missing actor reason")
      _assert_eq(unsupported.reason, "unsupported_choice_kind", "unsupported kind reason")
    end)
  end)
end

-- ===== merged from test_item_use_settlement_pin.lua =====
do
---@diagnostic disable: redundant-parameter
-- 道具使用结果结算 pin spec(深化迁移 step 0)
-- 在 settlement 深模块落地前,把散布在 executor/handlers/use_flow_resolvers 的
-- 结算行为(成功判定、消耗时机、广播/遥测恰好一次、留卡语义)按 类别×路径 钉死。
-- fixture 一律经真实 begin/resolve 路径构造;禁止手搓 choice.meta(假绿风险)。
  local support = require("test.support.shared_support")
  local default_map = require("src.config.content.default_map")
  local availability = require("src.rules.items.availability")
  local choice_resolver = require("src.rules.choice.resolver")
  local demolish = require("src.rules.items.demolish")
  local item_ids = require("src.config.gameplay.item_ids")
  local post_effects = require("src.rules.items.post_effects")
  local remote_dice = require("src.rules.items.remote_dice")
  local settlement = require("src.rules.items.settlement")
  local use_flow = require("src.rules.items.use_flow")
  local action_anim_port = require("src.foundation.ports.action_anim")

  local function _assert_eq(actual, expected, msg)
    luassert.truthy(actual == expected, tostring(msg) .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
  end

  local function _new_game()
    return support.new_game({ map = default_map })
  end

  -- 道具使用卡牌展示与成就遥测的按局探针。
  -- 道具使用不再推送 item_card popup;成就经 game.achievement_progress_port。
  local function _install_probes(game)
    local probes = { item_card_popups = 0, item_used_events = 0, opened_choice_specs = {} }
    game.achievement_progress_port = {
      item_used = function()
        probes.item_used_events = probes.item_used_events + 1
        return true
      end,
    }
    game.intent_output_port = {
      push_popup = function(_, payload)
        if type(payload) == "table" and payload.kind == "item_card" then
          probes.item_card_popups = probes.item_card_popups + 1
        end
        return true
      end,
      open_choice = function(_, choice_spec)
        probes.opened_choice_specs[#probes.opened_choice_specs + 1] = choice_spec
        return true
      end,
    }
    return probes
  end

  local function _with_patches(patches, fn)
    local previous = {}
    for index, patch in ipairs(patches) do
      previous[index] = patch.target[patch.key]
      patch.target[patch.key] = patch.value
    end
    local ok, result = pcall(fn)
    for index = #patches, 1, -1 do
      local patch = patches[index]
      patch.target[patch.key] = previous[index]
    end
    if not ok then
      error(result, 0)
    end
    return result
  end

  local function _select_action(choice, option_id, actor_role_id)
    return {
      type = "choice_select",
      choice_id = choice.id,
      option_id = option_id,
      actor_role_id = actor_role_id,
    }
  end

  -- 经真实 begin_item_use 拿 followup spec,再经 settlement.escrow(真实写入口)
  -- 装饰预消耗;meta 仍不手搓。原经 item_phase_choice handler 的构造链随该
  -- 生产死 kind 一起收掉了;escrow 写入口今天没有生产调用者,这里 pin 的是
  -- 台账 resolve/refund 语义本身,escrow 面的去留另行裁决(见 escrow 死面 issue)。
  local function _open_preconsumed_followup(game, player, item_id, _probes)
    local result
    _with_patches({
      {
        target = availability,
        key = "can_offer_in_phase",
        value = function()
          return true, "ok"
        end,
      },
    }, function()
      result = use_flow.begin_item_use(game, player.id, item_id, { phase = "landing" })
    end)
    local followup_spec = result and result.intent and result.intent.choice_spec or nil
    luassert.truthy(followup_spec ~= nil, "waiting item use should surface a followup choice spec")
    settlement.escrow(player, item_id, followup_spec)
    return followup_spec
  end

  local _config_reset = require("test.support.config_reset")



  -- 类别:简单 post 道具 · 路径:begin(人类)
  describe("TestItemUseFlowSettlementPins", function()
    before_each(function()
      _config_reset.reset_all()
    end)
    it("test_post_item_consumes_before_apply_without_card_popup", function()
      local g = _new_game()
      local player = g.players[1]
      local probes = _install_probes(g)
      player.inventory:add({ id = item_ids.free_rent })
      local count_at_apply = nil

      _with_patches({
        {
          target = post_effects,
          key = "apply_post",
          value = function(_, apply_player)
            count_at_apply = support.count_item(apply_player, item_ids.free_rent)
            return true
          end,
        },
      }, function()
        local result = use_flow.begin_item_use(g, player.id, item_ids.free_rent, {})

        _assert_eq(result.ok, true, "post item should apply")
        _assert_eq(result.status, "applied", "post item status")
        _assert_eq(result.item_consumed, true, "post item should report consumed")
      end)

      _assert_eq(count_at_apply, 0, "post item must be consumed before apply runs")
      _assert_eq(support.count_item(player, item_ids.free_rent), 0, "post item should leave inventory")
      _assert_eq(probes.item_card_popups, 0, "post item should not display a card popup")
      _assert_eq(probes.item_used_events, 1, "post item should report telemetry exactly once")
    end)

  -- 类别:遥控骰子 · 路径:begin(AI 即时 apply)
    it("test_ai_remote_dice_consumes_before_apply_without_card_popup", function()
      local g = _new_game()
      local player = g.players[1]
      local probes = _install_probes(g)
      player.inventory:add({ id = item_ids.remote_dice })
      g.auto_play_port = {
        pick_remote_dice_value = function()
          return 4
        end,
      }
      local count_at_apply = nil

      _with_patches({
        {
          target = remote_dice,
          key = "apply",
          value = function(_, apply_player)
            count_at_apply = support.count_item(apply_player, item_ids.remote_dice)
            return { ok = true }
          end,
        },
      }, function()
        local result = use_flow.begin_item_use(g, player.id, item_ids.remote_dice, { is_computer_controlled = true })

        _assert_eq(result.ok, true, "ai remote dice should apply")
        _assert_eq(result.status, "applied", "ai remote dice status")
      end)

      _assert_eq(count_at_apply, 0, "ai remote dice must be consumed before apply runs")
      _assert_eq(probes.item_card_popups, 0, "ai remote dice should not display a card popup")
      _assert_eq(probes.item_used_events, 1, "ai remote dice should report telemetry exactly once")
    end)

  -- 类别:目标玩家道具 · 路径:begin 等待选择
    it("test_waiting_choice_never_consumes_displays_or_reports_telemetry", function()
      local g = _new_game()
      local user = g.players[1]
      local target = g.players[2]
      local probes = _install_probes(g)
      user.inventory:add({ id = item_ids.steal })
      target.inventory:add({ id = item_ids.roadblock })

      local result = use_flow.begin_item_use(g, user.id, item_ids.steal, { phase = "pre_action" })

      _assert_eq(result.status, "waiting_choice", "steal begin should wait for target")
      _assert_eq(result.item_consumed, false, "waiting must not consume")
      _assert_eq(support.count_item(user, item_ids.steal), 1, "steal card should remain while waiting")
      _assert_eq(probes.item_card_popups, 0, "waiting must not broadcast")
      _assert_eq(probes.item_used_events, 0, "waiting must not report telemetry")
    end)

  -- 类别:目标玩家道具 · 路径:choice 取消
    it("test_cancelling_a_target_choice_retains_the_item_without_broadcast", function()
      local g = _new_game()
      local user = g.players[1]
      local target = g.players[2]
      local probes = _install_probes(g)
      user.inventory:add({ id = item_ids.steal })
      target.inventory:add({ id = item_ids.roadblock })

      local begin_result = use_flow.begin_item_use(g, user.id, item_ids.steal, { phase = "pre_action" })
      local choice = support.open_choice(g, begin_result.choice_spec)
      choice_resolver.resolve(g, choice, { type = "choice_cancel", choice_id = choice.id })

      _assert_eq(support.count_item(user, item_ids.steal), 1, "cancelled choice should retain the item")
      _assert_eq(probes.item_card_popups, 0, "cancelled choice must not broadcast")
      _assert_eq(probes.item_used_events, 0, "cancelled choice must not report telemetry")
    end)

  -- 类别:偷窃(applier 自耗) · 路径:resolve(经 executor 重入)
    it("test_steal_resolve_consumes_exactly_one_card_without_card_popup", function()
      local g = _new_game()
      local user = g.players[1]
      local target = g.players[2]
      local probes = _install_probes(g)
      user.inventory:add({ id = item_ids.steal })
      target.inventory:add({ id = item_ids.roadblock })

      local begin_result = use_flow.begin_item_use(g, user.id, item_ids.steal, { phase = "pre_action" })
      local choice = support.open_choice(g, begin_result.choice_spec)
      local result = use_flow.resolve_item_use_choice(g, choice, _select_action(choice, target.id, user.id))

      _assert_eq(result.ok, true, "steal resolve should apply")
      _assert_eq(result.item_consumed, true, "steal resolve should report consumed")
      _assert_eq(support.count_item(user, item_ids.steal), 0, "steal card should be consumed")
      _assert_eq(support.count_item(user, item_ids.roadblock), 1, "stolen item should arrive")
      _assert_eq(support.count_item(target, item_ids.roadblock), 0, "target should lose the stolen item")
      _assert_eq(probes.item_card_popups, 0, "steal resolve should not display a card popup")
      _assert_eq(probes.item_used_events, 1, "steal resolve should report telemetry exactly once")
    end)

  -- 类别:偷窃 · 路径:resolve,背包已满(自耗腾格,CONTEXT「偷窃入包」)
    it("test_steal_against_a_full_bag_succeeds_by_consuming_the_steal_card_first", function()
      local g = _new_game()
      local user = g.players[1]
      local target = g.players[2]
      local probes = _install_probes(g)
      user.inventory:add({ id = item_ids.steal })
      while not user.inventory:is_full() do
        user.inventory:add({ id = item_ids.roadblock })
      end
      local slots_before = user.inventory:count()
      target.inventory:add({ id = item_ids.mine })

      local begin_result = use_flow.begin_item_use(g, user.id, item_ids.steal, { phase = "pre_action" })
      local choice = support.open_choice(g, begin_result.choice_spec)
      local result = use_flow.resolve_item_use_choice(g, choice, _select_action(choice, target.id, user.id))

      _assert_eq(result.ok, true, "full bag steal should succeed")
      _assert_eq(support.count_item(user, item_ids.steal), 0, "steal card must be consumed to free its slot")
      _assert_eq(support.count_item(user, item_ids.mine), 1, "stolen item takes the freed slot")
      _assert_eq(support.count_item(target, item_ids.mine), 0, "target loses the stolen item")
      _assert_eq(user.inventory:count(), slots_before, "bag stays full: one slot out, one slot in")
      _assert_eq(probes.item_card_popups, 0, "successful steal should not display a card popup")
      _assert_eq(probes.item_used_events, 1, "successful steal reports telemetry exactly once")
    end)

  -- 类别:目标玩家道具 · 路径:resolve(apply 成功后才消耗)
    it("test_target_item_consumes_only_after_successful_apply", function()
      local g = _new_game()
      local user = g.players[1]
      local target = g.players[2]
      local probes = _install_probes(g)
      user.inventory:add({ id = item_ids.exile })
      local count_at_apply = nil

      _with_patches({
        {
          target = post_effects,
          key = "apply_target",
          value = function(_, apply_user)
            count_at_apply = support.count_item(apply_user, item_ids.exile)
            return { ok = true }
          end,
        },
      }, function()
        local begin_result = use_flow.begin_item_use(g, user.id, item_ids.exile, { phase = "pre_action" })
        local choice = support.open_choice(g, begin_result.choice_spec)
        local result = use_flow.resolve_item_use_choice(g, choice, _select_action(choice, target.id, user.id))

        _assert_eq(result.ok, true, "target item resolve should apply")
        _assert_eq(result.item_consumed, true, "target item resolve should report consumed")
      end)

      _assert_eq(count_at_apply, 1, "target item must still be held while apply runs")
      _assert_eq(support.count_item(user, item_ids.exile), 0, "target item should be consumed after apply")
      _assert_eq(probes.item_card_popups, 0, "target item resolve should not display a card popup")
      _assert_eq(probes.item_used_events, 1, "target item resolve should report telemetry exactly once")
    end)

  -- 类别:目标玩家道具 · 路径:resolve,apply 失败(留卡、零广播)
    it("test_failed_target_apply_retains_the_item_and_never_broadcasts", function()
      local g = _new_game()
      local user = g.players[1]
      local target = g.players[2]
      local probes = _install_probes(g)
      user.inventory:add({ id = item_ids.exile })

      _with_patches({
        {
          target = post_effects,
          key = "apply_target",
          value = function()
            return { ok = false, reason = "blocked" }
          end,
        },
      }, function()
        local begin_result = use_flow.begin_item_use(g, user.id, item_ids.exile, { phase = "pre_action" })
        local choice = support.open_choice(g, begin_result.choice_spec)
        local result = use_flow.resolve_item_use_choice(g, choice, _select_action(choice, target.id, user.id))

        _assert_eq(result.ok, false, "failed target apply should reject")
        _assert_eq(result.reason, "blocked", "failed target apply reason")
        _assert_eq(result.item_consumed, false, "failed target apply must not report consumed")
      end)

      _assert_eq(support.count_item(user, item_ids.exile), 1, "failed target apply should retain the item")
      _assert_eq(probes.item_card_popups, 0, "failed target apply must not broadcast")
      _assert_eq(probes.item_used_events, 0, "failed target apply must not report telemetry")
    end)

  -- 类别:遥控骰子 · 路径:resolve(人类)
    it("test_remote_dice_resolve_consumes_exactly_one_card_without_card_popup", function()
      local g = _new_game()
      local user = g.players[1]
      local probes = _install_probes(g)
      user.inventory:add({ id = item_ids.remote_dice })

      local begin_result = use_flow.begin_item_use(g, user.id, item_ids.remote_dice, { phase = "pre_action" })
      _assert_eq(begin_result.status, "waiting_choice", "remote dice begin should wait")
      local choice = support.open_choice(g, begin_result.choice_spec)
      local result = use_flow.resolve_item_use_choice(g, choice, _select_action(choice, 4, user.id))

      _assert_eq(result.ok, true, "remote dice resolve should apply")
      _assert_eq(support.count_item(user, item_ids.remote_dice), 0, "remote dice should consume exactly one card")
      _assert_eq(probes.item_card_popups, 0, "remote dice resolve should not display a card popup")
      _assert_eq(probes.item_used_events, 1, "remote dice resolve should report telemetry exactly once")
    end)

  -- 类别:路障 · 路径:resolve(真实 roadblock.apply)
    it("test_roadblock_resolve_consumes_exactly_one_card_without_card_popup", function()
      local g = _new_game()
      local user = g.players[1]
      local probes = _install_probes(g)
      user.inventory:add({ id = item_ids.roadblock })

      local begin_result = use_flow.begin_item_use(g, user.id, item_ids.roadblock, { phase = "pre_action" })
      _assert_eq(begin_result.status, "waiting_choice", "roadblock begin should wait")
      local choice = support.open_choice(g, begin_result.choice_spec)
      local first_option = choice.options[1]
      local result = use_flow.resolve_item_use_choice(g, choice,
        _select_action(choice, first_option.id or first_option, user.id))

      _assert_eq(result.ok, true, "roadblock resolve should apply")
      _assert_eq(support.count_item(user, item_ids.roadblock), 0, "roadblock should consume exactly one card")
      _assert_eq(probes.item_card_popups, 0, "roadblock resolve should not display a card popup")
      _assert_eq(probes.item_used_events, 1, "roadblock resolve should report telemetry exactly once")
    end)

  -- 类别:拆除(怪兽) · 路径:resolve 漏斗(resolver 消耗先于 apply)
    it("test_demolish_resolve_consumes_before_apply_without_card_popup", function()
      local g = _new_game()
      local user = g.players[1]
      local probes = _install_probes(g)
      user.inventory:add({ id = item_ids.monster })
      local count_at_apply = nil

      _with_patches({
        {
          target = demolish,
          key = "apply",
          value = function(_, apply_player)
            count_at_apply = support.count_item(apply_player, item_ids.monster)
            return { ok = true }
          end,
        },
      }, function()
        local choice = support.open_choice(g, {
          kind = "demolish_target",
          options = { { id = 12, label = "目标" } },
          meta = { player_id = user.id, item_id = item_ids.monster },
        })
        local result = use_flow.resolve_item_use_choice(g, choice, _select_action(choice, 12, user.id))

        _assert_eq(result.ok, true, "demolish resolve should apply")
      end)

      _assert_eq(count_at_apply, 0, "demolish must be consumed before apply runs")
      _assert_eq(support.count_item(user, item_ids.monster), 0, "demolish should consume exactly one card")
      _assert_eq(probes.item_card_popups, 0, "demolish resolve should not display a card popup")
      _assert_eq(probes.item_used_events, 1, "demolish resolve should report telemetry exactly once")
    end)

  -- 类别:escrow 已入账 · 拒绝路径仍如实上报消耗(不退卡、不广播)
    it("test_escrowed_rejection_still_reports_the_card_as_consumed", function()
      local g = _new_game()
      local user = g.players[1]
      local probes = _install_probes(g)

      local settled = settlement.execute(g, user, item_ids.mine, function()
        return { ok = false, reason = "blocked" }
      end, { fallback_reason = "fallback", context_preconsumed = true })

      _assert_eq(settled.ok, false, "escrowed failure should reject")
      _assert_eq(settled.reason, "blocked", "effect reason passes through")
      _assert_eq(settled.item_consumed, true, "escrowed failure should stay consumed")
      _assert_eq(support.count_item(user, item_ids.mine), 0, "effect rejection must not refund the escrowed card")
      _assert_eq(probes.item_card_popups, 0, "rejection must not broadcast")
      _assert_eq(probes.item_used_events, 0, "rejection must not report telemetry")
    end)

  -- 类别:escrow 托管/退还 · settlement.escrow → settlement.abandon 直穿
    it("test_abandon_refunds_the_escrowed_card_exactly_once", function()
      local g = _new_game()
      local user = g.players[1]
      user.inventory:add({ id = item_ids.mine })

      local choice = support.open_choice(g, settlement.escrow(user, item_ids.mine, {
        kind = "item_target_player",
        options = { { id = g.players[2].id } },
      }))
      _assert_eq(support.count_item(user, item_ids.mine), 0, "escrow must consume the card")
      _assert_eq(choice.meta.item_preconsumed, true, "escrow must write the public cross-layer boolean")
      _assert_eq(choice.allow_cancel, false, "escrow must disable cancel")

      _assert_eq(settlement.abandon(g, choice, "test"), true, "first abandon should refund")
      _assert_eq(support.count_item(user, item_ids.mine), 1, "abandon must return the card to the bag")
      _assert_eq(settlement.abandon(g, choice, "test"), false, "second abandon must be a no-op")
      _assert_eq(support.count_item(user, item_ids.mine), 1, "idempotent abandon must not duplicate the card")
    end)

    it("test_abandon_honors_the_legacy_preconsume_boolean_and_flips_it_after_refund", function()
      local g = _new_game()
      local user = g.players[1]
      local choice = {
        meta = { item_preconsumed = true, item_id = item_ids.mine, player_id = user.id },
      }

      _assert_eq(settlement.abandon(g, choice, "test"), true, "legacy boolean escrow should refund")
      _assert_eq(support.count_item(user, item_ids.mine), 1, "legacy refund must return the card")
      _assert_eq(choice.meta.item_preconsumed, false, "refund must flip the legacy boolean")
      _assert_eq(settlement.abandon(g, choice, "test"), false, "flipped boolean must block a second refund")
    end)

    it("test_abandon_rejects_unrefundable_shapes_without_crashing", function()
      local g = _new_game()
      local user = g.players[1]

      _assert_eq(settlement.abandon(g, nil, "test"), false, "nil choice is not refundable")
      _assert_eq(settlement.abandon(g, { meta = {} }, "test"), false, "choice without escrow is not refundable")
      _assert_eq(settlement.abandon(g, {
        meta = { item_preconsumed = true },
      }, "test"), false, "escrow without item id is not refundable")
      _assert_eq(settlement.abandon(nil, {
        meta = { item_preconsumed = true, item_id = item_ids.mine, player_id = user.id },
      }, "test"), false, "unresolvable actor is not refundable")
    end)

  -- 类别:预消耗(非重复阶段) · 路径:begin_item_use + settlement.escrow → followup resolve
    it("test_preconsumed_followup_consumes_at_choice_open_and_resolves_without_double_consume", function()
      local g = _new_game()
      local user = g.players[1]
      local target = g.players[2]
      local probes = _install_probes(g)
      user.inventory:add({ id = item_ids.exile })

      _with_patches({
        {
          target = post_effects,
          key = "apply_target",
          value = function()
            return { ok = true }
          end,
        },
      }, function()
        local followup_spec = _open_preconsumed_followup(g, user, item_ids.exile, probes)

        _assert_eq(support.count_item(user, item_ids.exile), 0, "non-repeatable phase item must preconsume at choice open")
        _assert_eq(followup_spec.meta.item_preconsumed, true, "followup must carry preconsumed marker")
        _assert_eq(followup_spec.allow_cancel, false, "preconsumed followup must disable cancel")
        _assert_eq(probes.item_card_popups, 0, "preconsume must not broadcast before resolve")

        local choice = support.open_choice(g, followup_spec)
        local result = use_flow.resolve_item_use_choice(g, choice, _select_action(choice, target.id, user.id))

        _assert_eq(result.ok, true, "preconsumed followup resolve should apply")
        _assert_eq(result.item_consumed, true, "preconsumed followup should report consumed")
      end)

      _assert_eq(support.count_item(user, item_ids.exile), 0, "resolve must not consume a second card")
      _assert_eq(probes.item_card_popups, 0, "preconsumed resolve should not display a card popup")
      _assert_eq(probes.item_used_events, 1, "preconsumed resolve should report telemetry exactly once")
    end)

  -- 潜伏缺陷 #4(本 pin 起草时发现):旧偷窃卡在 apply 内部无条件自耗,
  -- 无视 item_preconsumed 标志——预消耗的偷窃 followup 在 resolve 时二次消耗,
  -- 命中 inventory.lua 的 missing item 断言直接崩溃。settlement 深化后偷窃
  -- 经台账 commit 自耗(escrow 已入账则空转),此组合自然修复。
    it("test_preconsumed_steal_followup_resolves_without_crashing", function()
      local g = _new_game()
      local user = g.players[1]
      local target = g.players[2]
      local probes = _install_probes(g)
      user.inventory:add({ id = item_ids.steal })
      target.inventory:add({ id = item_ids.mine })

      local followup_spec = _open_preconsumed_followup(g, user, item_ids.steal, probes)
      local choice = support.open_choice(g, followup_spec)
      local result = use_flow.resolve_item_use_choice(g, choice, _select_action(choice, target.id, user.id))

      _assert_eq(result.ok, true, "preconsumed steal resolve should apply")
      _assert_eq(support.count_item(user, item_ids.steal), 0, "steal must consume exactly one card in total")
      _assert_eq(support.count_item(user, item_ids.mine), 1, "stolen item should arrive")
    end)

  -- 类别:兜底动画 · 路径:apply 期间 action_anim_seq 推进,跳过二次排队
    it("test_skips_fallback_anim_when_action_anim_seq_advances_during_apply", function()
      local g = _new_game()
      local player = g.players[1]
      player.inventory:add({ id = item_ids.mine })
      local queued = false

      _with_patches({
        {
          target = action_anim_port,
          key = "is_enabled",
          value = function() return true end,
        },
        {
          target = action_anim_port,
          key = "queue",
          value = function() queued = true end,
        },
      }, function()
        local result = settlement.execute(g, player, item_ids.mine, function()
          g.turn.action_anim_seq = (g.turn.action_anim_seq or 0) + 1
          return { ok = true }
        end, {})

        _assert_eq(result.ok, true, "apply should succeed")
        _assert_eq(result.action_anim, nil, "fallback anim should be skipped when seq advanced")
        _assert_eq(queued, false, "anim should not be queued when seq advanced")
      end)
    end)

  -- 类别:已预 applied 道具 · 路径:count-diff 过渡,apply 后计数低于 preapplied_count
    it("test_marks_already_applied_item_consumed_when_count_drops_below_preapplied_count", function()
      local g = _new_game()
      local player = g.players[1]

      local result = settlement.execute(g, player, item_ids.mine, function()
        return { ok = true }
      end, { consume = "already_applied", preapplied_count = 1 })

      _assert_eq(result.ok, true, "apply should succeed")
      _assert_eq(result.item_consumed, true, "should report consumed when preapplied count dropped")
    end)

  -- 类别:escrow 退还 · 路径:背包已满导致 add 失败
    it("test_abandon_returns_false_when_inventory_cannot_accept_the_refund", function()
      local g = _new_game()
      local user = g.players[1]
      user.inventory:add({ id = item_ids.mine })
      while not user.inventory:is_full() do
        user.inventory:add({ id = item_ids.roadblock })
      end

      local choice = support.open_choice(g, settlement.escrow(user, item_ids.mine, {
        kind = "item_target_player",
        options = { { id = g.players[2].id } },
      }))
      -- escrow 消耗了一张卡,腾出一个格子;重新填满后退还失败
      user.inventory:add({ id = item_ids.roadblock })

      _assert_eq(settlement.abandon(g, choice, "test"), false, "abandon should fail when bag is full")
    end)

  -- 类别:兜底动画 · 路径:canonical.action_anim=false 视为未提供,继续排队
    it("test_queues_fallback_anim_when_canonical_action_anim_is_explicitly_false", function()
      local g = _new_game()
      local player = g.players[1]
      player.inventory:add({ id = item_ids.mine })
      local queued = false

      _with_patches({
        {
          target = action_anim_port,
          key = "is_enabled",
          value = function() return true end,
        },
        {
          target = action_anim_port,
          key = "queue",
          value = function() queued = true end,
        },
      }, function()
        local result = settlement.execute(g, player, item_ids.mine, function()
          return { ok = true, action_anim = false }
        end, {})

        _assert_eq(result.ok, true, "apply should succeed")
        _assert_eq(result.action_anim, true, "fallback anim should be queued")
        _assert_eq(queued, true, "anim should be queued")
      end)
    end)

  -- 类别:escrow 托管 · 路径:choice_spec 已携带 meta.item_id/player_id
    it("test_escrow_preserves_existing_meta_item_id_and_player_id", function()
      local g = _new_game()
      local user = g.players[1]
      user.inventory:add({ id = item_ids.mine })

      local choice = settlement.escrow(user, item_ids.mine, {
        kind = "item_target_player",
        options = { { id = g.players[2].id } },
        meta = { item_id = 9999, player_id = 8888 },
      })

      _assert_eq(choice.meta.item_id, 9999, "escrow should preserve existing item_id")
      _assert_eq(choice.meta.player_id, 8888, "escrow should preserve existing player_id")
    end)

  -- 类别:applier_owned · 路径:未 commit 但 escrow 已入账
    it("test_applier_owned_accepts_escrowed_items_without_explicit_commit", function()
      local g = _new_game()
      local user = g.players[1]

      local result = settlement.execute(g, user, item_ids.steal, function()
        return { ok = true }
      end, { consume = "applier_owned", context_preconsumed = true })

      _assert_eq(result.ok, true, "escrowed applier-owned item should apply")
      _assert_eq(result.item_consumed, true, "escrowed item should report consumed")
    end)
  end)
end
