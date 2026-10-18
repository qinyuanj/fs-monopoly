local number_utils = require("src.foundation.number")
local role_id_utils = require("src.foundation.identity")

local tip_util = {}

function tip_util.normalize_duration(duration)
  if number_utils.is_numeric(duration) and duration > 0 then
    return duration
  end
  return 2.0
end

function tip_util.normalize_text(text)
  if text == nil then
    return nil
  end
  local ok, value = pcall(tostring, text)
  if not ok then
    return nil
  end
  return value
end

function tip_util.normalize_intent(intent, normalize_duration)
  if type(intent) ~= "table" then
    return nil
  end

  local text = tip_util.normalize_text(intent.text)
  if text == nil then
    return nil
  end

  return {
    text = text,
    duration = normalize_duration(intent.duration),
    dedupe_key = intent.dedupe_key,
    blocks_inter_turn = intent.blocks_inter_turn == true,
    source = intent.source,
    chain_key = intent.chain_key,
    role_id = intent.role_id,
  }
end

function tip_util.resolve_scope(tip_queue, role_id)
  if role_id == nil then
    return tip_queue
  end
  local key = role_id_utils.normalize(role_id)
  if key == nil then
    return tip_queue
  end
  local scope = tip_queue.role_scopes[key]
  if scope == nil then
    scope = { pending = {}, active_tip = nil }
    tip_queue.role_scopes[key] = scope
  end
  return scope
end

function tip_util.each_scope(tip_queue, fn)
  local stop = fn(tip_queue)
  if stop then
    return stop
  end
  for _, scope in pairs(tip_queue.role_scopes) do
    stop = fn(scope)
    if stop then
      return stop
    end
  end
  return nil
end

return tip_util

