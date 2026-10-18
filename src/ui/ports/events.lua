local runtime_state = require("src.ui.state.runtime")

local runtime_event_ports = {}

local function _visual_sync_ready(state, payload)
  return payload ~= nil and payload.tile_id ~= nil and state.on_board_visual_sync
end

function runtime_event_ports.on_tile_upgraded(state, payload)
  if _visual_sync_ready(state, payload) then
    state:on_board_visual_sync({
      tile_ids = { payload.tile_id },
    })
  end
end

local function _record_pending_choice(state, choice, payload)
  runtime_state.set_pending_choice(state, choice, {
    choice_id = choice.id,
    elapsed_seconds = payload and payload.elapsed_seconds or 0,
  })
  runtime_state.set_ui_dirty(state, true)
end

local function _event_choice(payload)
  return payload and payload.choice or nil
end

-- #524 时序裁定：开屏只允许发生在 dirty 刷新内（ui_sync.model._render_ui_model
-- 为唯一开屏口），事件路径只记账——记 pending choice 并置 ui_dirty，同帧
-- dirty 刷新按 gate 判定开屏；两条开屏路径叠加导致的同 choice 双开随之消解。
-- get_current_game 保留在签名内：event_bridge 按事件回调三参契约传入，
-- 记账路径不再读它。
function runtime_event_ports.on_need_choice(state, get_current_game, payload)
  local choice = _event_choice(payload)
  if not choice then
    return
  end
  _record_pending_choice(state, choice, payload)
end

return runtime_event_ports

