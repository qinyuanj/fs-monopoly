-- remote（遥控骰子）选择屏的唯一归宿：schema 引用 + 开屏 + 点击意图。
-- 无 inert 确认键，点选项即确认。
local schema = require("src.ui.schema.remote_choice")
local canvas = require("src.ui.coord.canvas_coordinator")
local option_screen = require("src.ui.screens._option_screen")
local logger = require("src.foundation.log")
local ui_event_intents = require("src.ui.input.event_intents")
local runtime_state = require("src.ui.state.runtime")
local route_base = require("src.ui.input.route_base")

local M = { key = "remote", canvas = canvas.CANVAS_REMOTE_CHOICE }

function M.descriptor()
  return {
    key = "remote",
    root = schema.canvas,
    title = schema.title,
    body = schema.body,
    underlay = schema.underlay,
    -- 灰底接点背景关闭(#177),开屏开触摸;输入锁定时随屏一并关闭。
    underlay_touch = true,
    option_buttons = schema.options,
  }
end

function M.open(state, choice, choice_id)
  option_screen.open(state, "remote", choice, choice_id)
end

function M.build_route_specs(state)
  local specs = {}
  for index, name in ipairs(schema.options) do
    specs[#specs + 1] = {
      name = name,
      build_intent = function()
        local model = runtime_state.get_ui_model(state)
        local choice = model and model.choice or nil
        if not choice then logger.warn("remote_select without choice"); return nil end
        local option_id = ui_event_intents.resolve_option_id(choice, { index = index }, state)
        if not option_id then logger.warn("remote_select missing option:", tostring(index)); return nil end
        return { type = "choice_select", choice_id = choice.id, option_id = option_id }
      end,
    }
  end
  -- 点背景关闭(#177):灰底 ≡ 基础屏取消按钮,复用同一意图口径。
  specs[#specs + 1] = {
    name = schema.underlay,
    build_intent = function()
      return route_base.build_base_cancel_intent(state, "遥控骰子灰底")
    end,
  }
  return specs
end

return M

