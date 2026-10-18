-- 自定义事件处理器装配(>100 mutation sites 拆分):结算面板 endgame_result_panels /
-- 棋盘反馈 cue board_feedback_handlers / 市场提示 market_tip_handlers 各自成模块,
-- 本文件保留安装核心(注册闭包 + 分发/延迟)与惰性装载时序。
local monopoly_event = require("src.foundation.events")
local host_events = require("src.ui.seams.host_events")
local landing_visual_hold = require("src.ui.visual_hold")
local endgame_result_panels = require("src.ui.coord.endgame_result_panels")
local board_feedback_handlers = require("src.ui.coord.board_feedback_handlers")
local market_tip_handlers = require("src.ui.coord.market_tip_handlers")
local tile_index_handlers = require("src.ui.coord.tile_index_handlers")

local event_handlers = {}
local context = { installed = false, state = nil }

function event_handlers.install(_, logger, state)
  context.state = state
  endgame_result_panels.set_context(logger, state)
  board_feedback_handlers.set_context(state)
  tile_index_handlers.set_context(state)

  if context.installed then
    return
  end
  context.installed = true

  local function _dispatch_or_defer(data, handler, immediate)
    local current_state = context.state
    if current_state == nil or immediate == true then
      return handler(data)
    end
    local result = nil
    landing_visual_hold.run_or_defer(current_state, nil, "runtime_event", function()
      result = handler(data)
    end)
    return result
  end

  -- handlers_by_event 登记簿已删(#262):写后无任何读者(纯记账),
  -- `#list + 1` 的下标变异不可杀;注册行为本身由 host_events 承担。
  local function _register_handler(event_name, handler)
    -- gm.finished 是终态事件,落地 hold 激活时不得 defer:finished 后
    -- advance_turn 直接返回(game_state),回合脚本永不恢复,release_pending
    -- 永不置位,defer 即永久滞留——面板不弹、对局不结束。
    local immediate = event_name == monopoly_event.game.finished
    host_events.register_custom_event(event_name, function(_, _, data)
      return _dispatch_or_defer(data, handler, immediate)
    end)
  end

  pcall(require, "src.ui.render.anim")

  tile_index_handlers.install(_register_handler, monopoly_event)
  board_feedback_handlers.install(_register_handler, monopoly_event)
  market_tip_handlers.install(_register_handler, monopoly_event)
  endgame_result_panels.install(_register_handler, monopoly_event)
end

return event_handlers

