local constants = require("src.config.content.constants")
local inventory = require("src.rules.items.inventory")
local item_ids = require("src.config.gameplay.item_ids")
local event_kinds = require("src.config.gameplay.event_kinds")
local timing = require("src.config.gameplay.timing")
local event_feed = require("src.rules.ports.event_feed")
local action_anim_port = require("src.foundation.ports.action_anim")
local number_utils = require("src.foundation.number")
local angel_feedback = require("src.rules.items.angel_feedback")
local target_cash_effects = require("src.rules.items.target_cash_effects")
local steal = require("src.rules.items.steal")
local demolish = require("src.rules.items.demolish")

local target_effects = {}
-- timing 是静态配置,action_anim_default_seconds 键恒在,`or 1.0` 是死防御(#259 删除)。
local action_anim_duration = timing.action_anim_default_seconds

-- 请神卡只请正面神灵：穷神持有者与无神灵者都不进候选面（deities_008/009/010）。
local invitable_deities = { rich = true, angel = true }

local target_item_order = {
  item_ids.steal,
  item_ids.missile,
  item_ids.share_wealth,
  item_ids.exile,
  item_ids.tax,
  item_ids.invite_deity,
  item_ids.send_poor,
  item_ids.poor,
}

local function _build_exile_log_entry(user, target)
  return user.name
    .. " 使用流放卡，将 "
    .. target.name
    .. " 送往深山，停留 "
    .. number_utils.format_integer_part(constants.mountain_stay_turns)
    .. " 回合"
end

local specs = {
  [item_ids.steal] = {
    filter_target = function(_, _, target)
      return inventory.count(target) > 0
    end,
    apply = function(game, user, target, context)
      return steal.steal_random_item(game, user, target, context and context.commit_item_use or nil)
    end,
  },
  [item_ids.missile] = {
    apply = function(game, user, target, context)
      -- 目标已验证，轰炸必定结算；先入消耗台账，避免同格使用者送医破产清包。
      if context and context.commit_item_use then
        context.commit_item_use()
      end
      return demolish.apply(game, user, target.position, {
        item_id = item_ids.missile,
        injure = true,
        title = "导弹卡",
      })
    end,
  },
  [item_ids.share_wealth] = target_cash_effects.share_wealth,
  [item_ids.exile] = {
    apply = function(game, user, target)
      if game:angel_immune_to_item(target, item_ids.exile) then
        angel_feedback.publish(game, target, "流放")
        return true
      end
      local idx = game.board:find_first_by_type("mountain")
      local from_index = target.position
      local queued = false
      local log_entry = _build_exile_log_entry(user, target)
      if idx then
        idx = game:player_relocate(target, {
          destination_index = idx,
          move_dir_mode = "clear",
        })
        queued = action_anim_port.queue(game, {
          kind = "teleport_effect",
          player_id = target.id,
          from_index = from_index,
          to_index = idx,
          duration = action_anim_duration,
        })
      end
      if queued then
        return {
          ok = true,
          action_anim = true,
          after_action_anim = {
            next_state = "move_followup",
            next_args = {
              mode = "apply_location_effects",
              log_entries = { log_entry },
              effects = {
                { player_id = target.id, effect = "mountain" },
              },
            },
          },
        }
      end
      event_feed.publish(game, {
        kind = event_kinds.item_used,
        text = log_entry,
      })
      game:player_apply_mountain_effects(target)
      return true
    end,
  },
  [item_ids.tax] = target_cash_effects.tax,
  [item_ids.invite_deity] = {
    filter_target = function(game, _, target)
      return invitable_deities[game:player_deity_type(target)] == true
    end,
    apply = function(game, user, target)
      local target_type = game:player_deity_type(target)
      game:transfer_deity(target, user)
      event_feed.publish(game, {
        kind = event_kinds.deity_evicted,
        text = user.name .. " 使用请神卡，从 " .. target.name .. " 请走 " .. target_type,
      })
      return true
    end,
  },
  [item_ids.send_poor] = {
    require_user = function(game, user)
      if not game:player_has_deity(user, "poor") then
        return false
      end
      return true
    end,
    apply = function(game, user, target)
      assert(game:player_has_deity(user, "poor"),
        "send_poor.apply: user must have effective poor deity")
      game:transfer_deity(user, target)
      event_feed.publish(game, {
        kind = event_kinds.deity_transferred,
        text = user.name .. " 使用送神卡，将穷神送给 " .. target.name,
      })
      return true
    end,
  },
  [item_ids.poor] = {
    apply = function(game, user, target)
      game:set_player_deity(target, "poor", constants.deity_duration_turns)
      event_feed.publish(game, {
        kind = event_kinds.deity_attached,
        text = user.name .. " 使用穷神卡，" .. target.name .. " 穷神附身",
      })
      return true
    end,
  },
}

function target_effects.get(item_id)
  return specs[item_id]
end

function target_effects.ids()
  return target_item_order
end

return target_effects

