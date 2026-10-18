-- 市场提示事件处理器(自 event_handlers.lua 拆分,行为保持):购买失败与卡槽
-- 满载的 tip 队列消息。
local tip_queue = require("src.foundation.tips")

local market_tip_handlers = {}
local MARKET_TIP_MIN_SECONDS = 3.0

local _enqueue_tip = tip_queue.enqueue

local function _event_data(data)
  if type(data) == "table" then
    return data
  end
  return nil
end

local function _popup_body(event_data)
  local popup = event_data and event_data.popup or nil
  return popup and popup.body or nil
end

local function _resolve_market_buy_failed_tip(event_data)
  local body = _popup_body(event_data)
  if type(body) == "string" and body ~= "" then
    return body
  end
  return "黑市购买失败"
end

function market_tip_handlers.install(register_handler, monopoly_event)
  register_handler(monopoly_event.market.buy_failed, function(data)
    local event_data = _event_data(data)
    local tip_text = _resolve_market_buy_failed_tip(event_data)
    _enqueue_tip({
      text = tip_text,
      duration = MARKET_TIP_MIN_SECONDS,
      dedupe_key = "market_buy_failed:" .. tostring(tip_text),
      blocks_inter_turn = false,
      source = "market.buy_failed",
    })
  end)

  register_handler(monopoly_event.market.inventory_full, function(data)
    local event_data = _event_data(data)
    local tip_text = (event_data and event_data.body) or "卡槽已满，无法继续购买"
    _enqueue_tip({
      text = tip_text,
      duration = MARKET_TIP_MIN_SECONDS,
      dedupe_key = "market_inventory_full",
      blocks_inter_turn = false,
      source = "market.inventory_full",
    })
  end)
end

return market_tip_handlers

