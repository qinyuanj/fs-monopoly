local logger = require("src.foundation.log")
local runtime_state = require("src.ui.state.runtime")
local modal_state = require("src.ui.state.modal")

local intents = {}

local function _resolve_mapped_from_runtime(state, index)
  if state == nil then
    return nil
  end
  return modal_state.get_visible_option_id(state, index)
end

local function _resolve_option_by_index(choice, index)
  local options = choice.options
  if type(options) ~= "table" then
    return nil
  end
  local option = options[index]
  if option then
    return option.id or option
  end
  return nil
end

-- 按 index 取 option：优先用运行时记下的可见槽位映射，回落到 choice.options。
local function _resolve_option_id_by_index(choice, index, state)
  local mapped = _resolve_mapped_from_runtime(state, index)
  if mapped then
    return mapped
  end
  return _resolve_option_by_index(choice, index)
end

function intents.resolve_option_id(choice, payload, state)
  assert(choice ~= nil, "missing choice")
  assert(payload ~= nil, "missing payload")
  local option_id = payload.option_id
  if option_id then
    return option_id
  end
  local index = payload.index
  if index then
    return _resolve_option_id_by_index(choice, index, state)
  end
  return nil
end

local function _resolve_choice_or_warn(state, warn_label)
  local current_model = runtime_state.get_ui_model(state)
  local choice = current_model and current_model.choice or nil
  if not choice then
    logger.warn(warn_label .. " without choice")
  end
  return choice
end

function intents.choice_cancel_intent(state, warn_label)
  local choice = _resolve_choice_or_warn(state, warn_label)
  if not choice then
    return nil
  end
  if choice.allow_cancel == false then
    return nil
  end
  return { type = "choice_cancel", choice_id = choice.id }
end

function intents.choice_select_intent(state, index, warn_label)
  local choice = _resolve_choice_or_warn(state, warn_label)
  if not choice then
    return nil
  end
  local option_id = intents.resolve_option_id(choice, { index = index }, state)
  if not option_id then
    logger.warn(warn_label .. " missing option:", tostring(index))
    return nil
  end
  return {
    type = "choice_select",
    choice_id = choice.id,
    option_id = option_id,
  }
end

function intents.choice_confirm_intent(state, warn_label)
  local choice = _resolve_choice_or_warn(state, warn_label)
  if not choice then
    return nil
  end
  local option_id = modal_state.get_selected_option_id(state)
  if option_id == nil then
    option_id = modal_state.get_visible_option_id(state, 1)
  end
  if option_id == nil then
    logger.warn(warn_label .. " missing selected option")
    return nil
  end
  return {
    type = "choice_select",
    choice_id = choice.id,
    option_id = option_id,
  }
end

return intents

