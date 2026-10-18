local logger = require("src.foundation.log")
local runtime_state = require("src.ui.state.runtime")
local modal_state = require("src.ui.state.modal")

local intents = {}

local function _resolve_option_id_from_payload(payload)
  return payload.option_id
end

local function _resolve_index_from_payload(payload)
  return payload.index
end

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
  local option_id = _resolve_option_id_from_payload(payload)
  if option_id then
    return option_id
  end
  local index = _resolve_index_from_payload(payload)
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

--[[ mutate4lua-manifest
version=4
projectHash=f26ecdcd20a0f420
scope.0.id=chunk:src/ui/input/event_intents.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=115
scope.0.semanticHash=b6be3e1d9af7e851
scope.1.id=function:_resolve_option_id_from_payload
scope.1.kind=function
scope.1.startLine=7
scope.1.endLine=9
scope.1.semanticHash=58edf350ecb7da5e
scope.2.id=function:_resolve_index_from_payload
scope.2.kind=function
scope.2.startLine=11
scope.2.endLine=13
scope.2.semanticHash=749d97117f212ae2
scope.3.id=function:_resolve_mapped_from_runtime
scope.3.kind=function
scope.3.startLine=15
scope.3.endLine=20
scope.3.semanticHash=d599aca6af000405
scope.4.id=function:_resolve_option_by_index
scope.4.kind=function
scope.4.startLine=22
scope.4.endLine=32
scope.4.semanticHash=049c17ed57af93e9
scope.5.id=function:_resolve_option_id_by_index
scope.5.kind=function
scope.5.startLine=35
scope.5.endLine=41
scope.5.semanticHash=a3afc98b704081ab
scope.6.id=function:intents.resolve_option_id
scope.6.kind=function
scope.6.startLine=43
scope.6.endLine=55
scope.6.semanticHash=b791a829d473dbea
scope.7.id=function:_resolve_choice_or_warn
scope.7.kind=function
scope.7.startLine=57
scope.7.endLine=64
scope.7.semanticHash=4e08e81d9e65eeea
scope.8.id=function:intents.choice_cancel_intent
scope.8.kind=function
scope.8.startLine=66
scope.8.endLine=75
scope.8.semanticHash=c59624c723426db6
scope.9.id=function:intents.choice_select_intent
scope.9.kind=function
scope.9.startLine=77
scope.9.endLine=92
scope.9.semanticHash=8514bca047d6de1b
scope.10.id=function:intents.choice_confirm_intent
scope.10.kind=function
scope.10.startLine=94
scope.10.endLine=112
scope.10.semanticHash=0d20c98d7850268c
]]
