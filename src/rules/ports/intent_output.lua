local intent_output = {}
local contract_helper = require("src.rules.ports.contract_helper")

local function _call_optional(game, method_name, default_result, ...)
  return contract_helper.call_optional_method(game, "intent_output_port", method_name, {
    default_result = default_result,
  }, ...)
end

function intent_output.open_choice(game, choice_spec, opts)
  return _call_optional(game, "open_choice", nil, game, choice_spec, opts)
end

function intent_output.push_popup(game, payload, opts)
  return _call_optional(game, "push_popup", false, game, payload, opts)
end

-- payload 可以是 intent 本身,也可以是包着 intent 的信封;非表一律不认。
local function _resolve_intent(payload)
  if type(payload) ~= "table" then
    return nil
  end
  local intent = payload.intent or payload
  if type(intent) ~= "table" then
    return nil
  end
  return intent
end

local function _choice_intent(intent)
  return intent.kind == "need_choice" and intent.choice_spec
end

local function _popup_intent(intent)
  return intent.kind == "push_popup" and intent.payload
end

local function _popup_opts_of(intent, opts)
  return intent.popup_opts or intent.opts or opts
end

function intent_output.dispatch(game, payload, opts)
  local intent = _resolve_intent(payload)
  if intent == nil then
    return nil
  end
  if _choice_intent(intent) then
    return intent_output.open_choice(game, intent.choice_spec, opts)
  end
  if _popup_intent(intent) then
    return intent_output.push_popup(game, intent.payload, _popup_opts_of(intent, opts))
  end
  return nil
end

return intent_output

