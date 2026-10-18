local choice_support = require("src.ui.view.choice_support")
local runtime_state = require("src.ui.state.runtime")
local pending_confirmation = require("src.ui.state.pending_confirmation")
local modal_ports = require("src.ui.input.modal_ports")
local highlight_lifecycle = require("src.ui.state.item_slot_highlight_lifecycle_queue")

local item_phase_ask_flow = {}

local function _close_choice_modal(state)
  modal_ports.close_choice_modal(state)
end

-- option 可以是 { id = ... } 也可以直接是裸 id。
local function _option_id(opt)
  return type(opt) == "table" and opt.id or opt
end

-- 折叠一个 option id 到累计值，返回 (累计值, 是否冲突)。
-- 冲突 = 出现了第二个与已累计值不同的 id。
local function _merge_option_id(option_id, current_id)
  if option_id == nil then
    return current_id, false
  end
  if option_id ~= current_id then
    return nil, true
  end
  return option_id, false
end

-- 所有 option 都指向同一个 id 时返回该 id，否则 nil。
local function _resolve_single_option_id(choice)
  if type(choice) ~= "table" or type(choice.options) ~= "table" then
    return nil
  end
  local option_id = nil
  for _, opt in ipairs(choice.options) do
    local conflict
    option_id, conflict = _merge_option_id(option_id, _option_id(opt))
    if conflict then
      return nil
    end
  end
  return option_id
end

local function _dispatch_single_pre_confirm_option(game, state, choice, intent, opts, action_port)
  if not choice_support.requires_item_slot_pre_confirm(choice) then
    return
  end
  local opt_id = _resolve_single_option_id(choice)
  if opt_id == nil then
    return
  end
  action_port.dispatch_action(game, state, {
    type = "choice_select",
    choice_id = choice.id,
    option_id = opt_id,
    actor_role_id = intent.actor_role_id,
  }, opts)
end

local function _handle_choice_select(state, game, intent, opts, action_port)
  pending_confirmation.confirm(state)
  local choice = runtime_state.get_ui_model_choice(state)
  -- #595:确认要带上「是哪个选择」,否则后续的迟到关闭无从匹配。
  highlight_lifecycle.push(state, "confirm_item_use", choice and choice.id or nil)
  if choice ~= nil then
    _dispatch_single_pre_confirm_option(game, state, choice, intent, opts, action_port)
  end
  _close_choice_modal(state)
  return true
end

local function _handle_choice_cancel(state, game, intent, opts, action_port)
  pending_confirmation.cancel(state)
  -- #595:关闭必须说明关的是哪个选择。旧口径只是清掉扁平旗标,刷新层遂把它
  -- 误读成槽位命令而无条件解冻——迟到的旧选择关闭会解除新选择的冻结(场景 017)。
  -- 取消/结束/替换在 ui.state 侧统一归一为 choice_released(场景 018)。
  -- 关窗前先读:_close_choice_modal 之后 ui_model 上的待决选择可能已经消失。
  local choice = runtime_state.get_ui_model_choice(state)
  highlight_lifecycle.push(state, "choice_released", choice and choice.id or nil)
  _close_choice_modal(state)
  if choice and choice.id then
    action_port.dispatch_action(game, state, {
      type = "choice_cancel",
      choice_id = choice.id,
      actor_role_id = intent.actor_role_id,
    }, opts)
  end
  return true
end

local INTENT_HANDLERS = {
  choice_select = _handle_choice_select,
  choice_cancel = _handle_choice_cancel,
}

function item_phase_ask_flow.dispatch(state, game, intent, opts, action_port)
  if not pending_confirmation.is_source_active(state, pending_confirmation.SOURCE_ITEM_PHASE_ASK) then
    return false
  end
  local handler = INTENT_HANDLERS[intent and intent.type]
  return handler and handler(state, game, intent, opts, action_port) or false
end

return item_phase_ask_flow

