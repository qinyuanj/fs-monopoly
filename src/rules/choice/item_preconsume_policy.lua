local item_preconsume_policy = {}

-- option 既可能是 { id = ... } 表,也可能是裸 id。
local function _option_id_of(option)
  return type(option) == "table" and option.id or option
end

function item_preconsume_policy.is_cancel_action(action)
  return action ~= nil and action.type == "choice_cancel"
end

local function _options_of(choice)
  return choice and choice.options or nil
end

function item_preconsume_policy.each_option(choice, visitor)
  local options = _options_of(choice)
  if type(options) ~= "table" then
    return nil
  end
  for index, option in ipairs(options) do
    local option_id = _option_id_of(option)
    local result = visitor(option, option_id, index)
    if result ~= nil then
      return result
    end
  end
  return nil
end

function item_preconsume_policy.is_preconsumed(choice)
  return choice ~= nil and choice.meta ~= nil and choice.meta.item_preconsumed == true
end

function item_preconsume_policy.first_option_id(choice)
  return item_preconsume_policy.each_option(choice, function(_, option_id)
    return option_id
  end)
end

local function _build_fallback_select(choice, action, option_id)
  return {
    type = "choice_select",
    choice_id = choice and choice.id or nil,
    option_id = option_id,
    actor_role_id = action and action.actor_role_id or nil,
  }
end

function item_preconsume_policy.normalize_cancel_action(choice, action)
  if not item_preconsume_policy.is_cancel_action(action) then
    return action
  end
  if not item_preconsume_policy.is_preconsumed(choice) then
    return action
  end
  local fallback_option_id = item_preconsume_policy.first_option_id(choice)
  if fallback_option_id == nil then
    return action
  end
  return _build_fallback_select(choice, action, fallback_option_id)
end

function item_preconsume_policy.disable_followup_cancel(choice_spec)
  if type(choice_spec) ~= "table" then
    return choice_spec
  end
  choice_spec.allow_cancel = false
  choice_spec.cancel_label = nil
  return choice_spec
end

function item_preconsume_policy.ensure_followup_meta(choice_spec)
  if type(choice_spec) ~= "table" then
    return nil
  end
  choice_spec.meta = choice_spec.meta or {}
  choice_spec.meta.item_preconsumed = true
  return choice_spec.meta
end

-- 只在 context 带值、且 meta 尚未落过该字段时补写(既有值优先)。
local function _fill_missing_field(meta, key, value)
  if value ~= nil then
    meta[key] = meta[key] or value
  end
end

function item_preconsume_policy.merge_preconsume_context(meta, context)
  if type(meta) ~= "table" then
    return meta
  end
  local ctx = context or {}
  _fill_missing_field(meta, "item_id", ctx.item_id)
  _fill_missing_field(meta, "player_id", ctx.player_id)
  return meta
end

-- force_skip 等放弃路径的退还入口:薄适配到结算台账(惰性 require,
-- settlement 不得反向依赖本 policy)。
function item_preconsume_policy.refund(game, choice)
  local settlement = require("src.rules.items.settlement")
  -- #293:abandon 忽略第三参(签名 `(game, choice, _)`),label 是死参数,
  -- 等价变异体处置——删冗余。
  return settlement.abandon(game, choice)
end

function item_preconsume_policy.decorate_followup_choice_spec(choice_spec, context)
  if type(choice_spec) ~= "table" then
    return choice_spec
  end
  item_preconsume_policy.disable_followup_cancel(choice_spec)
  local meta = item_preconsume_policy.ensure_followup_meta(choice_spec)
  item_preconsume_policy.merge_preconsume_context(meta, context)
  return choice_spec
end

return item_preconsume_policy

