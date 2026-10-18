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

-- 行为测试公共接缝：test_item_use_flow / test_force_skip_refund_pin 经此入口建立托管，
-- 再由真实选择解析或强制跳过验证仅消费一次、退还幂等与背包容量约束。
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

