-- 道具使用结果结算深模块:唯一解释者。
-- 成功判定(经 use_result.canonicalize)、消耗/留存时机、成就遥测
-- (恰好一次)、兜底 action_anim 全部收敛于此;waiting 原样放行(不消耗、
-- 不补动画）。外部 begin/resolve seam 保持冻结，
-- 本模块只被 use_flow implementation 与自身测试穿过。
local achievement_progress = require("src.rules.ports.achievement_progress")
local availability = require("src.rules.items.availability")
local action_anim_port = require("src.foundation.ports.action_anim")
local flow_context = require("src.rules.items.use_flow_context")
local inventory = require("src.rules.items.inventory")
local item_ids = require("src.config.gameplay.item_ids")
local timing = require("src.config.gameplay.timing")
local use_result = require("src.rules.items.use_result")

local settlement = {}
-- 兜底动画时长只认 config 真源(timing.action_anim_default_seconds 恒有值,
-- 「or 1.0」是恒被短路的死默认——等价变异体,按 #257 三分类删冗余)。
local action_anim_duration = timing.action_anim_default_seconds

-- 消耗时机:kind 级默认由调用方描述符经 opts.consume 声明
-- (before_apply | after_success | applier_owned | already_applied),
-- 道具级例外只登记在这张表——偷窃卡与导弹卡经 commit() 自耗。
local _item_consume_overrides = {
  [item_ids.steal] = "applier_owned",
  [item_ids.missile] = "applier_owned",
}

local ESCROW_META_KEY = "item_use_escrow"

local function _resolve_consume_mode(item_id, opts)
  local mode = opts.consume or "before_apply"
  if mode == "already_applied" then
    return mode
  end
  return _item_consume_overrides[item_id] or mode
end

-- 台账的 escrow 种子:优先读结算私有令牌,同时承认公共跨层布尔
-- choice.meta.item_preconsumed(turn/choice 层与既有 fixture 的既定接口)。
local function _escrow_token(opts)
  local meta = opts.choice and opts.choice.meta or nil
  return meta and meta[ESCROW_META_KEY] or nil
end

local function _token_escrowed(token)
  return token ~= nil and token.consumed == true and token.refunded ~= true
end

local function _meta_escrowed(opts)
  local meta = opts.choice and opts.choice.meta or nil
  return meta ~= nil and meta.item_preconsumed == true
end

local function _seed_escrow(ledger, opts)
  if _token_escrowed(_escrow_token(opts)) then
    ledger.escrowed = true
    return
  end
  if _meta_escrowed(opts) then
    ledger.escrowed = true
    return
  end
end

local function _make_commit(player, item_id, ledger)
  return function()
    assert(ledger.committed ~= true, "item use already committed: " .. tostring(item_id))
    ledger.committed = true
    if ledger.escrowed or ledger.consumed then
      return true
    end
    assert(inventory.consume(player, item_id) == true, "consume committed item failed: " .. tostring(item_id))
    ledger.consumed = true
    return true
  end
end

local function _item_consumed(ledger)
  return ledger.escrowed == true or ledger.consumed == true
end

local function _action_anim_seq(game)
  return game.turn and game.turn.action_anim_seq or 0
end

local function _item_name(item_id)
  local cfg = inventory.cfg(item_id)
  return cfg and cfg.name or nil
end

local function _queue_fallback_anim(game, player, item_id, before_seq, canonical)
  if canonical.action_anim then
    return canonical.action_anim
  end
  if not action_anim_port.is_enabled(game) then
    return canonical.action_anim
  end
  if _action_anim_seq(game) > before_seq then
    return canonical.action_anim
  end
  action_anim_port.queue(game, {
    kind = "item_use",
    player_id = player.id,
    item_id = item_id,
    item_name = _item_name(item_id),
    duration = action_anim_duration,
  })
  return true
end

local function _frozen_base(status, ok, player, item_id, ledger, canonical)
  return {
    ok = ok,
    status = status,
    actor = player,
    actor_id = player and player.id or nil,
    item_id = item_id,
    item_consumed = _item_consumed(ledger),
    result = canonical.raw,
    _settled_item_use = true,
  }
end

local function _consume_after_success(player, item_id, ledger, consume_mode)
  if consume_mode ~= "after_success" or _item_consumed(ledger) then
    return
  end
  assert(inventory.consume(player, item_id) == true, "consume applied item failed: " .. tostring(item_id))
  ledger.consumed = true
end

local function _assert_applier_owned(item_id, ledger, consume_mode)
  if consume_mode ~= "applier_owned" then
    return
  end
  assert(ledger.committed == true or _item_consumed(ledger),
    "applier-owned item applied without commit: " .. tostring(item_id))
end

local function _settle_applied(game, player, item_id, ledger, canonical, consume_mode, before_seq)
  if canonical.consumed_by_applier then
    ledger.consumed = true
  end
  _consume_after_success(player, item_id, ledger, consume_mode)
  _assert_applier_owned(item_id, ledger, consume_mode)
  availability.mark_effect_group_used(game, item_id)
  local frozen = _frozen_base("applied", true, player, item_id, ledger, canonical)
  frozen.action_anim = _queue_fallback_anim(game, player, item_id, before_seq, canonical)
  frozen.after_action_anim = canonical.after_action_anim
  achievement_progress.item_used(game, player)
  return frozen
end

local function _settle_rejected(player, item_id, ledger, canonical)
  if canonical.consumed_by_applier then
    ledger.consumed = true
  end
  local frozen = _frozen_base("rejected", false, player, item_id, ledger, canonical)
  frozen.reason = canonical.reason
  return frozen
end

local function _consume_before_apply(player, item_id, ledger, consume_mode)
  if consume_mode ~= "before_apply" or ledger.escrowed then
    return
  end
  assert(inventory.consume(player, item_id) == true, "consume item failed: " .. tostring(item_id))
  ledger.consumed = true
end

-- already_applied 模式的消耗事实回填:apply 前后计数差为正即视为 applier 已自耗。
local function _reconcile_preapplied_count(player, item_id, ledger, consume_mode, opts)
  if consume_mode ~= "already_applied" or opts.preapplied_count == nil then
    return
  end
  if flow_context.count_item(player, item_id) < opts.preapplied_count then
    ledger.consumed = true
  end
end

function settlement.execute(game, player, item_id, apply, opts)
  opts = opts or {}
  local consume_mode = _resolve_consume_mode(item_id, opts)
  local ledger = { consumed = false, escrowed = false, committed = false }
  _seed_escrow(ledger, opts)
  _consume_before_apply(player, item_id, ledger, consume_mode)

  local before_seq = _action_anim_seq(game)
  local raw = apply(_make_commit(player, item_id, ledger))
  local canonical = use_result.canonicalize(raw, opts.fallback_reason)

  if canonical.status == "await_choice" then
    return raw
  end
  _reconcile_preapplied_count(player, item_id, ledger, consume_mode, opts)
  if canonical.status == "rejected" then
    return _settle_rejected(player, item_id, ledger, canonical)
  end
  return _settle_applied(game, player, item_id, ledger, canonical, consume_mode, before_seq)
end

-- 非重复阶段 followup 的预消耗托管:卡即刻入台账 escrow(令牌随 choice 走),
-- resolve 时 _seed_escrow 认领不二次消耗,放弃路径经 settlement.abandon 退还。
-- 同时写公共跨层布尔 item_preconsumed(turn/choice 层既定接口)并禁用取消。
local function _seed_escrow_meta(choice_spec, player, item_id)
  local meta = choice_spec.meta or {}
  choice_spec.meta = meta
  meta[ESCROW_META_KEY] = { consumed = true, item_id = item_id, player_id = player.id }
  meta.item_preconsumed = true
  meta.item_id = meta.item_id or item_id
  meta.player_id = meta.player_id or player.id
end

function settlement.escrow(player, item_id, choice_spec)
  assert(type(choice_spec) == "table", "escrow needs a choice spec")
  assert(inventory.consume(player, item_id) == true, "escrow consume failed: " .. tostring(item_id))
  _seed_escrow_meta(choice_spec, player, item_id)
  choice_spec.allow_cancel = false
  choice_spec.cancel_label = nil
  return choice_spec
end

-- 令牌在场的退还判定:已消耗且未退还时才可退。
local function _refundable_token_item(meta, token)
  if token.consumed == true and token.refunded ~= true then
    return token.item_id or meta.item_id
  end
  return nil
end

-- 返回可退还的 item_id;不可退(无托管、已退、形状不符)返回 nil。
-- 令牌在场以令牌为准;仅有公共布尔的旧 fixture 走布尔判定。
local function _refundable_escrow_item(meta)
  local token = meta[ESCROW_META_KEY]
  if token ~= nil then
    return _refundable_token_item(meta, token)
  end
  if meta.item_preconsumed == true then
    return meta.item_id
  end
  return nil
end

-- 退还的两个前置:choice 形状合法,且 meta 上确有可退托管。
-- 返回 (meta, item_id);任一不成立时 item_id 为 nil。
local function _resolve_refund(choice)
  local meta = type(choice) == "table" and choice.meta or nil
  if type(meta) ~= "table" then
    return nil, nil
  end
  return meta, _refundable_escrow_item(meta)
end

-- 收卡人 id:令牌 → meta → choice owner 依次兜底。
local function _refund_actor_id(choice, meta, token)
  return (token and token.player_id) or meta.player_id or choice.owner_role_id
end

-- 收卡人:令牌 → meta → choice owner 依次兜底,须持有背包才能收。
local function _resolve_refund_actor(game, choice, meta, token)
  local player = flow_context.resolve_actor(game, _refund_actor_id(choice, meta, token))
  if not (player and player.inventory) then
    return nil
  end
  return player
end

-- 托管卡退还(force_skip / 目标失效放弃)。幂等:令牌只退一次;
-- 仅有公共布尔的旧 fixture 退还后翻转布尔防重复。
function settlement.abandon(game, choice, _)
  local meta, item_id = _resolve_refund(choice)
  if item_id == nil then
    return false
  end
  local token = meta[ESCROW_META_KEY]
  local player = _resolve_refund_actor(game, choice, meta, token)
  if player == nil then
    return false
  end
  if inventory.add(player, { id = item_id }) ~= true then
    return false
  end
  if token ~= nil then
    token.refunded = true
  end
  meta.item_preconsumed = false
  return true
end

function settlement.is_settled(value)
  return type(value) == "table" and value._settled_item_use == true
end

settlement.ESCROW_META_KEY = ESCROW_META_KEY

return settlement

--[[ mutate4lua-manifest
version=4
projectHash=c9202416dc677dce
scope.0.id=chunk:src/rules/items/settlement.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=297
scope.0.semanticHash=c298b4cefbde79ec
scope.1.id=function:_resolve_consume_mode
scope.1.kind=function
scope.1.startLine=28
scope.1.endLine=34
scope.1.semanticHash=63322cef87b31453
scope.2.id=function:_escrow_token
scope.2.kind=function
scope.2.startLine=38
scope.2.endLine=41
scope.2.semanticHash=1ce8d76e9850d858
scope.3.id=function:_token_escrowed
scope.3.kind=function
scope.3.startLine=43
scope.3.endLine=45
scope.3.semanticHash=e5273a0d66e6d09c
scope.4.id=function:_meta_escrowed
scope.4.kind=function
scope.4.startLine=47
scope.4.endLine=50
scope.4.semanticHash=f5a97f4e25132a43
scope.5.id=function:_seed_escrow
scope.5.kind=function
scope.5.startLine=52
scope.5.endLine=64
scope.5.semanticHash=bc7ee2eab2209db1
scope.6.id=function:_make_commit
scope.6.kind=function
scope.6.startLine=66
scope.6.endLine=77
scope.6.semanticHash=b6dd50da37474f95
scope.7.id=function:<anonymous>
scope.7.kind=function
scope.7.startLine=67
scope.7.endLine=76
scope.7.semanticHash=1d58829fec7c6ad8
scope.8.id=function:_item_consumed
scope.8.kind=function
scope.8.startLine=79
scope.8.endLine=81
scope.8.semanticHash=8a55e2fe6a6437b0
scope.9.id=function:_action_anim_seq
scope.9.kind=function
scope.9.startLine=83
scope.9.endLine=85
scope.9.semanticHash=ad93d62df55bfe8d
scope.10.id=function:_item_name
scope.10.kind=function
scope.10.startLine=87
scope.10.endLine=90
scope.10.semanticHash=9225cfe7b87d962b
scope.11.id=function:_queue_fallback_anim
scope.11.kind=function
scope.11.startLine=92
scope.11.endLine=110
scope.11.semanticHash=9174d0162a75970e
scope.12.id=function:_frozen_base
scope.12.kind=function
scope.12.startLine=112
scope.12.endLine=123
scope.12.semanticHash=0c888224820d3b0f
scope.13.id=function:_consume_after_success
scope.13.kind=function
scope.13.startLine=125
scope.13.endLine=131
scope.13.semanticHash=e7e36e93eefb3a88
scope.14.id=function:_assert_applier_owned
scope.14.kind=function
scope.14.startLine=133
scope.14.endLine=139
scope.14.semanticHash=21531f319979cb93
scope.15.id=function:_settle_applied
scope.15.kind=function
scope.15.startLine=141
scope.15.endLine=152
scope.15.semanticHash=e5fa76322cd915d2
scope.16.id=function:_settle_rejected
scope.16.kind=function
scope.16.startLine=154
scope.16.endLine=161
scope.16.semanticHash=72ccfab846e96d26
scope.17.id=function:_consume_before_apply
scope.17.kind=function
scope.17.startLine=163
scope.17.endLine=169
scope.17.semanticHash=1afcf6a6ab73cf25
scope.18.id=function:_reconcile_preapplied_count
scope.18.kind=function
scope.18.startLine=172
scope.18.endLine=179
scope.18.semanticHash=dcc78adb809c2f15
scope.19.id=function:settlement.execute
scope.19.kind=function
scope.19.startLine=181
scope.19.endLine=200
scope.19.semanticHash=2f4ef41e320f2ee0
scope.20.id=function:_seed_escrow_meta
scope.20.kind=function
scope.20.startLine=205
scope.20.endLine=212
scope.20.semanticHash=5e3990d7bcb3bd90
scope.21.id=function:settlement.escrow
scope.21.kind=function
scope.21.startLine=214
scope.21.endLine=221
scope.21.semanticHash=86fbddff4684782d
scope.22.id=function:_refundable_token_item
scope.22.kind=function
scope.22.startLine=224
scope.22.endLine=229
scope.22.semanticHash=f1592d5eae659f28
scope.23.id=function:_refundable_escrow_item
scope.23.kind=function
scope.23.startLine=233
scope.23.endLine=242
scope.23.semanticHash=5e2e7e5bcdaef441
scope.24.id=function:_resolve_refund
scope.24.kind=function
scope.24.startLine=246
scope.24.endLine=252
scope.24.semanticHash=f1acd360422468ea
scope.25.id=function:_refund_actor_id
scope.25.kind=function
scope.25.startLine=255
scope.25.endLine=257
scope.25.semanticHash=1492dfcf9870ad3e
scope.26.id=function:_resolve_refund_actor
scope.26.kind=function
scope.26.startLine=260
scope.26.endLine=266
scope.26.semanticHash=a4970bd8e21156f1
scope.27.id=function:settlement.abandon
scope.27.kind=function
scope.27.startLine=270
scope.27.endLine=288
scope.27.semanticHash=769076235e991e13
scope.28.id=function:settlement.is_settled
scope.28.kind=function
scope.28.startLine=290
scope.28.endLine=292
scope.28.semanticHash=2c6c232630682316
]]
