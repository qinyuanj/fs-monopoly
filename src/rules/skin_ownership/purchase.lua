-- 皮肤付费购买(#204 皮肤归属内部):校验拒绝条件、记录在途、经付费购买 port 发起;
-- 宿主回调完成时结算归属、清在途、穿上,再把结果交给本次购买的 on_complete。
-- 同一角色同时只能有一笔在途购买;完成时商品必须与在途一致。
local logger = require("src.foundation.log")
local paid_purchase_port = require("src.rules.ports.paid_purchase")
local archive = require("src.rules.skin_ownership.archive")
local catalog = require("src.rules.skin_ownership.catalog")
local session = require("src.rules.skin_ownership.session")

local purchase = {}

local function _resolve_buyer(root_state, role_id)
  local game = root_state.game
  if game == nil then
    return nil, nil, "missing_game"
  end
  if type(game.find_player_by_id) ~= "function" then
    return game, nil, "missing_player_lookup"
  end
  local player = game:find_player_by_id(role_id)
  if player == nil then
    return game, nil, "missing_player"
  end
  return game, player, nil
end

local function _clear_pending(slot, key)
  slot.pending_by_role[key] = nil
end

local function _complete(root_state, role_id, product_id)
  local slot = session.ensure(root_state)
  local key = session.role_key(role_id)
  local pending = slot.pending_by_role[key]
  if pending == nil then
    return session.rejected("pending_purchase_missing", { product_id = product_id })
  end
  if pending.product_id ~= product_id then
    return session.rejected("pending_purchase_mismatch", { product_id = product_id })
  end
  _clear_pending(slot, key)
  local skin = catalog.skin_by_product(product_id)
  if skin == nil then
    return session.rejected("missing_product", { product_id = product_id })
  end
  local _, persisted = session.mark_owned(slot, role_id, product_id)
  local equipped = session.wear(slot, role_id, skin)
  return session.accepted({ product_id = product_id, equipped = equipped, persisted = persisted })
end

local function _notify(on_complete, result)
  if type(on_complete) ~= "function" then
    return
  end
  local ok, err = pcall(on_complete, result)
  if not ok then
    logger.warn("skin_ownership: purchase on_complete failed", tostring(err))
  end
end

local function _entry(root_state, role_id, skin, on_complete)
  return {
    kind = "skin",
    product_id = skin.product_id,
    name = skin.name,
    currency = skin.currency,
    price = skin.price,
    on_purchase = function()
      local result = _complete(root_state, role_id, skin.product_id)
      _notify(on_complete, result)
      return result.accepted == true
    end,
  }
end

-- 返回 (是否发起, 失败原因)。
local function _start_via_paid_port(root_state, role_id, entry)
  local game, player, player_reason = _resolve_buyer(root_state, role_id)
  if player_reason ~= nil then
    return false, player_reason
  end
  local ok, started, reason = pcall(paid_purchase_port.start, game, player, entry)
  if not ok then
    logger.warn("skin_ownership: paid purchase start failed", "role_id=" .. tostring(role_id), tostring(started))
    return false, "paid_gateway_missing"
  end
  if started ~= true then
    return false, reason or "paid_gateway_rejected"
  end
  return true, nil
end

local function _rejection(skin, slot, key)
  if skin.unlock ~= "purchase" then
    return "invalid_purchase_skin"
  end
  -- ADR 0074 第 2 条:归属写不进存档就不收钱。
  if not archive.can_persist(skin.product_id) then
    return "archive_unavailable"
  end
  if slot == nil then
    return "missing_state"
  end
  if key == nil then
    return "missing_role"
  end
  if slot.pending_by_role[key] ~= nil then
    return "purchase_in_flight"
  end
  return nil
end

function purchase.start(root_state, role_id, product_id, on_complete)
  local skin = catalog.skin_by_product(product_id)
  if skin == nil then
    return session.rejected("missing_product", { product_id = product_id })
  end
  local slot = session.ensure(root_state)
  local key = session.role_key(role_id)
  local reason = _rejection(skin, slot, key)
  if reason ~= nil then
    return session.rejected(reason, { product_id = product_id })
  end
  slot.pending_by_role[key] = { product_id = product_id }
  local started, start_reason = _start_via_paid_port(root_state, role_id, _entry(root_state, role_id, skin, on_complete))
  if not started then
    _clear_pending(slot, key)
    return session.rejected(start_reason, { product_id = product_id })
  end
  return session.accepted({ product_id = product_id })
end

return purchase
