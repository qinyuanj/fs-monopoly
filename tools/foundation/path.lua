-- 纯路径计算:只做字符串演算,不碰文件系统,也不问当前平台。
--
-- 与 foundation.env 里的 current_dir / system_tmp_dir / make_temp_path 划清界限——那几个要读
-- 环境变量、起子进程,属于 IO,不在这里。这条边界的意义是:路径演算可以脱离文件系统
-- 单测,不需要临时目录,也不需要替身。
local text = require("foundation.text")

local path = {}

function path.normalize_path(value)
  return (tostring(value or ""):gsub("\\", "/"))
end

function path.is_absolute_path(value)
  return path.normalize_path(value):sub(1, 1) == "/"
end

-- 变参逐段左折。段数不设上限:写几段就得几段,不静默丢参(issue #211)。
--
-- 段的收集走 select("#", ...) 而非 ipairs({...}):nil 段是合法输入(与
-- normalize_path(nil) 折成空串同一口径),而 ipairs 遇 nil 洞会提前截断,把后面的段
-- 一并吞掉——那正是本函数原先的失败模式换个马甲。
function path.join_path(...)
  local result = ""
  for index = 1, select("#", ...) do
    local segment = path.normalize_path((select(index, ...)))
    if result == "" then
      result = segment
    elseif segment ~= "" then
      result = result:gsub("/+$", "") .. "/" .. segment:gsub("^/+", "")
    end
  end
  return result
end

function path.parent_dir(value)
  local normalized = path.normalize_path(value)
  return normalized:match("^(.*)/[^/]+$")
end

function path.simplify_path(value)
  local normalized = path.normalize_path(value)
  local prefix = ""
  local remainder = normalized

  if normalized:sub(1, 1) == "/" then
    prefix = "/"
    remainder = normalized:sub(2)
  end

  local parts = {}
  for _, segment in ipairs(text.split(remainder, "/")) do
    if segment ~= "" and segment ~= "." then
      if segment == ".." then
        if #parts > 0 and parts[#parts] ~= ".." then
          parts[#parts] = nil
        elseif prefix == "" then
          parts[#parts + 1] = segment
        end
      else
        parts[#parts + 1] = segment
      end
    end
  end

  local simplified = table.concat(parts, "/")
  if prefix == "" then
    return simplified
  end
  return "/" .. simplified
end

function path.resolve_path(base, value)
  local normalized_path = path.normalize_path(value)
  if normalized_path == "" then
    return path.simplify_path(base)
  end
  if path.is_absolute_path(normalized_path) then
    return path.simplify_path(normalized_path)
  end
  return path.simplify_path(path.join_path(base or "", normalized_path))
end

return path
