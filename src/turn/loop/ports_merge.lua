-- 端口组合并原语(#602 拆分,自 loop/ports.lua 移出,行为保持):
-- noop 组构造、必填/额外键合并、override 形态判定与组表拷贝。
-- 「有哪些端口组」的数据仍归 ports.lua,这里只回答「怎么并」。
local tables = require("src.foundation.tables")

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

-- 浅拷贝收敛到 foundation.tables.copy_table(同为 nil 容错的浅拷贝原语),
-- 与 #601 ensure_* 归并同向:拷贝循环不再各自拼写。
function M.copy_array(values)
  return tables.copy_table(values)
end

function M.copy_port_groups(port_groups)
  local copied = {}
  for group_name, keys in pairs(port_groups) do
    copied[group_name] = M.copy_array(keys)
  end
  return copied
end

-- 内部守卫的直驱口:base 漂移告警「missing base port」在公开 resolve 路径
-- 不可达(base builders 覆盖全部必填键),经 ports.lua _M_test 转发钉住其契约。
M._merge_required_ports = _merge_required_ports

return M

--[[ mutate4lua-manifest
version=4
projectHash=8be206db14af190d
scope.0.id=chunk:src/turn/loop/ports_merge.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=100
scope.0.semanticHash=a91bfbebff79b36a
scope.1.id=function:<anonymous>
scope.1.kind=function
scope.1.startLine=8
scope.1.endLine=8
scope.1.semanticHash=f5774b2783966d88
scope.2.id=function:M.build_noop_group
scope.2.kind=function
scope.2.startLine=10
scope.2.endLine=19
scope.2.semanticHash=bbff2d3a782e6934
scope.3.id=function:M.resolve_grouped_override
scope.3.kind=function
scope.3.startLine=21
scope.3.endLine=31
scope.3.semanticHash=90cc3803af58c9fe
scope.4.id=function:M.has_legacy_flat_override
scope.4.kind=function
scope.4.startLine=33
scope.4.endLine=45
scope.4.semanticHash=c6ee6065a49bca46
scope.5.id=function:_merge_required_ports
scope.5.kind=function
scope.5.startLine=48
scope.5.endLine=60
scope.5.semanticHash=d5550a183fe7a270
scope.6.id=function:_merge_extra_ports
scope.6.kind=function
scope.6.startLine=63
scope.6.endLine=72
scope.6.semanticHash=78696d8d9528ba54
scope.7.id=function:M.copy_group_ports
scope.7.kind=function
scope.7.startLine=74
scope.7.endLine=79
scope.7.semanticHash=bb18ffc46ebce027
scope.8.id=function:M.copy_array
scope.8.kind=function
scope.8.startLine=83
scope.8.endLine=85
scope.8.semanticHash=f1ce1850b7232305
scope.9.id=function:M.copy_port_groups
scope.9.kind=function
scope.9.startLine=87
scope.9.endLine=93
scope.9.semanticHash=a42861a62f41a049
]]
