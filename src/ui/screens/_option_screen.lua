-- player / remote 共享的选项开屏 helper（两屏 open 委托它，避免复制）。
local openers = require("src.ui.coord.choice_openers")
local modal_state = require("src.ui.state.modal")

local M = {}

function M.open(state, screen_key, choice, choice_id)
  local ui, screen = openers.open_screen(state, screen_key, choice, choice_id)
  -- 灰底触摸按屏区分(#177):underlay_touch 的屏(遥控骰子)灰底即点背景关闭出口,
  -- 开触摸接 CLICK;其余屏(玩家选择)灰底是纯装饰,Eggy 覆盖节点默认吸触摸,
  -- 显式关触摸让点击穿透到下层基础屏取消按钮。
  if screen.underlay then
    ui:set_touch_enabled(screen.underlay, screen.underlay_touch == true)
  end
  local option_ids, selected = openers.fill_option_nodes(
    ui, screen, openers.resolve_player_or_remote_options(choice, screen_key))
  openers.set_action_button(ui, screen.confirm, true, true, "确定")
  local allow_cancel = choice.allow_cancel ~= false
  openers.set_action_button(ui, screen.cancel, allow_cancel, allow_cancel, choice.cancel_label or "取消")
  modal_state.open_choice(state, choice_id, option_ids, selected)
end

return M

