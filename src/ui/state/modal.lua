local modal_state = {}
local runtime_state = require("src.ui.state.runtime")
local panel_interrupt = require("src.ui.state.panel_interrupt")
local role_id_utils = require("src.foundation.identity")

local function _ui_runtime(state)
  return runtime_state.ensure_ui_runtime(state)
end

function modal_state.open_choice(state, choice_id, option_ids, selected_option_id)
  assert(state ~= nil, "missing state")
  runtime_state.set_pending_choice_elapsed(state, 0)
  runtime_state.set_pending_choice_id(state, choice_id)
  local ui_runtime = _ui_runtime(state)
  ui_runtime.choice_visible_option_ids = option_ids
  ui_runtime.pending_choice_selected_option_id = selected_option_id
end

modal_state.open_market = modal_state.open_choice

function modal_state.select_choice_option(state, option_id)
  assert(state ~= nil, "missing state")
  local ui_runtime = _ui_runtime(state)
  ui_runtime.pending_choice_selected_option_id = option_id
  runtime_state.set_ui_dirty(state, true)
end

modal_state.select_market_option = modal_state.select_choice_option

function modal_state.close_choice(state)
  assert(state ~= nil, "missing state")
  local ui_runtime = _ui_runtime(state)
  ui_runtime.choice_visible_option_ids = nil
  ui_runtime.pending_choice_selected_option_id = nil
end

-- 「待确认选项」的读取口：其它模块不再直接翻 ui_runtime 字段。
function modal_state.get_selected_option_id(state)
  assert(state ~= nil, "missing state")
  return _ui_runtime(state).pending_choice_selected_option_id
end

function modal_state.get_visible_option_id(state, index)
  assert(state ~= nil, "missing state")
  local option_ids = _ui_runtime(state).choice_visible_option_ids
  if type(option_ids) ~= "table" then
    return nil
  end
  return option_ids[index]
end

-- 当前激活的选择屏 key（由 coord 层开屏/关屏时写入 state.ui）。
function modal_state.get_active_choice_screen_key(state)
  local ui = state and state.ui or nil
  return ui and ui.active_choice_screen_key or nil
end

local function _model_current_role_id(state)
  local model = runtime_state.get_ui_model(state)
  return model and role_id_utils.normalize(model.current_player_id) or nil
end

-- 操作者 role 的唯一读取口:行动中的 role 优先,否则回退到模型侧当前玩家。
function modal_state.operator_role_id(state)
  local ui = state and state.ui
  if not ui then
    return nil
  end
  if ui.current_action_role_id ~= nil then
    return ui.current_action_role_id
  end
  return _model_current_role_id(state)
end

-- 载荷落旗标(CRAP 门禁):payload 派生的四个字段收敛到本函数,
-- open_popup 只留断言、dirty 标记与面板打断。
local function _apply_popup_payload(ui, payload)
  ui.popup_active = true
  ui.popup_payload = payload
  ui.popup_seq = (ui.popup_seq or 0) + 1
  ui.popup_broadcast = payload and payload.broadcast == true
  ui.popup_exclude_role_id = payload and payload.exclude_role_id or nil
end

-- popup 旗标影响 base_visible / 道具槽可点性,开关都必须标 ui_dirty 驱动重绘:
-- 弹窗自动关闭后若再无其他 dirty 源(如回合结束阶段用卡),槽位会保持弹窗期间
-- 渲染的不可点状态直到窗口超时。
function modal_state.open_popup(state, payload)
  assert(state ~= nil and state.ui ~= nil, "missing ui state")
  _apply_popup_payload(state.ui, payload)
  -- 买家免展示口径(2026-08-25):载荷排除的角色由弹窗 canvas 分发跳过,
  -- 旗标随载荷落 ui 态,供分发与黑市重建门读取。旗标必须活过 modal 关闭:
  -- close_popup 收屏后的 canvas 回切分发仍要读它(被排除角色收屏也不回切),
  -- 故只能由 popup_presenter.close_popup 在最终分发完成后清,不能随本模块清。
  runtime_state.set_ui_dirty(state, true)
  panel_interrupt.interrupt(state)
end

function modal_state.close_popup(state)
  assert(state ~= nil and state.ui ~= nil, "missing ui state")
  state.ui.popup_active = false
  state.ui.popup_payload = nil
  runtime_state.set_ui_dirty(state, true)
end

return modal_state

