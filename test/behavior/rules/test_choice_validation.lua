require("test.bootstrap").install_package_paths()
local luassert = require("luassert")
local support = require("test.support.shared_support")
local _new_game = support.new_game
local item_preconsume_policy = require("src.rules.choice.item_preconsume_policy")
local choice_handler_factory = require("src.rules.choice_handlers.factory")
local item_slot_click = require("src.turn.actions.item_slot_click")
local availability = require("src.rules.items.availability")
local logger = require("src.foundation.log")

-- 道具槽的选项 / 可用性校验统一住 item_slot_click.resolve：展示层只报「谁点了第几个
-- 槽」，槽位 → 道具直读行动者背包，活道具窗从 turn.pending_choice 取。
-- 这里只构造刚好够裁定走到选项 / 可用性分支的 game：行动者即当前回合玩家，
-- 窗归属行动者（否则会先撞 not_current_turn / no_item_window）。
local function _item_slot_game(choice, item_id)
  local player = { id = 1, inventory = { items = { { id = item_id } } } }
  local game = {
    players = { player },
    turn = { current_player_index = 1, pending_choice = choice },
    tip_output_port = { enqueue = function() return true end },
  }
  function game:find_player_by_id(role_id)
    return role_id == player.id and player or nil
  end
  return game
end

local function _click_first_slot(choice, item_id)
  return item_slot_click.resolve(_item_slot_game(choice, item_id), {
    type = "item_slot_click",
    slot_index = 1,
    actor_role_id = 1,
  })
end

local function _item_window(options, meta)
  return {
    id = 21,
    kind = "item_phase_passive",
    owner_role_id = 1,
    options = options,
    meta = meta,
  }
end

local _item_choice_handler_t2_tests = {
  function()
    local seen = {}
    local result = item_preconsume_policy.each_option({
      options = {
        { id = "opt1", label = "A" },
        "opt2",
        { label = "ignored" },
      },
    }, function(option, option_id, index)
      seen[#seen + 1] = {
        option = option,
        option_id = option_id,
        index = index,
      }
    end)
    luassert.truthy(result == nil, "each_option should return nil when the visitor never stops iteration")
    luassert.truthy(seen[1].option_id == "opt1", "each_option should expose the first table option id")
    luassert.truthy(seen[2].option_id == "opt2", "each_option should expose string options directly")
    luassert.truthy(seen[3].option_id == seen[3].option, "each_option should fall back to the raw option when id is missing")
  end,
  function()
    local seen = {}
    local result = item_preconsume_policy.each_option({
      options = {
        { id = "opt1" },
        "opt2",
        { id = "opt3" },
      },
    }, function(option, option_id, index)
      seen[#seen + 1] = {
        option = option,
        option_id = option_id,
        index = index,
      }
      if index == 2 then
        return option_id
      end
    end)
    luassert.truthy(result == "opt2", "each_option should stop when the visitor returns a value")
    luassert.truthy(#seen == 2, "each_option should stop visiting after a non-nil return")
  end,
  function()
    luassert.truthy(item_preconsume_policy.is_cancel_action({ type = "choice_cancel" }) == true,
      "is_cancel_action should accept choice_cancel")
    luassert.truthy(item_preconsume_policy.is_cancel_action({ type = "choice_select" }) == false,
      "is_cancel_action should reject non-cancel actions")
    luassert.truthy(item_preconsume_policy.is_cancel_action(nil) == false,
      "is_cancel_action should reject nil actions")
  end,
  function()
    local decorated = item_preconsume_policy.decorate_followup_choice_spec(nil, {
      item_id = 2005,
      player_id = 7,
    })
    luassert.truthy(decorated == nil, "decorate_followup_choice_spec should return nil choice_spec unchanged")
  end,
  function()
    local choice_spec = {
      allow_cancel = true,
      cancel_label = "返回",
    }
    local decorated = item_preconsume_policy.decorate_followup_choice_spec(choice_spec, nil)
    luassert.truthy(decorated == choice_spec, "decorate_followup_choice_spec should mutate and return the original choice_spec")
    luassert.truthy(choice_spec.allow_cancel == false, "decorate_followup_choice_spec should disable cancel")
    luassert.truthy(choice_spec.cancel_label == nil, "decorate_followup_choice_spec should clear cancel label")
    luassert.truthy(choice_spec.meta.item_preconsumed == true, "decorate_followup_choice_spec should mark item_preconsumed")
  end,
  function()
    local choice_spec = {
      allow_cancel = true,
      cancel_label = "返回",
    }
    local meta = item_preconsume_policy.ensure_followup_meta(choice_spec)
    luassert.truthy(meta == choice_spec.meta, "ensure_followup_meta should return the choice meta table")
    luassert.truthy(meta.item_preconsumed == true, "ensure_followup_meta should mark item_preconsumed")

    item_preconsume_policy.disable_followup_cancel(choice_spec)
    luassert.truthy(choice_spec.allow_cancel == false, "disable_followup_cancel should disable cancel")
    luassert.truthy(choice_spec.cancel_label == nil, "disable_followup_cancel should clear cancel label")

    item_preconsume_policy.merge_preconsume_context(meta, {
      item_id = 2005,
      player_id = 7,
    })
    luassert.truthy(meta.item_id == 2005, "merge_preconsume_context should backfill item_id")
    luassert.truthy(meta.player_id == 7, "merge_preconsume_context should backfill player_id")

    item_preconsume_policy.merge_preconsume_context(meta, {
      item_id = 9001,
      player_id = 77,
    })
    luassert.truthy(meta.item_id == 2005, "merge_preconsume_context should not overwrite item_id")
    luassert.truthy(meta.player_id == 7, "merge_preconsume_context should not overwrite player_id")
  end,
  function()
    local choice_spec = {
      meta = {
        item_id = 9001,
        player_id = 77,
      },
    }
    item_preconsume_policy.decorate_followup_choice_spec(choice_spec, {
      item_id = 2005,
      player_id = 7,
    })
    luassert.truthy(choice_spec.meta.item_preconsumed == true, "decorate_followup_choice_spec should keep preconsumed marker")
    luassert.truthy(choice_spec.meta.item_id == 9001, "decorate_followup_choice_spec should not overwrite existing item_id")
    luassert.truthy(choice_spec.meta.player_id == 77, "decorate_followup_choice_spec should not overwrite existing player_id")
  end,
  function()
    local game = _new_game()
    local player = game.players[1]
    local captured_choice_spec = nil
    player.inventory:add({ id = 2005 })
    local handlers = choice_handler_factory.build_item_handlers({
      finish_choice = function(_, stay)
        return { stay = stay == true }
      end,
      finish_active_item_phase = function() end,
      begin_item_use = function(_, _, item_id)
        luassert.truthy(item_id == 2005, "item_phase_passive should forward selected item_id")
        return {
          ok = true,
          waiting = true,
          intent = {
            choice_spec = {
              kind = "remote_dice_value",
              allow_cancel = false,
              cancel_label = "old",
              meta = {
                player_id = 999,
              },
            },
          },
        }
      end,
    })
    local original_dispatch = require("src.rules.ports.intent_output").dispatch
    require("src.rules.ports.intent_output").dispatch = function(_, intent)
      captured_choice_spec = intent and intent.choice_spec or nil
      return true
    end

    local ok, result = pcall(function()
      return handlers.item_phase_passive.execute(game, {
        kind = "item_phase_passive",
        meta = {
          player_id = player.id,
          phase = "pre_action",
          resume_next_state = "roll",
          resume_next_args = { player_id = player.id },
        },
      }, {
        option_id = 2005,
      })
    end)

    require("src.rules.ports.intent_output").dispatch = original_dispatch

    luassert.truthy(ok, result)
    luassert.truthy(result and result.stay == true, "repeatable item phase should keep waiting when followup choice opens")
    luassert.truthy(captured_choice_spec ~= nil, "repeatable item phase should dispatch followup choice")
    luassert.truthy(captured_choice_spec.allow_cancel == true, "repeatable followup should stay cancelable")
    luassert.truthy(captured_choice_spec.cancel_label == "old", "repeatable followup should preserve existing cancel label")
    luassert.truthy(captured_choice_spec.meta.phase == "pre_action", "repeatable followup should preserve phase meta")
    luassert.truthy(captured_choice_spec.meta.item_id == 2005, "repeatable followup should attach selected item_id")
    luassert.truthy(captured_choice_spec.meta.player_id == 999, "repeatable followup should not overwrite existing player_id")
    luassert.truthy(captured_choice_spec.meta.passive_origin == true, "passive followup should mark passive_origin")
  end,
}

local function _crap_assert_eq(a, b, msg)
  luassert.is.equal(b, a, msg)
end

local function _with_patched_dependencies(overrides, fn)
  local orig_warn = logger.warn
  local orig_can_offer = availability.can_offer_in_phase

  logger.warn = overrides.warn or orig_warn
  availability.can_offer_in_phase = overrides.can_offer_in_phase or orig_can_offer

  local ok, result = pcall(fn)

  logger.warn = orig_warn
  availability.can_offer_in_phase = orig_can_offer

  if not ok then
    error(result, 2)
  end
  return result
end

describe("TestChoicesValidation", function()
it("test_item_preconsume_each_option_iterates_without_return", function()
  _item_choice_handler_t2_tests[1]()
end)

it("test_item_preconsume_each_option_stops_on_return", function()
  _item_choice_handler_t2_tests[2]()
end)

it("test_item_preconsume_is_cancel_action_recognizes_choice_cancel", function()
  _item_choice_handler_t2_tests[3]()
end)

it("test_item_preconsume_returns_nil_choice_spec_unchanged", function()
  _item_choice_handler_t2_tests[4]()
end)

it("test_item_preconsume_marks_choice_spec_and_disables_cancel", function()
  _item_choice_handler_t2_tests[5]()
end)

it("test_item_preconsume_followup_helpers_mark_disable_and_backfill_meta", function()
  _item_choice_handler_t2_tests[6]()
end)

it("test_item_preconsume_preserves_existing_context_fields", function()
  _item_choice_handler_t2_tests[7]()
end)

it("test_item_phase_passive_decorates_repeatable_followup_meta", function()
  _item_choice_handler_t2_tests[8]()
end)

-- 窗里已经 offer 了这张卡就是放行的充要条件：可用性判定是 offer 的前置，
-- 裁定不再复查一遍（缺 phase 的窗也不该把已 offer 的卡挡下来）。
it("test_item_slot_click_offered_option_selects_without_consulting_availability", function()
  _with_patched_dependencies({
    can_offer_in_phase = function()
      error("offered option must not be re-checked against availability")
    end,
  }, function()
    local choice = _item_window({ { id = "item_123" } }, {})

    local result = _click_first_slot(choice, "item_123")
    _crap_assert_eq(result.status, "select", "offered option is admitted")
    _crap_assert_eq(result.action.option_id, "item_123", "admitted option comes from the clicked slot")
    _crap_assert_eq(result.action.choice_id, 21, "admitted action targets the open window")
  end)
end)

-- 卡不在 offer 里就不放行；窗连 phase 都没有时拒因分类不出，走 unknown 并留 warn，
-- 绝不冒充一个具体拒因。
it("test_item_slot_click_option_missing_from_window_denies_as_unknown", function()
  local warned = 0
  _with_patched_dependencies({
    warn = function()
      warned = warned + 1
    end,
    can_offer_in_phase = function()
      error("phaseless window must not reach availability")
    end,
  }, function()
    local choice = _item_window({ { id = "item_123" } }, nil)

    local result = _click_first_slot(choice, "item_999")
    _crap_assert_eq(result.status, "denied", "option missing from window is denied")
    _crap_assert_eq(result.reason, "unknown", "unclassifiable denial stays unknown")
    _crap_assert_eq(warned, 1, "phaseless window is warned once")
  end)
end)

-- 拒因由 rules 的可用性判定给出，且它必须拿到解析出的行动者、点中的道具与窗的阶段。
it("test_item_slot_click_availability_denial_denies_with_its_reason", function()
  _with_patched_dependencies({
    can_offer_in_phase = function(_, actor, item_id, phase)
      _crap_assert_eq(actor.id, 1, "availability receives resolved actor")
      _crap_assert_eq(item_id, "item_123", "availability receives selected item")
      _crap_assert_eq(phase, "pre_move", "availability receives phase")
      return false, "insufficient_funds"
    end,
  }, function()
    local choice = _item_window({ { id = "item_other" } }, { phase = "pre_move" })

    local result = _click_first_slot(choice, "item_123")
    _crap_assert_eq(result.status, "denied", "availability denial is not admitted")
    _crap_assert_eq(result.reason, "insufficient_funds", "denial reason comes from availability")
  end)
end)


end)
