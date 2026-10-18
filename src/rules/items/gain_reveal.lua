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

--[[ mutate4lua-manifest
version=4
projectHash=479ce3b47c79b5bd
scope.0.id=chunk:src/rules/items/gain_reveal.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=76
scope.0.semanticHash=3bb5e1565d15ed3e
scope.1.id=function:_can_queue
scope.1.kind=function
scope.1.startLine=9
scope.1.endLine=11
scope.1.semanticHash=342b68d7fd51b713
scope.2.id=function:_reveal_source
scope.2.kind=function
scope.2.startLine=13
scope.2.endLine=15
scope.2.semanticHash=616a2ca60599c94f
scope.3.id=function:_gain_popup_body
scope.3.kind=function
scope.3.startLine=17
scope.3.endLine=25
scope.3.semanticHash=bd5eec2bd7fba197
scope.4.id=function:_excluded_role_id
scope.4.kind=function
scope.4.startLine=36
scope.4.endLine=41
scope.4.semanticHash=016404b903ca3235
scope.5.id=function:_push_gain_popup
scope.5.kind=function
scope.5.startLine=43
scope.5.endLine=53
scope.5.semanticHash=032cace616e130d6
scope.6.id=function:gain_reveal.queue
scope.6.kind=function
scope.6.startLine=55
scope.6.endLine=73
scope.6.semanticHash=d3e9ef111aad7469
]]
