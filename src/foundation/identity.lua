local number_utils = require("src.foundation.number")

local role_id = {}

local function _normalized_integer(value)
  return number_utils.to_integer(value)
end

local function _text_fallback(value)
  local ok, as_text = pcall(tostring, value)
  if ok and type(as_text) == "string" and as_text ~= "" then
    return as_text
  end
  return nil
end

function role_id.normalize(value)
  if value == nil then
    return nil
  end
  local normalized = _normalized_integer(value)
  if normalized ~= nil then
    return normalized
  end
  if type(value) == "string" then
    return value
  end
  return _text_fallback(value)
end

function role_id.equals(left, right)
  -- 直接比较规范化值：nil == non-nil 在 Lua 中恒为 false（等价于显式 nil 守卫），
  -- nil == nil 为 true（两个未知身份视为同一身份）。无需显式 nil guard。
  return role_id.normalize(left) == role_id.normalize(right)
end

-- Looks the normalized id up both as-is and as text, since maps may be keyed either way.
local function _read_normalized(map, normalized)
  if normalized == nil then
    return nil
  end
  local value = map[normalized]
  if value ~= nil then
    return value
  end
  return map[tostring(normalized)]
end

function role_id.read(map, key)
  if type(map) ~= "table" then
    return nil
  end
  local value = _read_normalized(map, role_id.normalize(key))
  if value ~= nil then
    return value
  end
  if key ~= nil then
    return map[key]
  end
  return nil
end

function role_id.write(map, key, value)
  if type(map) ~= "table" then
    return nil
  end
  local normalized = role_id.normalize(key)
  if normalized == nil then
    return nil
  end
  map[normalized] = value
  if type(normalized) ~= "string" then
    map[tostring(normalized)] = nil
  end
  return normalized
end

return role_id

