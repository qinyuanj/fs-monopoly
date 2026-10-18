local logger = require("src.foundation.log")
local availability = require("src.rules.items.availability")
local denial_tip = require("src.turn.actions.item_slot_denial_tip")

local item_slot_denial = {}

local function _option_id(option)
  return type(option) == "table" and option.id or option
end

function item_slot_denial.choice_offers_item(choice, item_id)
  local options = choice.options
  if type(options) ~= "table" then
    return false
  end
  for _, option in ipairs(options) do
    if _option_id(option) == item_id then
      return true
    end
  end
  return false
end

-- 卡在窗里没被 offer 的具体原因由 rules 的可用性判定给出；判不出（ok / 未知）
-- 属设计不可达，走通用文案并留 warn。
local function _phase_of(choice)
  return choice.meta and choice.meta.phase or nil
end

local function _invalid_phase(phase)
  return type(phase) ~= "string" or phase == ""
end

function item_slot_denial.unavailable_reason(game, actor, choice, item_id)
  local phase = _phase_of(choice)
  if _invalid_phase(phase) then
    logger.warn("item slot window without phase:", tostring(choice.id), tostring(item_id))
    return "unknown"
  end
  local can_offer, deny_reason = availability.can_offer_in_phase(game, actor, item_id, phase)
  if can_offer then
    logger.warn("item slot missing from options while offerable:", tostring(item_id), tostring(phase))
    return "unknown"
  end
  return deny_reason or "unknown"
end

function item_slot_denial.deny(game, actor_role_id, item_id, reason)
  denial_tip.emit(game, actor_role_id, item_id, reason)
  return { status = "denied", reason = reason }
end

return item_slot_denial

