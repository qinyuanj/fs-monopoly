-- 端口组合并原语(#602 拆分,自 loop/ports.lua 移出,行为保持):
-- noop 组构造、必填/额外键合并、override 形态判定与组表拷贝。
-- 「有哪些端口组」的数据仍归 ports.lua,这里只回答「怎么并」。

local M = {}

local _noop = function() end

function M.build_noop_group(keys, overrides)
  local group = {}
  for _, key in ipairs(keys or {}) do
    group[key] = _noop
  end
  for key, fn in pairs(overrides or {}) do
    group[key] = fn
  end
  return group
end

function M.resolve_grouped_override(override_ports, group_names)
  if type(override_ports) ~= "table" then
    return nil
  end
  for _, group_name in ipairs(group_names) do
    if type(override_ports[group_name]) == "table" then
      return override_ports
    end
  end
  return nil
end

-- 必填端口：override 给了函数就用 override，否则用 base；base 缺失即报错。
local function _merge_required_ports(merged, base_group, override_group, required_keys)
  for _, key in ipairs(required_keys) do
    local fn = base_group[key]
    if type(fn) ~= "function" then
      error("missing base port: " .. tostring(key))
    end
    if override_group and type(override_group[key]) == "function" then
      merged[key] = override_group[key]
    else
      merged[key] = fn
    end
  end
end

-- override 里的非必填键原样透传，不覆盖已合并的必填端口。
local function _merge_extra_ports(merged, override_group)
  if type(override_group) ~= "table" then
    return
  end
  for key, value in pairs(override_group) do
    if merged[key] == nil then
      merged[key] = value
    end
  end
end

function M.copy_group_ports(base_group, override_group, required_keys)
  local merged = {}
  _merge_required_ports(merged, base_group, override_group, required_keys)
  _merge_extra_ports(merged, override_group)
  return merged
end

return M

