local card_choice = require("src.rules.land.settlement_card_choice")
local effect_choice = require("src.rules.land.settlement_effect_choice")
local landing = require("src.rules.land.settlement_landing")
local shared = require("src.rules.land.settlement_shared")

local settlement = {}

function settlement.begin_landing_settlement(game, actor_id, context)
  return landing.begin_landing_settlement(game, actor_id, context)
end

local function _kind_of(choice)
  return choice and choice.kind or nil
end

function settlement.resolve_landing_settlement_choice(game, choice, action)
  local kind = _kind_of(choice)
  if kind == "landing_optional_effect" then
    return effect_choice.resolve(game, choice, action)
  end
  if kind == "rent_card_prompt" then
    return card_choice.resolve_rent(game, choice, action)
  end
  if kind == "tax_card_prompt" then
    return card_choice.resolve_tax(game, choice, action)
  end
  return shared.reject("not_landing_choice")
end

settlement._M_test = {
  _has_pending_relocation_action_anim = landing._M_test._has_pending_relocation_action_anim,
  _option_is_offered = effect_choice._M_test._option_is_offered,
}

return settlement

