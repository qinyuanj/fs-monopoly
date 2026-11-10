require("test.bootstrap").install_package_paths()

local arch_policy = require("packages.arch_policy")
local fs = require("foundation.fs")

-- 仓根 policy.edn 入库并受守卫核对(ADR 0082 第 2、3 条):
-- :proposals / :omit 由 agent 按 uml-viewer 插件规则直接改,本守卫不看;
-- 其余键必须与 arch_policy.project_uml_policy 的投影语义一致(忽略空白、逗号、注释与
-- 顶层键序)。:out 不在投影里,只要求写到已忽略的 tmp/uml/ 下。
-- 层序唯一真源仍是 levels.edn(ADR 0077):policy.edn 只是镜像,不一致就报红。
local M = {}

local _PATH = "policy.edn"
local _FREE_KEYS = { [":proposals"] = true, [":omit"] = true }
local _OUT_KEY = ":out"
local _OUT_PREFIX = "tmp/uml/"
local _HINT = "uml_policy_guard: 层序改 tools/packages/arch_policy/levels.edn,再同步 policy.edn"
  .. "(:proposals/:omit 以外的键是 arch_policy.project_uml_policy 的镜像,ADR 0077 / 0082)"

local _CLOSE = { ["["] = "]", ["{"] = "}", ["("] = ")" }

local function _prefixed(text)
  return "uml_policy_guard: " .. text
end

-- 最小 EDN 读取:把一个 form 规范化成文本,用于语义比较。只需覆盖 uml-viewer policy
-- 的形状(map / vector / list、keyword、string、symbol、数字、布尔、nil);
-- 原子按原文保留。失败以 { line, message } 抛出,由 _read 收口。
local function _reader(text)
  local cursor, length = 1, #text

  local function fail(message, at)
    local _, newlines = text:sub(1, (at or cursor) - 1):gsub("\n", "")
    error({ line = newlines + 1, message = message }, 0)
  end

  local function skip()
    while cursor <= length do
      local c = text:sub(cursor, cursor)
      if c:match("[%s,]") then
        cursor = cursor + 1
      elseif c == ";" then
        local newline = text:find("\n", cursor, true)
        cursor = newline and newline + 1 or length + 1
      else
        return
      end
    end
  end

  local form

  local function sequence(open)
    local start = cursor
    cursor = cursor + 1
    local items = {}
    while true do
      skip()
      local c = text:sub(cursor, cursor)
      if c == "" then fail("unterminated '" .. open .. "'", start) end
      if c == _CLOSE[open] then
        cursor = cursor + 1
        return items
      end
      items[#items + 1] = form()
    end
  end

  form = function()
    skip()
    local start = cursor
    local c = text:sub(cursor, cursor)
    if c == "" then fail("unexpected end of file") end
    if c == '"' then
      cursor = cursor + 1
      while true do
        local d = text:sub(cursor, cursor)
        if d == "" then fail("unterminated string", start) end
        if d == "\\" then
          cursor = cursor + 2
        elseif d == '"' then
          cursor = cursor + 1
          return text:sub(start, cursor - 1)
        else
          cursor = cursor + 1
        end
      end
    end
    if c == "[" or c == "(" then
      return c .. table.concat(sequence(c), " ") .. _CLOSE[c]
    end
    if c == "{" then
      local items = sequence("{")
      if #items % 2 ~= 0 then fail("map literal needs an even number of forms", start) end
      return "{" .. table.concat(items, " ") .. "}"
    end
    if c == "]" or c == "}" or c == ")" or c == "#" or c == "\\" then
      fail("unsupported or unexpected '" .. c .. "'")
    end
    while cursor <= length and not text:sub(cursor, cursor):match("[%s,;\"%[%]{}()]") do
      cursor = cursor + 1
    end
    return text:sub(start, cursor - 1)
  end

  -- 顶层 map -> 有序条目 { { key, value, at }, ... };键必须是 keyword 且不重复。
  local function top_level()
    skip()
    if text:sub(cursor, cursor) ~= "{" then fail("top level must be a map") end
    local start = cursor
    cursor = cursor + 1
    local entries, seen = {}, {}
    while true do
      skip()
      local c = text:sub(cursor, cursor)
      if c == "" then fail("unterminated '{'", start) end
      if c == "}" then
        cursor = cursor + 1
        break
      end
      local at = cursor
      local key = form()
      if not key:match("^:[^/]+$") then fail("top-level key must be a keyword, got " .. key, at) end
      if seen[key] then fail("duplicate key " .. key, at) end
      seen[key] = true
      skip()
      local value_char = text:sub(cursor, cursor)
      if value_char == "}" or value_char == "" then fail("missing value for " .. key, at) end
      entries[#entries + 1] = { key = key, value = form() }
    end
    skip()
    if cursor <= length then fail("unexpected content after the top-level map") end
    return entries
  end

  return top_level
end

local function _read(text, source)
  local ok, entries = pcall(_reader(tostring(text or "")))
  if ok then return entries end
  local detail = type(entries) == "table" and entries or { line = 1, message = tostring(entries) }
  return nil, string.format("%s (line %d): %s", source, detail.line, detail.message)
end

local function _index(entries)
  local values = {}
  for _, entry in ipairs(entries) do values[entry.key] = entry.value end
  return values
end

-- 核心判定(供 spec 注入合成文本;run 走同一逻辑):policy.edn 原文 + 投影原文 ->
-- 违规描述列表;有违规时末行固定是层序真源提示。
function M.check(policy_text, projected_text)
  local projected_entries, projected_err = _read(projected_text, "project_uml_policy")
  if projected_entries == nil then return { _prefixed("invalid projection: " .. projected_err) } end
  local entries, err = _read(policy_text, _PATH)
  if entries == nil then return { _prefixed("invalid " .. err), _HINT } end

  local actual = _index(entries)
  local expected = _index(projected_entries)
  local violations = {}
  for _, entry in ipairs(projected_entries) do
    local value = actual[entry.key]
    if value == nil then
      violations[#violations + 1] = _prefixed("missing key " .. entry.key .. " (expected " .. entry.value .. ")")
    elseif value ~= entry.value then
      violations[#violations + 1] = _prefixed(entry.key .. " differs from project_uml_policy: expected "
        .. entry.value .. ", got " .. value)
    end
  end
  local out = actual[_OUT_KEY]
  if out == nil or out:sub(1, #_OUT_PREFIX + 1) ~= '"' .. _OUT_PREFIX or out:sub(-1) ~= '"' then
    violations[#violations + 1] = _prefixed(_OUT_KEY .. " must be a string under " .. _OUT_PREFIX
      .. " (got " .. tostring(out) .. ")")
  end
  for _, entry in ipairs(entries) do
    if expected[entry.key] == nil and not _FREE_KEYS[entry.key] and entry.key ~= _OUT_KEY then
      violations[#violations + 1] = _prefixed("unexpected key " .. entry.key
        .. " (only the projection, :out, :proposals and :omit are allowed)")
    end
  end
  if #violations > 0 then violations[#violations + 1] = _HINT end
  return violations
end

function M.run()
  local policy, load_err = arch_policy.load(arch_policy.DEFAULT_POLICY_PATH)
  if policy == nil then
    return { ok = false, error = "uml_policy_guard error: " .. tostring(load_err) }
  end
  local text = fs.read_raw(_PATH)
  if text == nil then
    return { ok = false, error = _prefixed("cannot read " .. _PATH) .. "\n" .. _HINT }
  end
  local violations = M.check(text, arch_policy.project_uml_policy(policy))
  if #violations > 0 then
    return { ok = false, error = table.concat(violations, "\n") }
  end
  return { ok = true, message = "uml_policy_guard ok" }
end

return M
