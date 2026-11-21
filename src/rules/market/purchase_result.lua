--   false(非法商品) / { ok=false, reason }(校验/余额/在途/通道失败) /
--   { ok=true, fulfilled_now=true, inventory_full_after }(本地即时成交) /
--   { ok=true, deferred_fulfillment=true }(付费下单、异步履约)。
--
local purchase_result = {}

local RESULT_MT = {}

local function _new(status, fields)
  return setmetatable({
    status = status,
    reason = fields.reason,
    kind = fields.kind,
    product_id = fields.product_id,
    fulfilled_now = fields.fulfilled_now,
    inventory_full_after = fields.inventory_full_after,
    raw = fields.raw,
  }, RESULT_MT)
end

function purchase_result.is_result(value)
  return getmetatable(value) == RESULT_MT
end

function purchase_result.fulfilled(fields)
  fields = fields or {}
  return _new("fulfilled", {
    kind = fields.kind,
    product_id = fields.product_id,
    fulfilled_now = true,
    inventory_full_after = fields.inventory_full_after == true,
    raw = fields.raw,
  })
end

function purchase_result.deferred(fields)
  fields = fields or {}
  return _new("deferred", { kind = fields.kind, product_id = fields.product_id, raw = fields.raw })
end

function purchase_result.rejected(reason, fields)
  assert(type(reason) == "string" and reason ~= "", "rejected requires a stable reason")
  fields = fields or {}
  return _new("rejected", { reason = reason, raw = fields.raw })
end

function purchase_result.residual(raw)
  return _new("residual", { raw = raw })
end

local function _decode_rejected(raw, fallback_reason)
  return purchase_result.rejected(raw.reason or fallback_reason or "purchase_rejected", { raw = raw })
end

-- ok == true 的两个成交终态;两者都不是则仍属 residual(非可识别终态)。
local function _decode_ok(raw)
  if raw.deferred_fulfillment == true then
    return purchase_result.deferred({ kind = raw.kind, product_id = raw.product_id, raw = raw })
  end
  if raw.fulfilled_now == true then
    return purchase_result.fulfilled({
      kind = raw.kind,
      product_id = raw.product_id,
      inventory_full_after = raw.inventory_full_after == true,
      raw = raw,
    })
  end
  return purchase_result.residual(raw)
end

function purchase_result.canonicalize(raw, fallback_reason)
  if purchase_result.is_result(raw) then
    return raw
  end
  if type(raw) ~= "table" then
    return purchase_result.residual(raw)
  end
  if raw.ok == false then
    return _decode_rejected(raw, fallback_reason)
  end
  if raw.ok == true then
    return _decode_ok(raw)
  end
  return purchase_result.residual(raw)
end

return purchase_result

