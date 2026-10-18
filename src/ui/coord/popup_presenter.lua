local modal_state = require("src.ui.state.modal")
local popup = require("src.ui.coord.popup")
local canvas = require("src.ui.coord.canvas_coordinator")
local dice_nodes = require("src.ui.schema.dice")
local role_id_utils = require("src.foundation.identity")
local logger = require("src.foundation.log")

local popup_presenter = {}

-- 先落状态再渲染:popup_broadcast 只在 modal_state.open_popup 一处置位,
-- popup.show 的 canvas 分发读的就是这份状态。
function popup_presenter.push_popup(state, payload, opts)
  assert(payload ~= nil, "missing popup payload")
  opts = opts or {}
  local ui = state.ui
  if opts.policy == "defer" and ui.popup_active then
    local queue = ui.popup_queue
    if type(queue) ~= "table" then
      queue = {}
      ui.popup_queue = queue
    end
    queue[#queue + 1] = payload
    return true
  end
  modal_state.open_popup(state, payload)
  popup.show(state, payload)
  return true
end

local function _current_turn(state)
  return state and state.game and state.game.turn or nil
end

local function _action_anim_of(turn)
  return turn and turn.action_anim or nil
end

local function _is_roll_action_anim(turn)
  local anim = _action_anim_of(turn)
  return turn ~= nil and turn.phase == "wait_action_anim" and anim ~= nil and anim.kind == "roll"
end

local function _is_roll_action_anim_active(state)
  return _is_roll_action_anim(_current_turn(state))
end

local function _resolve_canvas_after_popup(state, ui)
  if _is_roll_action_anim_active(state) then
    return dice_nodes.canvas
  end
  return canvas.resolve_canvas_after_popup(ui)
end

local function _next_queued_popup(queue)
  if type(queue) == "table" and #queue > 0 then
    return table.remove(queue, 1)
  end
  return nil
end

function popup_presenter.close_popup(state)
  local ui = state.ui
  if not (ui and ui.popup_active) then
    logger.warn("close_popup ignored: popup not active")
    return
  end
  local kind = ui.popup_kind or "card"
  popup.hide(state)
  modal_state.close_popup(state)
  ui.popup_kind = nil
  local next_payload = _next_queued_popup(ui.popup_queue)
  if next_payload ~= nil then
    modal_state.open_popup(state, next_payload)
    popup.show(state, next_payload)
    return
  end
  local next_canvas = _resolve_canvas_after_popup(state, ui)
  popup.switch_popup_canvas(state, kind, next_canvas, canvas.CANVAS_BASE)
  ui.popup_broadcast = false
  ui.popup_exclude_role_id = nil
end

-- 点击关闭的唯一入口:广播展示的关闭权只归行动者,非广播弹窗维持谁点谁关。
-- 买家免展示口径(2026-08-25):被载荷排除的角色(黑市买家)看不到展示也无
-- 关闭权——其收屏只走超时自动关闭,程序化 popup_confirm 不得提前收掉旁观者
-- 的展示。
-- 广播弹窗的关闭权判定(CRAP 门禁):排除者与非行动者两条拒绝路径收敛到
-- 本谓词,dismiss_popup 只留「是否广播」的分派与收屏。
local function _may_dismiss_broadcast(state, ui, actor_role_id)
  local actor = role_id_utils.normalize(actor_role_id)
  if ui.popup_exclude_role_id ~= nil and role_id_utils.equals(actor, ui.popup_exclude_role_id) then
    return false
  end
  return role_id_utils.equals(actor, modal_state.operator_role_id(state))
end

function popup_presenter.dismiss_popup(state, actor_role_id)
  local ui = state and state.ui
  if ui and ui.popup_broadcast and not _may_dismiss_broadcast(state, ui, actor_role_id) then
    return false
  end
  popup_presenter.close_popup(state)
  return true
end

return popup_presenter

