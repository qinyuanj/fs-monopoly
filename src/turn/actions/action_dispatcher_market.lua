-- market 域 handler：黑市翻页/页签导航。handle_force_skip（choice 强制跳过，走
-- src.turn.deadlines）与黑市无关，因同属「choice 级旁路处理」且体量过小不值得
-- 单开模块而收在这里；回迁/改名需同步 manifest 与多个 dispatch spec，暂以本注释
-- 明示收录口径。
local validator = require("src.turn.actions.validator")
local market_service = require("src.rules.market")
local force_resolve = require("src.turn.deadlines")
local ctx_mod = require("src.turn.actions.context")

local market_handlers = {}

function market_handlers.apply_market_navigation(game, state, action, ctx, choice)
  if not choice or choice.kind ~= "market_buy" then
    return false
  end
  if not validator.validate(action, { game = game, choice = choice }) then
    return false
  end
  if not market_service.choice.apply_navigation(game, choice, action) then
    return false
  end
  ctx.output_ports.sync_pending_choice(state, choice)
  return true
end

function market_handlers.handle_market_navigation(game, state, action, opts, ctx)
  local choice = ctx_mod.resolve_pending_choice(game, state, ctx)
  if not market_handlers.apply_market_navigation(game, state, action, ctx, choice) then
    return { status = "rejected" }
  end
  return { status = "applied" }
end

function market_handlers.handle_force_skip(game, state, action, opts, ctx)
  local choice = ctx_mod.resolve_pending_choice(game, state, ctx)
  force_resolve.force_skip(game, state, choice, action.reason or "dispatch")
  return { status = "applied" }
end

return market_handlers

