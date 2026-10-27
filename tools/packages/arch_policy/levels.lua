-- 架构层配置的受限 EDN reader。只服务 packages.arch_policy 的公开加载链，
-- 不接受顶层其他键、namespace 或通用 EDN 值；所有失败都带来源与行号。
local M = {}

local function _parse(text, source)
  local cursor, line = 1, 1
  local length = #text

  local function fail(message, at_line)
    error({ line = at_line or line, message = message }, 0)
  end

  local function skip_space()
    while cursor <= length do
      local ch = text:sub(cursor, cursor)
      if ch == "\n" then
        line = line + 1
        cursor = cursor + 1
      elseif ch == " " or ch == "\t" or ch == "\r" or ch == "," then
        cursor = cursor + 1
      elseif ch == ";" then
        while cursor <= length and text:sub(cursor, cursor) ~= "\n" do
          cursor = cursor + 1
        end
      else
        return
      end
    end
  end

  local function expect(ch)
    skip_space()
    if text:sub(cursor, cursor) ~= ch then
      fail("expected '" .. ch .. "'")
    end
    cursor = cursor + 1
  end

  local function keyword()
    skip_space()
    local at_line = line
    if text:sub(cursor, cursor) ~= ":" then
      fail("expected a component keyword", at_line)
    end
    cursor = cursor + 1
    local first = cursor
    while cursor <= length and not text:sub(cursor, cursor):match("[%s,%[%]{};]") do
      cursor = cursor + 1
    end
    local name = text:sub(first, cursor - 1)
    if not name:match("^[A-Za-z_][A-Za-z0-9_%-]*$") then
      fail("invalid component keyword (namespaces are not supported)", at_line)
    end
    return name, at_line
  end

  skip_space()
  expect("{")
  skip_space()
  if text:sub(cursor, cursor) == "}" then
    fail("missing :levels")
  end

  local groups, lines = {}, {}
  local seen_levels = false
  while true do
    skip_space()
    if cursor > length then fail("unclosed top-level map") end
    if text:sub(cursor, cursor) == "}" then
      cursor = cursor + 1
      break
    end
    local key, key_line = keyword()
    if key ~= "levels" then fail("only the :levels top-level key is allowed", key_line) end
    if seen_levels then fail("duplicate :levels key", key_line) end
    seen_levels = true

    expect("[")
    skip_space()
    if text:sub(cursor, cursor) == "]" then fail(":levels must contain at least one group") end
    while true do
      skip_space()
      if cursor > length then fail("unclosed :levels vector") end
      if text:sub(cursor, cursor) == "]" then
        cursor = cursor + 1
        break
      end
      expect("[")
      local group = {}
      while true do
        skip_space()
        if cursor > length then fail("unclosed level group") end
        if text:sub(cursor, cursor) == "]" then
          cursor = cursor + 1
          break
        end
        local name, name_line = keyword()
        if lines[name] ~= nil then fail("duplicate component :" .. name, name_line) end
        lines[name] = name_line
        group[#group + 1] = name
      end
      if #group == 0 then fail("level groups must not be empty") end
      groups[#groups + 1] = group
    end
  end

  if not seen_levels then fail("missing :levels") end
  skip_space()
  if cursor <= length then fail("trailing content after the top-level map") end
  return groups, lines
end

function M.read(text, source)
  local ok, groups, lines = pcall(_parse, text, source)
  if not ok then
    local detail = type(groups) == "table" and groups or { line = 1, message = tostring(groups) }
    return nil, nil, string.format("%s (line %d): %s", source, detail.line, detail.message)
  end
  return groups, lines
end

return M
