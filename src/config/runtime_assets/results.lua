local state = require("src.config.runtime_assets.state")

local M = {}

function M.key(value)
  if value == nil then
    return nil
  end
  return tostring(value)
end

function M.result(meaning, fields)
  local out = fields or {}
  out.meaning = meaning
  out.ok = out.ok ~= false
  return out
end

function M.missing(meaning, reason, fields)
  local out = fields or {}
  out.meaning = meaning
  out.ok = false
  out.reason = reason
  return out
end

function M.image_result(meaning, raw_key, reason, opts)
  local lookup_key = M.key(raw_key)
  local image_key = raw_key ~= nil and state.images(opts)[lookup_key] or nil
  if image_key == nil then
    return M.missing(meaning, reason, {
      lookup_key = lookup_key,
    })
  end
  return M.result(meaning, {
    image_key = image_key,
    asset_id = image_key,
    lookup_key = lookup_key,
    fallback_used = false,
  })
end

return M

