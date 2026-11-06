require("test.bootstrap").install_package_paths()
-- luacheck: ignore 143 (busted injects the verified luassert object)
local luassert = assert
-- item_phase_passive 窗里选卡后打开跟随选择(followup)时，派发出去的 choice_spec.meta
-- 必须带上道具来源：item_id / player_id 只补缺不覆盖，passive_origin 恒为 true
-- (turn/optional_action_choice 据此把它认作道具跟随选择)，并记下被点的槽位。
-- 经 choice_handler_factory 的公共入口驱动，只替换注入的 begin_item_use 与
-- intent_output 出站端口。
local support = require("test.support.shared_support")
local choice_handler_factory = require("src.rules.choice_handlers.factory")
local intent_output_port = require("src.rules.ports.intent_output")

local SELECTED_ITEM_ID = 2005
local CLICKED_SLOT = 3

local function _open_followup(followup_choice_spec)
  local game = support.new_game()
  local player = game.players[1]
  player.inventory:add({ id = SELECTED_ITEM_ID })
  local handlers = choice_handler_factory.build_item_handlers({
    finish_choice = function(_, stay)
      return { stay = stay == true }
    end,
    finish_active_item_phase = function() end,
    begin_item_use = function()
      return { ok = true, waiting = true, intent = { kind = "need_choice", choice_spec = followup_choice_spec } }
    end,
  })
  local dispatched
  local result
  support.with_patches({
    { target = intent_output_port, key = "dispatch", value = function(_, intent)
        dispatched = intent
        return true
      end },
  }, function()
    result = handlers.item_phase_passive.execute(game, {
      kind = "item_phase_passive",
      meta = { player_id = player.id, phase = "pre_action", resume_next_state = "roll" },
    }, { option_id = SELECTED_ITEM_ID, slot_index = CLICKED_SLOT })
  end)
  return result, dispatched, player
end

describe("TestItemPhaseHandlersFollowupMeta", function()
  it("test_a_followup_without_meta_is_stamped_with_the_item_origin", function()
    local result, dispatched, player = _open_followup({ kind = "remote_dice_value" })
    luassert.is_true(result.stay, "the item phase window keeps waiting on the followup")
    local meta = dispatched.choice_spec.meta
    luassert.is.equal(SELECTED_ITEM_ID, meta.item_id, "the selected item id is attached")
    luassert.is.equal(player.id, meta.player_id, "the acting player id is attached")
    luassert.is.equal(true, meta.passive_origin, "the followup is marked as an item usage followup")
    luassert.is.equal(CLICKED_SLOT, meta.item_slot_index, "the clicked slot is remembered for settlement")
    luassert.is.equal("pre_action", meta.phase, "the phase is carried for resuming the window")
  end)

  it("test_a_followup_keeps_its_own_meta_fields", function()
    local _, dispatched = _open_followup({
      kind = "remote_dice_value",
      meta = { item_id = 9001, player_id = 999, dice_count = 2 },
    })
    local meta = dispatched.choice_spec.meta
    luassert.is.equal(9001, meta.item_id, "an item id set by the followup is not overwritten")
    luassert.is.equal(999, meta.player_id, "a player id set by the followup is not overwritten")
    luassert.is.equal(2, meta.dice_count, "followup-specific meta survives the decoration")
    luassert.is.equal(true, meta.passive_origin, "the followup is still marked as an item usage followup")
  end)
end)
