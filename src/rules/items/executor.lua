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

