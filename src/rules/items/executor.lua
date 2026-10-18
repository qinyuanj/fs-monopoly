local effects = require("src.rules.items.post_effects")
local auto_play_port = require("src.rules.ports.auto_play")
local flow_context = require("src.rules.items.use_flow_context")
local inventory = require("src.rules.items.inventory")
local settlement = require("src.rules.items.settlement")

local executor = {}

local function _resolve_context(game, player, context)
  context = context or {}
  if type(context.is_computer_controlled) == "nil" then
    context.is_computer_controlled = auto_play_port.is_computer_controlled(game, player)
  end
  return context
end

local function _resolve_handler(game, item_id)
  local registries = assert(game.registries, "missing game.registries")
  local registry = assert(registries.items, "missing item registry")
  return registry.handlers[item_id]
end

-- 无注册 handler 的道具:post effect 即 applier,消耗归 settlement(before_apply)。
local function _use_post_effect(game, player, item_id, context, fallback_reason)
  return settlement.execute(game, player, item_id, function()
    local res = effects.apply_post(game, player, item_id, context)
    assert(res ~= nil, "missing item post effect result: " .. tostring(item_id))
    return res
  end, { consume = "before_apply", fallback_reason = fallback_reason })
end

-- 历史 handler 契约:效果已在 handler 内部生效(含消耗),结算只负责
-- 判定/广播/兜底动画;消耗事实经 apply 前后计数回填台账。
-- 该路径随 step 3 各 kind 迁入 settlement 后仅剩注入式测试 handler 使用。
local function _settle_applied_handler(game, player, item_id, res, before_count, fallback_reason)
  return settlement.execute(game, player, item_id, function()
    return res
  end, {
    consume = "already_applied",
    fallback_reason = fallback_reason,
    preapplied_count = before_count,
  })
end

function executor.use_item(game, player, item_id, context)
  context = _resolve_context(game, player, context)
  local cfg = inventory.cfg(item_id)
  assert(cfg ~= nil, "missing item cfg: " .. tostring(item_id))
  local fallback_reason = context.reject_reason_fallback

  local handler = _resolve_handler(game, item_id)
  if handler == nil then
    return _use_post_effect(game, player, item_id, context, fallback_reason)
  end

  local before_count = flow_context.count_item(player, item_id)
  local res = handler(game, player, item_id, context)
  if settlement.is_settled(res) then
    return res
  end
  -- waiting 形状不在这里判:use_result.canonicalize 是 raw 形状的唯一解码点,
  -- 它把 waiting 归为 await_choice,settlement 再原样放行 raw、不落任何账。
  -- executor 自己再判一次只会把「谁认识 waiting」重新摊回两处。
  return _settle_applied_handler(game, player, item_id, res, before_count, fallback_reason)
end

return executor

--[[ mutate4lua-manifest
version=4
projectHash=d52f3db5823f97ab
scope.0.id=chunk:src/rules/items/executor.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=69
scope.0.semanticHash=18d64a487a3d12f0
scope.1.id=function:_resolve_context
scope.1.kind=function
scope.1.startLine=9
scope.1.endLine=15
scope.1.semanticHash=373d2c4c480c68c0
scope.2.id=function:_resolve_handler
scope.2.kind=function
scope.2.startLine=17
scope.2.endLine=21
scope.2.semanticHash=dc27a51c59197b11
scope.3.id=function:_use_post_effect
scope.3.kind=function
scope.3.startLine=24
scope.3.endLine=30
scope.3.semanticHash=f592722d6d2354aa
scope.4.id=function:<anonymous>
scope.4.kind=function
scope.4.startLine=25
scope.4.endLine=29
scope.4.semanticHash=ac2e2ffdb008515e
scope.5.id=function:_settle_applied_handler
scope.5.kind=function
scope.5.startLine=35
scope.5.endLine=44
scope.5.semanticHash=442dcb21260eb9ab
scope.6.id=function:<anonymous>#2
scope.6.kind=function
scope.6.startLine=36
scope.6.endLine=38
scope.6.semanticHash=1136505bd37c301e
scope.7.id=function:executor.use_item
scope.7.kind=function
scope.7.startLine=46
scope.7.endLine=66
scope.7.semanticHash=3275df758ca60eaf
]]
