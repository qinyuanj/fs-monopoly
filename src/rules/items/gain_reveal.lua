local event_kinds = require("src.config.gameplay.event_kinds")
local timing = require("src.config.gameplay.timing")
local action_anim_port = require("src.foundation.ports.action_anim")
local intent_output_port = require("src.rules.ports.intent_output")
local inventory = require("src.rules.items.inventory")

local gain_reveal = {}

local function _can_queue(game, player, item_id)
  return game ~= nil and player ~= nil and item_id ~= nil
end

local function _reveal_source(opts)
  return opts and opts.source or nil
end

local function _gain_popup_body(player, item_id)
  local body = player.name .. " 获得道具卡：" .. inventory.item_name(item_id)
  local cfg = inventory.cfg(item_id)
  local description = cfg and cfg.description or nil
  if description ~= nil and description ~= "" then
    body = body .. "——" .. description
  end
  return body
end

-- 获得展示全来源统一走「卡牌展示屏」弹窗全员广播(2026-08-22 #543 口径反转):
-- 标题+获得文案+卡图全员同步,复刻机会卡 popup 通道。
-- 原「仅获得者可见」的图鉴放大卡私有展示已随 item_get_reveal 链路整条拆除;
-- source 字段保留观测与黑市取消路径识别用途。
-- (#544:放大卡覆盖层现住图鉴 canvas、per-role 可达,#512 约束表述已被真机
-- 原型推翻;浏览放大的「仅浏览者可见」归图鉴屏自身路径,与本通道无关。)
-- 2026-08-25 买家免展示口径:黑市购买的获得展示对买家本人冗余(黑市屏内
-- 即时反馈)且打断连续购买流程——展示仍全员广播,载荷置 exclude_role_id
-- 排除买家,UI 只按标志分发、跳过其 canvas,黑市屏全程不动。
local function _excluded_role_id(opts, player)
  if _reveal_source(opts) == "market" then
    return player.id
  end
  return nil
end

local function _push_gain_popup(game, player, item_id, opts)
  return intent_output_port.push_popup(game, {
    title = "道具卡",
    body = _gain_popup_body(player, item_id),
    kind = "item_card",
    image_ref = item_id,
    broadcast = true,
    exclude_role_id = _excluded_role_id(opts, player),
    auto_close_seconds = timing.item_get_reveal_seconds,
  }, { policy = "defer" })
end

function gain_reveal.queue(game, player, item_id, opts)
  if not _can_queue(game, player, item_id) then
    return false
  end
  local queued = action_anim_port.queue(game, {
    kind = event_kinds.item_gain_popup,
    player_id = player.id,
    owner_role_id = player.id,
    item_id = item_id,
    item_name = inventory.item_name(item_id),
    duration = timing.item_get_reveal_seconds,
    source = _reveal_source(opts),
    broadcast = true,
  })
  if queued then
    _push_gain_popup(game, player, item_id, opts)
  end
  return queued
end

return gain_reveal

