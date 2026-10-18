-- 商店购买结算的唯一解释者:一次购买结果 → 一个结构化 verdict { keep_open }。
-- 承接原 choice 模块购买结果解释的全部判定(经 purchase_result 收敛后
-- 读 canonical status),但不再接收 choice 层的 finish_choice——收尾与否只由
-- verdict.keep_open 表达,由 choice_handlers/market adapter 翻成框架的
-- {stay=true} / finish_choice(game,false)。副作用(rebuild、inventory_full、
-- intent 分发)全部收敛在此;finish_choice 泄漏就此消失。
-- 单向依赖 choice(session/feedback 卫星),choice 不 require 本模块,无环。
--
-- 本模块**不做 intent 分发**(工单 #133):resolve 的两个调用点
-- (choice_handlers/market.lua、market/auto.lua)传入的 result 恒为
-- purchase.execute 的返回值,而它的四种形状(false / {ok=false,reason} /
-- {ok=true,fulfilled_now} / {ok=true,deferred_fulfillment})**没有一种带 intent 键**。
-- 真正产 intent 的是 market/effects.lua,但它走 intent dispatcher,不流经本模块。
local choice = require("src.rules.market.choice")
local purchase_result = require("src.rules.market.purchase_result")

local session = choice.session
local feedback = choice.feedback

local purchase_settlement = {}

local function _is_purchase_failure(canonical)
  return canonical.status == "rejected"
end

local function _should_keep_market_open(entry, canonical)
  if canonical.status == "deferred" then
    return true
  end
  return entry and entry.kind == "item" and canonical.status == "fulfilled"
end

local function _is_full_buy(entry, canonical)
  return entry and entry.kind == "item"
    and canonical.status == "fulfilled" and canonical.inventory_full_after == true
end

local function _handle_keep_open(game, choice_state, player, entry, canonical)
  local rebuilt = session.rebuild_pending(game, choice_state, player)
  if not rebuilt then return { keep_open = false } end
  if _is_full_buy(entry, canonical) then feedback.emit_inventory_full(player, entry) end
  return { keep_open = true }
end

local function _try_failure_stay(game, choice_state, player, canonical)
  if not _is_purchase_failure(canonical) then return false end
  return not not session.rebuild_pending(game, choice_state, player)
end

function purchase_settlement.resolve(game, choice_state, player, entry, result)
  local canonical = purchase_result.canonicalize(result)
  if _should_keep_market_open(entry, canonical) then
    return _handle_keep_open(game, choice_state, player, entry, canonical)
  end
  if _try_failure_stay(game, choice_state, player, canonical) then return { keep_open = true } end
  return { keep_open = false }
end

return purchase_settlement

