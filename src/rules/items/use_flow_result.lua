local result = {}

local function _build_result(base, extra)
  for key, value in pairs(extra or {}) do
    base[key] = value
  end
  return base
end

function result.rejected(reason, extra)
  return _build_result({
    ok = false,
    status = "rejected",
    reason = reason,
  }, extra)
end

local function _choice_spec_from_result(raw_result)
  local intent = type(raw_result) == "table" and raw_result.intent or nil
  return type(intent) == "table" and intent.choice_spec or nil
end

local function _waiting_choice(raw_result, player, item_id)
  local choice_spec = _choice_spec_from_result(raw_result)
  return {
    ok = true,
    status = "waiting_choice",
    waiting = true,
    actor = player,
    actor_id = player and player.id or nil,
    item_id = item_id,
    item_consumed = false,
    choice_spec = choice_spec,
    choice = choice_spec,
    intent = type(raw_result) == "table" and raw_result.intent or nil,
    result = raw_result,
  }
end

-- 效果路径的结果已全部经 settlement 结算(_settled_item_use 冻结封套);
-- 这里只放行结算结果、把 waiting 包装为 begin/resolve seam 的 waiting_choice 封套。
function result.normalize_effect(raw_result, player, item_id)
  if type(raw_result) == "table" and raw_result._settled_item_use == true then
    return raw_result
  end
  if type(raw_result) == "table" and raw_result.waiting == true then
    return _waiting_choice(raw_result, player, item_id)
  end
  error("unsettled item effect result: " .. tostring(raw_result))
end

return result

