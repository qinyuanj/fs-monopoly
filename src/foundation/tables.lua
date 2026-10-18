local M = {}

function M.copy(value)
  if type(value) ~= "table" then
    return value
  end
  local out = {}
  for key, child in pairs(value) do
    out[key] = M.copy(child)
  end
  return out
end

function M.copy_table(value)
  if type(value) ~= "table" then
    return {}
  end
  local out = {}
  for key, child in pairs(value) do
    out[key] = child
  end
  return out
end

function M.contains(list, value)
  if type(list) ~= "table" then
    return false
  end
  for _, current in ipairs(list) do
    if current == value then
      return true
    end
  end
  return false
end

function M.join_or_default(list, separator, default_value)
  if type(list) ~= "table" or #list == 0 then
    return default_value
  end
  return table.concat(list, separator)
end

function M.ensure_table_field(t, key)
  if type(t[key]) ~= "table" then
    t[key] = {}
  end
  return t[key]
end

-- 字段为 nil 时填入任意默认值并返回现值;已有值(含 false)原样保留。
function M.ensure_field(t, key, fallback)
  if t[key] == nil then
    t[key] = fallback
  end
  return t[key]
end

-- 只在字段缺席(nil)时补空表,已有的非表值保持原样交回调用方。与
-- ensure_table_field 不同:那个会把非表值悄悄换成空表,这里不会掩盖类型错误。
function M.ensure_absent_field(t, key)
  local value = t[key]
  if value == nil then
    value = {}
    t[key] = value
  end
  return value
end

-- 容器可能缺席时的安全下标读取:非表容器与缺失下标统一落 nil。
function M.at(container, index)
  if type(container) == "table" and container[index] ~= nil then
    return container[index]
  end
  return nil
end

return M

