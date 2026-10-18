local event_kinds = require("src.config.gameplay.event_kinds")
local event_feed = require("src.rules.ports.event_feed")
local monopoly_event = require("src.foundation.events")
local timing = require("src.config.gameplay.timing")

local angel_feedback = {}

--- 天使免疫触发时统一发布反馈：tip 文案 + UI 特效（angel_deity cue）。
--- @param game table
--- @param target table  -- 受保护的玩家
--- @param item_label string  -- 道具简称，例如 "导弹"、"建筑摧毁"
--- @param opts? { tile_index?: integer }  -- 可选播放位置（默认走 player_id）
function angel_feedback.publish(game, target, item_label, opts)
  assert(target ~= nil, "missing target")
  assert(type(item_label) == "string" and item_label ~= "", "missing item_label")
  local text = target.name .. " 天使保护，" .. item_label .. "无效"
  event_feed.publish(game, {
    kind = event_kinds.item_immune,
    text = text,
    tip = true,
    tip_duration = timing.event_tip_default_seconds,
    tip_dedupe_key = "angel_immune:" .. tostring(target.id) .. ":" .. tostring(item_label),
    source = "rules.items.angel_feedback",
  })
  monopoly_event.emit(monopoly_event.feedback.angel_immune_blocked, {
    player_id = target.id,
    tile_index = opts and opts.tile_index or nil,
  })
end

return angel_feedback

