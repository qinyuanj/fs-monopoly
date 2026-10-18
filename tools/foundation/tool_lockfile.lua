local text_lib = require("foundation.text")
local path_lib = require("foundation.path")
local fs_lib = require("foundation.fs")

local tool_lockfile = {}

local _TOOL_DEFS = {}

local function _split_fields(line)
  local fields = {}
  -- 第一个 token 是 name,剩余部分是仓库 URL(URL 内部不能有空格)。
  -- 钉版废弃后 URL 是上游 git 仓库地址(#94 起为 GitHub),不再带 tag/rockspec 版本信息。
  local name, url = line:match("^(%S+)%s+(%S+)$")
  if name ~= nil and url ~= nil then
    fields[1] = name
    fields[2] = url
  end
  return fields
end

function tool_lockfile.definition(name)
  return _TOOL_DEFS[name]
end

-- defs 可注入:#147/#148 退役最后两个工具后白名单为空,ensure_tool 机制测试靠注入夹具工具覆盖。
function tool_lockfile.parse_contents(content, defs)
  defs = defs or _TOOL_DEFS
  local tools = {}
  local ordered = {}
  local errors = {}

  local line_no = 0
  for raw_line in (tostring(content or "") .. "\n"):gmatch("(.-)\n") do
    line_no = line_no + 1
    local line = text_lib.trim(raw_line:gsub("#.*$", ""))
    if line ~= "" then
      local fields = _split_fields(line)
      local name, url = fields[1], fields[2]
      if #fields < 2 then
        errors[#errors + 1] = "line " .. tostring(line_no) .. ": expected <name> <url>"
      elseif defs[name] == nil then
        errors[#errors + 1] = "line " .. tostring(line_no) .. ": unknown tool " .. tostring(name)
      elseif tools[name] ~= nil then
        errors[#errors + 1] = "line " .. tostring(line_no) .. ": duplicate tool " .. tostring(name)
      elseif tostring(url):match("^https?://") == nil and tostring(url):match("^git%+http") == nil then
        errors[#errors + 1] = "line " .. tostring(line_no) .. ": invalid url for " .. tostring(name)
      else
        tools[name] = {
          name = name,
          url = url,
        }
        ordered[#ordered + 1] = name
      end
    end
  end

  if #errors > 0 then
    return nil, table.concat(errors, "\n")
  end
  return { tools = tools, ordered = ordered }
end

function tool_lockfile.lock_path(env)
  return path_lib.join_path((env or {}).repo_root or ".", "tools/tools.lock")
end

function tool_lockfile.read_lock(env)
  local path = tool_lockfile.lock_path(env)
  local content, err = fs_lib.read_file(path)
  if content == nil then
    return nil, err
  end
  return tool_lockfile.parse_contents(content, (env or {}).tool_defs)
end

return tool_lockfile
