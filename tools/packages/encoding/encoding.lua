local _self = debug.getinfo(1, "S").source or "@tools/packages/encoding/encoding.lua"
local _sb = dofile(_self:gsub("\\", "/"):gsub("^@", ""):match("^(.*)/[^/]+$")
  .. "/../../foundation/script_bootstrap.lua")
local env = _sb.install(_self)

local fs_lib = require("foundation.fs")
local path_lib = require("foundation.path")
local proc_lib = require("foundation.proc")
local text_lib = require("foundation.text")

local M = {}

local SUSPICIOUS_CODEPOINTS = {
  [0x00A0] = { replacement = " ", label = "non-breaking space" },
  [0x2007] = { replacement = " ", label = "figure space" },
  [0x2013] = { replacement = "-", label = "en dash" },
  [0x2014] = { replacement = "-", label = "em dash" },
  [0x2018] = { replacement = "'", label = "left single quote" },
  [0x2019] = { replacement = "'", label = "right single quote" },
  [0x201C] = { replacement = '"', label = "left double quote" },
  [0x201D] = { replacement = '"', label = "right double quote" },
  [0x2026] = { replacement = "...", label = "ellipsis" },
  [0x202F] = { replacement = " ", label = "narrow no-break space" },
}

local function _text(zh, en)
  return text_lib.bilingual(zh, en)
end

local function _help_text(command_name)
  local name = tostring(command_name or "tools/packages/encoding/encoding.lua")
  return table.concat({
    "用法:",
    "  lua " .. name .. " check [--root PATH]",
    "  lua " .. name .. " --help",
    "",
    "Usage:",
    "  lua " .. name .. " check [--root PATH]",
    "  lua " .. name .. " --help",
    "",
    "默认扫描 src/**/*.lua，要求文件为 UTF-8，",
    "并拦截注释或英文技术文本中的花式标点。",
    "By default it scans src/**/*.lua, requires UTF-8,",
    "and rejects fancy punctuation in comments or English technical text.",
  }, "\n") .. "\n"
end

local function _parse_args(args)
  local options = {
    command = nil,
    root = "src",
    help = false,
  }

  local index = 1
  if args[1] ~= nil and args[1]:sub(1, 2) ~= "--" then
    options.command = args[1]
    index = 2
  end

  while index <= #args do
    local token = args[index]
    if token == "--help" or token == "-h" then
      options.help = true
    elseif token == "--root" then
      index = index + 1
      options.root = args[index]
    else
      return nil, "unknown flag: " .. tostring(token)
    end
    index = index + 1
  end

  if options.command == nil then
    options.command = "check"
  end

  if options.root == nil or options.root == "" then
    return nil, "--root requires a value"
  end

  return options
end

local function _contains_cjk(text)
  for _, codepoint in utf8.codes(tostring(text or "")) do
    if (codepoint >= 0x3400 and codepoint <= 0x4DBF)
        or (codepoint >= 0x4E00 and codepoint <= 0x9FFF)
        or (codepoint >= 0xF900 and codepoint <= 0xFAFF)
        or (codepoint >= 0x20000 and codepoint <= 0x2A6DF)
        or (codepoint >= 0x2A700 and codepoint <= 0x2B73F)
        or (codepoint >= 0x2B740 and codepoint <= 0x2B81F)
        or (codepoint >= 0x2B820 and codepoint <= 0x2CEAF)
        or (codepoint >= 0x2CEB0 and codepoint <= 0x2EBEF)
    then
      return true
    end
  end
  return false
end

local function _has_ascii_letters(text)
  return tostring(text or ""):find("[A-Za-z]") ~= nil
end

local function _count_codepoints(text)
  local count = utf8.len(text or "")
  if count == nil then
    return 0
  end
  return count
end

local function _read_bytes(path)
  local file = io.open(path, "rb")
  if file ~= nil then
    local content = file:read("*a")
    file:close()
    return content
  end
  return fs_lib.read_file(path)
end

local function _byte_offset_to_line_column(content, offset)
  local normalized_offset = offset
  if normalized_offset == nil or normalized_offset < 1 then
    normalized_offset = 1
  end

  local line_number = 1
  local column_number = 1
  for index = 1, normalized_offset - 1 do
    local byte = content:byte(index)
    if byte == 10 then
      line_number = line_number + 1
      column_number = 1
    else
      column_number = column_number + 1
    end
  end
  return line_number, column_number
end

local function _collect_context_violations(file_path, line_number, base_column, context_kind, text, violations)
  local segment = tostring(text or "")
  if segment == "" or _contains_cjk(segment) or not _has_ascii_letters(segment) then
    return
  end

  local offset = 0
  for _, codepoint in utf8.codes(segment) do
    offset = offset + 1
    local info = SUSPICIOUS_CODEPOINTS[codepoint]
    if info ~= nil then
      violations[#violations + 1] = {
        path = file_path,
        line = line_number,
        column = base_column + offset - 1,
        context = context_kind,
        codepoint = codepoint,
        char = utf8.char(codepoint),
        replacement = info.replacement,
        label = info.label,
      }
    end
  end
end

local function _consume_short_string(line, start_index, quote_char)
  local index = start_index + 1
  while index <= #line do
    local ch = line:sub(index, index)
    if ch == "\\" then
      index = index + 2
    elseif ch == quote_char then
      return index, line:sub(start_index + 1, index - 1)
    else
      index = index + 1
    end
  end
  return nil, nil
end

local function _scan_line_for_violations(file_path, line_number, line, violations)
  local index = 1
  while index <= #line do
    local ch = line:sub(index, index)
    local next_two = line:sub(index, index + 1)

    if next_two == "--" then
      local comment_text = line:sub(index + 2)
      local base_column = _count_codepoints(line:sub(1, index + 1)) + 1
      _collect_context_violations(file_path, line_number, base_column, "comment", comment_text, violations)
      return
    end

    if ch == "'" or ch == '"' then
      local close_index, literal_text = _consume_short_string(line, index, ch)
      if close_index == nil then
        return
      end
      local base_column = _count_codepoints(line:sub(1, index)) + 1
      _collect_context_violations(file_path, line_number, base_column, "string", literal_text, violations)
      index = close_index + 1
    else
      index = index + 1
    end
  end
end

local function _scan_file(file_path)
  local normalized_path = path_lib.normalize_path(file_path)
  local content, read_err = _read_bytes(normalized_path)
  if content == nil then
    return nil, read_err
  end

  local violations = {}
  if content:sub(1, 3) == "\239\187\191" then
    violations[#violations + 1] = {
      path = normalized_path,
      line = 1,
      column = 1,
      kind = "bom",
    }
  end

  local _, invalid_position = utf8.len(content)
  if invalid_position ~= nil then
    local line_number, column_number = _byte_offset_to_line_column(content, invalid_position)
    violations[#violations + 1] = {
      path = normalized_path,
      line = line_number,
      column = column_number,
      kind = "invalid_utf8",
    }
    return violations
  end

  for byte_offset, codepoint in utf8.codes(content) do
    if codepoint >= 0x10000 then
      local line_number, column_number = _byte_offset_to_line_column(content, byte_offset)
      violations[#violations + 1] = {
        path = normalized_path,
        line = line_number,
        column = column_number,
        kind = "non_bmp",
        codepoint = codepoint,
        char = utf8.char(codepoint),
      }
    end
  end

  local line_number = 0
  for line in (content .. "\n"):gmatch("(.-)\n") do
    line_number = line_number + 1
    _scan_line_for_violations(normalized_path, line_number, line, violations)
  end

  return violations
end

local function _collect_targets(root_path)
  local resolved_root = path_lib.resolve_path(env.repo_root, root_path)
  if fs_lib.path_exists(resolved_root) ~= true then
    return nil, _text(
      "路径不存在: " .. tostring(root_path),
      "Path does not exist: " .. tostring(root_path)
    )
  end

  if fs_lib.is_dir(resolved_root) == true then
    return proc_lib.collect_lua_files(resolved_root)
  end

  if resolved_root:match("%.lua$") ~= nil then
    local single_file_path = path_lib.normalize_path(resolved_root)
    return { single_file_path }
  end

  return nil, _text(
    "只支持 Lua 文件或目录: " .. tostring(root_path),
    "Only Lua files or directories are supported: " .. tostring(root_path)
  )
end

local function _codepoint_label(codepoint, char)
  return " U+" .. string.format("%04X", codepoint or 0) .. ' "' .. tostring(char or "") .. '"'
end

local function _format_violation(violation)
  local prefix = table.concat({
    tostring(violation.path or ""),
    tostring(violation.line or 1),
    tostring(violation.column or 1),
  }, ":")

  if violation.kind == "invalid_utf8" then
    return prefix .. ": " .. _text(
      "检测到非法 UTF-8 字节序列",
      "invalid UTF-8 byte sequence"
    )
  end

  if violation.kind == "bom" then
    return prefix .. ": " .. _text(
      "检测到 UTF-8 BOM，Lua 源文件不允许携带 BOM",
      "UTF-8 BOM is not allowed for Lua source files"
    )
  end

  if violation.kind == "non_bmp" then
    return prefix .. ": "
      .. _text(
        "检测到非 BMP 字符（Eggy Lua 加载器不接受 4 字节 UTF-8）",
        "non-BMP character (Eggy Lua loader rejects 4-byte UTF-8)"
      )
      .. _codepoint_label(violation.codepoint, violation.char)
  end

  return prefix .. ": "
    .. _text(
      "检测到可疑字符",
      "suspicious character"
    )
    .. _codepoint_label(violation.codepoint, violation.char)
    .. " in "
    .. tostring(violation.context or "text")
    .. ", "
    .. _text("建议替换为", "replace with")
    .. ' "'
    .. tostring(violation.replacement or "")
    .. '"'
end

function M.run(args, runtime)
  runtime = runtime or {}
  local stdout = runtime.stdout or io.stdout
  local stderr = runtime.stderr or io.stderr

  local options, parse_err = _parse_args(args or arg or {})
  if options == nil then
    stderr:write(tostring(parse_err), "\n")
    return 1
  end

  if options.help then
    stdout:write(_help_text((arg and arg[0]) or "tools/packages/encoding/encoding.lua"))
    return 0
  end

  if options.command ~= "check" then
    stderr:write("unknown command: " .. tostring(options.command) .. "\n")
    return 1
  end

  local targets, collect_err = _collect_targets(options.root)
  if targets == nil then
    stderr:write(tostring(collect_err), "\n")
    return 1
  end

  local violations = {}
  for _, path in ipairs(targets) do
    local file_violations, scan_err = _scan_file(path)
    if file_violations == nil then
      stderr:write(tostring(scan_err), "\n")
      return 1
    end
    for _, violation in ipairs(file_violations) do
      violations[#violations + 1] = violation
    end
  end

  if #violations > 0 then
    stderr:write(_text("编码检查失败", "encoding check failed"), "\n")
    for _, violation in ipairs(violations) do
      stderr:write(_format_violation(violation), "\n")
    end
    stderr:write(_text("违规数量", "violation count") .. ": " .. tostring(#violations) .. "\n")
    return 1
  end

  stdout:write(_text("编码检查通过", "encoding check ok")
    .. ": "
    .. tostring(#targets)
    .. " Lua files\n")
  return 0
end

function M.main()
  return M.run(arg or {})
end

if ... == "tools.packages.encoding.encoding" then
  return M
end

os.exit(M.main())
