-- 纯路径计算:只做字符串演算,不碰文件系统,也不问当前平台。
--
-- 与 foundation.env 里的 current_dir / system_tmp_dir / make_temp_path 划清界限——那几个要读
-- 环境变量、起子进程,属于 IO,不在这里。这条边界的意义是:路径演算可以脱离文件系统
-- 单测,不需要临时目录,也不需要替身。
--
-- 本文件是**全仓唯一**的路径代数叶子(ADR 0083 深化):join / parent / simplify / 绝对判定
-- 只在这里实现一份,runtime_path_ops 与 bootstrap 一律转发过来,不再各写一套。
--
-- 硬约束:**顶层零 require**。bootstrap 会在 package.path 装好之前用 loadfile 取本文件,
-- 那时 require 不可用。需要 to_native_drive 时经 primitives 取(同样零 require),不复制第二份。
-- 取原语叶子:先查 package.loaded,再按本文件位置 dofile,并登记回去。
-- 不能裸 dofile —— 每次 dofile 都会重跑该文件、造出第二套 unique_name 计数器,
-- 临时名就会撞车(test_primitives_shared_instance.lua 钉住这条)。
local function _load_primitives()
  local cached = package.loaded["foundation.primitives"]
  if type(cached) == "table" then
    return cached
  end
  local dir = tostring(debug.getinfo(1, "S").source or ""):gsub("^@", ""):gsub("\\", "/")
    :match("^(.*)/[^/]+$") or "tools/foundation"
  local loaded = assert(dofile(dir .. "/primitives.lua"), "foundation.primitives must sit next to path")
  package.loaded["foundation.primitives"] = loaded
  return loaded
end

local primitives = _load_primitives()

local path = {}

function path.normalize_path(value)
  return (tostring(value or ""):gsub("\\", "/"))
end

-- 绝对路径判定(ADR 0083):内部路径一律是 D:/… / C:/… 正斜杠 Windows 绝对路径,
-- 所以盘符也算绝对路径;POSIX 根 "/" 仍认。UNC(//server/share)不在内部口径内。
function path.is_absolute_path(value)
  local normalized = path.normalize_path(value)
  return normalized:sub(1, 1) == "/" or normalized:match("^%a:/") ~= nil
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

-- 父目录:无父返回 nil。nil 是**契约**,不是缺省值——三个调用点各有各的兜底
-- (fs.lua 的 ensure_dir(nil) 直接成功、arch_policy 补 "."、deploy 补 current_dir()),
-- 在这里替它们选一种就会改写三处语义。
--
-- 名字是 split_parent:它只做"切一段",不承诺结果仍是可用路径。parent_dir 保留为
-- 同义别名(28 个 require("foundation.path") 调用点不动)。
function path.split_parent(value)
  local normalized = path.normalize_path(value)
  return normalized:match("^(.*)/[^/]+$")
end

path.parent_dir = path.split_parent

-- MSYS 形态 /d/dev/... → D:/dev/...(原生 Lua 的 io.open 只认后者)。
-- 实现只有一份,在 primitives 里;这里转发而不是复制,免得两份漂移。
path.to_native_drive = primitives.to_native_drive

-- 段的分割用 gmatch 而不是 foundation.text.split:本文件不能 require。两者在本用途上
-- 等价——split 只是多产出空段,而下面的循环本就丢弃空段。
function path.simplify_path(value)
  local normalized = path.normalize_path(value)
  local prefix = ""
  local remainder = normalized

  if normalized:sub(1, 1) == "/" then
    prefix = "/"
    remainder = normalized:sub(2)
  end

  local parts = {}
  for segment in remainder:gmatch("[^/]+") do
    if segment ~= "." then
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
