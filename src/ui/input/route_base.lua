local logger = require("src.foundation.log")
local base_nodes = require("src.ui.schema.base")
local route_model = require("src.ui.input.route_model")
local choice_support = require("src.ui.view.choice_support")
local optional_action_completion = require("src.turn.optional_action_completion")
local panel_interrupt = require("src.ui.state.panel_interrupt")

local intents = {}

local function _input_blocked(state)
  local ui = state and state.ui
  if ui and ui.input_blocked == true then
    return true
  end
  return panel_interrupt.settlement_type(ui) ~= nil
end

local function _can_build_optional_completion_intent(state)
  local result = optional_action_completion.can_complete_optional_action_phase(nil, nil, state, {
    choice = route_model.choice(state),
    require_actor = false,
    gate_state = {
      input_blocked = _input_blocked(state),
    },
  })
  return result.ok == true
end

-- 基础屏取消出口的唯一意图口径。基础屏取消按钮与遥控骰子灰底(#177 点背景关闭)
-- 共用:同一 choice_cancel、同一 is_base_cancel_choice 判断,两个出口永不脱节。
function intents.build_base_cancel_intent(state, source_label)
  local choice = route_model.choice(state)
  -- 与渲染显隐同一口径(choice_support.is_base_cancel_choice):按钮亮即有 intent。
  -- 口径外的点击说明按钮陈旧或模型失步,留 warn 供真机排查(此前是全链路唯一零日志吞点)。
  if not choice_support.is_base_cancel_choice(choice) then
    logger.warn((source_label or "基础屏取消按钮") .. "点击被忽略: 当前无可取消的道具后续选择",
      choice and ("choice_kind=" .. tostring(choice.kind)) or "choice=nil")
    return nil
  end
  return {
    type = "choice_cancel",
    choice_id = choice.id,
  }
end

function intents.build(state)
  return {
    {
      name = base_nodes.action_button,
      build_intent = function()
        local choice = route_model.choice(state)
        if choice_support.is_pre_action_item_phase_passive(choice) then
          return { type = "complete_optional_action_phase" }
        end
        if choice_support.is_optional_action_choice(choice) then
          return nil
        end
        return { type = "ui_button", id = "next" }
      end,
    },
    {
      name = base_nodes.end_button,
      build_intent = function()
        if not _can_build_optional_completion_intent(state) then
          return nil
        end
        return { type = "complete_optional_action_phase" }
      end,
    },
    {
      name = base_nodes.cancel_button,
      build_intent = function()
        return intents.build_base_cancel_intent(state)
      end,
    },
    {
      name = base_nodes.auto_button,
      build_intent = function()
        return { type = "ui_button", id = "auto" }
      end,
    },
    {
      name = base_nodes.action_log_button,
      build_intent = function()
        return { type = "toggle_action_log" }
      end,
    },
    {
      name = base_nodes.skin_button,
      build_intent = function()
        return { type = "open_skin_panel" }
      end,
    },
    {
      name = base_nodes.gallery_button,
      build_intent = function()
        return { type = "open_gallery_panel" }
      end,
    },
    {
      name = base_nodes.share_button,
      build_intent = function()
        return { type = "open_share_panel" }
      end,
    },
    {
      name = base_nodes.gift_code_button,
      build_intent = function()
        return { type = "open_gift_code_screen" }
      end,
    },
  }
end

return intents

