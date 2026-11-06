require("test.bootstrap").install_package_paths()

local fs_lib = require("foundation.fs")
local git_query = require("test.guards.lib.git_query")

local M = {}

-- 选择屏装饰节点吸触摸门禁(9e9ae37):Eggy 节点默认吸触摸,装饰节点又不发 CLICK,
-- 漏关触摸就会静默压住下层按钮(遥控骰子屏曾压住基础_取消按钮)。
--
-- 判定口径:
-- 1. 画布归属:Data/UIManagerNodes.lua 判不了。键 "A|B" 的 A 全表同值(346 条都是
--    1519736575,不是画布 ID),B 是节点自身 ID,值只有 {名字, 类型},没有父子信息。
--    因此「属于该屏」= 名字命中 config/choice_touch.lua 的命名前缀,或被该屏 schema /
--    descriptor 引用。盲区:既无前缀又没被 schema 引用的节点(如「标题」「正方形」)
--    归不到任何屏,本 guard 看不见。
-- 2. 选择屏:src/ui/screens 下带 descriptor 的模块(与 screens_registry 同口径),
--    自动发现,新屏未登记规则即判红。market/skin/item_atlas 是 canvas 面,不在此列。
-- 3. 按钮按节点类型 EButton 判,不看名字(「黑市-下一页按钮」就是 ELabel)。
-- 4. 灰底只认 descriptor.underlay(_option_screen 据此关触摸);名字带灰底但没声明的
--    节点没人管,按装饰节点算。
-- 5. 已关触摸只认 descriptor.passthrough_nodes:这才是运行时读的表,schema 写了但没
--    接进 descriptor 不算。这两个字段只有 _option_screen 消费,别的屏声明了也不生效。
-- 6. 每个装饰节点必须进 passthrough,或进 exempt / pending_device_check 并写理由;
--    豁免条目失效(改名、已进 passthrough)即判红,逼着销账。

local _CONFIG_MODULE = "test.guards.config.choice_touch"
local _NODES_MODULE = "Data.UIManagerNodes"
local _SCREENS_DIR = "src/ui/screens"
local _OPTION_SCREEN_REQUIRE = 'require("src.ui.screens._option_screen")'
local _SCHEMA_REQUIRE_PATTERN = 'require%("(src%.ui%.schema%.[%w_]+)"%)'

local function _prefixed(text)
  return "choice_touch_guard: " .. text
end

local function _sorted_keys(map)
  local keys = {}
  for key in pairs(map) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  return keys
end

local function _starts_with(text, prefix)
  return text:sub(1, #prefix) == prefix
end

local function _has_reason(reason)
  return type(reason) == "string" and reason:match("%S") ~= nil
end

local function _collect_declared(value, nodes, out)
  if type(value) == "string" then
    if nodes[value] then
      out[value] = true
    end
  elseif type(value) == "table" then
    for _, item in pairs(value) do
      _collect_declared(item, nodes, out)
    end
  end
end

local function _is_decoration(node_type, name, underlay)
  return node_type ~= "EButton" and node_type ~= "ECanvas" and name ~= underlay
end

local function _decorations(screen, rule, nodes)
  local members = {}
  _collect_declared(screen.schema, nodes, members)
  _collect_declared(screen.descriptor, nodes, members)
  for name in pairs(nodes) do
    for _, prefix in ipairs(rule.prefixes) do
      if _starts_with(name, prefix) then
        members[name] = true
      end
    end
  end
  local decorations = {}
  for name in pairs(members) do
    if _is_decoration(nodes[name], name, screen.descriptor.underlay) then
      decorations[name] = true
    end
  end
  return decorations
end

local function _check_prefixes(key, rule, nodes, violations)
  for _, prefix in ipairs(rule.prefixes) do
    local matched = false
    for name in pairs(nodes) do
      matched = matched or _starts_with(name, prefix)
    end
    if not matched then
      violations[#violations + 1] = _prefixed(key .. " 的前缀 " .. prefix .. " 命中不到任何节点,画布可能已改名")
    end
  end
end

local function _check_passthrough(screen, nodes, passthrough, violations)
  local key = screen.key
  for _, name in ipairs(_sorted_keys(passthrough)) do
    if not nodes[name] then
      violations[#violations + 1] = _prefixed(key .. " 的 passthrough 节点 " .. name .. " 不在 UIManagerNodes 里")
    elseif not _is_decoration(nodes[name], name, screen.descriptor.underlay) then
      violations[#violations + 1] = _prefixed(key .. " 的 passthrough 不得含按钮或灰底:" .. name .. " 会被关触摸")
    end
  end
  local declares_touch_nodes = next(passthrough) ~= nil or screen.descriptor.underlay
  if declares_touch_nodes and not screen.uses_option_screen then
    violations[#violations + 1] = _prefixed(key .. " 声明了 passthrough/underlay,但开屏不走 _option_screen,声明不生效")
  end
end

local function _check_table(key, label, entries, decorations, passthrough, violations)
  for _, name in ipairs(_sorted_keys(entries)) do
    if not decorations[name] or passthrough[name] then
      violations[#violations + 1] = _prefixed(key .. " 的 " .. label .. " 条目过期:" .. name .. " 不再是待处理的装饰节点,删掉")
    elseif not _has_reason(entries[name]) then
      violations[#violations + 1] = _prefixed(key .. " 的 " .. label .. " 条目 " .. name .. " 缺理由")
    end
  end
end

local function _check_screen(screen, rule, nodes, violations)
  local key = screen.key
  local passthrough = {}
  for _, name in ipairs(screen.descriptor.passthrough_nodes or {}) do
    passthrough[name] = true
  end
  local decorations = _decorations(screen, rule, nodes)
  _check_prefixes(key, rule, nodes, violations)
  _check_passthrough(screen, nodes, passthrough, violations)
  _check_table(key, "exempt", rule.exempt, decorations, passthrough, violations)
  _check_table(key, "pending_device_check", rule.pending_device_check, decorations, passthrough, violations)
  for _, name in ipairs(_sorted_keys(decorations)) do
    if not (passthrough[name] or rule.exempt[name] or rule.pending_device_check[name]) then
      violations[#violations + 1] = _prefixed(key .. " 的装饰节点 " .. name
        .. " 默认吸触摸且不发 CLICK:列进 schema 的 passthrough,或列进 config/choice_touch.lua 的豁免表并写理由")
    end
  end
end

-- 纯策略核:input = { nodes = {名字 → 类型}, screens = {{key, descriptor, schema, uses_option_screen}},
-- rules = {key → {prefixes, exempt, pending_device_check}} },返回违规描述列表。
function M.check(input)
  local violations = {}
  local seen = {}
  for _, screen in ipairs(input.screens) do
    seen[screen.key] = true
    local rule = input.rules[screen.key]
    if rule then
      _check_screen(screen, rule, input.nodes, violations)
    else
      violations[#violations + 1] = _prefixed("选择屏 " .. screen.key .. " 未登记:在 config/choice_touch.lua 写明命名前缀")
    end
  end
  for _, key in ipairs(_sorted_keys(input.rules)) do
    if not seen[key] then
      violations[#violations + 1] = _prefixed("规则 " .. key .. " 过期:没有对应的选择屏")
    end
  end
  return violations
end

local function _index_nodes(raw_nodes)
  local nodes = {}
  for _, entry in pairs(raw_nodes) do
    if type(entry) == "table" then
      nodes[entry[1]] = entry[2]
    end
  end
  return nodes
end

local function _load_screen(path, source)
  local module_name = path:gsub("%.lua$", ""):gsub("/", ".")
  local screen = require(module_name)
  local schema_module = source:match(_SCHEMA_REQUIRE_PATTERN)
  return {
    key = screen.key,
    descriptor = screen.descriptor(),
    schema = schema_module and require(schema_module) or {},
    uses_option_screen = source:find(_OPTION_SCREEN_REQUIRE, 1, true) ~= nil,
  }
end

-- IO 壳:读真实节点表、发现选择屏、装载规则。descriptor 每次新建,调用方可就地改。
function M.load_input()
  local paths, err = git_query.list_files(_SCREENS_DIR)
  assert(paths ~= nil, err)
  table.sort(paths)
  local screens = {}
  for _, path in ipairs(paths) do
    local source = path:match("%.lua$") and assert(fs_lib.read_file(path)) or ""
    if source:find("function M.descriptor", 1, true) then
      screens[#screens + 1] = _load_screen(path, source)
    end
  end
  return {
    nodes = _index_nodes(require(_NODES_MODULE)),
    screens = screens,
    rules = require(_CONFIG_MODULE).screens,
  }
end

function M.run()
  local violations = M.check(M.load_input())
  if #violations > 0 then
    return { ok = false, error = table.concat(violations, "\n") }
  end
  return { ok = true, message = "choice_touch_guard ok" }
end

return M
