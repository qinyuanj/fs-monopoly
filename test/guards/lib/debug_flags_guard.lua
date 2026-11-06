require("test.bootstrap").install_package_paths()

local fs_lib = require("foundation.fs")
local git_query = require("test.guards.lib.git_query")

local M = {}

-- 发布泄出门禁(#265):debug_auto_all_roles 是真人玩家联调开关(开局全席位托管),
-- 必须为 false 发布。联调期本地临时改 true,这条 guard 保证它不会跟着发布跑出去。
local _FLAGS_PATH = "src/config/gameplay/debug_flags.lua"

-- 调试残留:test/**/debug_* 目录里的 spec 会被车道发现,报错却看不出是临时文件;
-- src/** 的 [DEBUG- 标记是真机插桩,必须在提交前清掉。两者都和联调开关一样,
-- 是调试期产物泄进发布面,所以同样判失败而不是告警(guard 车道也只有红绿两态)。
local _DEBUG_MARKER = "[DEBUG-"
local _RESIDUE_SCOPES = { "test", "src" }

-- 纯策略核:给定 tracked 路径表和一个 read(path) -> content|nil 的读取器,返回违规列表。
-- 不碰 git、不碰文件系统——spec 喂合成的「开关被翻成 true」输入验证它真的会红
-- 判定核可注入合成输入，避免门禁只在合规仓库上假绿。
function M.check(paths, read)
  local violations = {}

  for _, path in ipairs(paths) do
    if path == _FLAGS_PATH then
      local content = read(path)
      if content == nil then
        violations[#violations + 1] = "debug_flags_guard: 读不到 " .. path
      else
        local line_no = 0
        for line in (content .. "\n"):gmatch("(.-)\n") do
          line_no = line_no + 1
          -- 先剥注释再判定:注释里的 `debug_auto_all_roles = true` 不算违规。
          local code = line:gsub("%-%-.*$", "")
          if code:match("debug_auto_all_roles%s*=%s*true") then
            violations[#violations + 1] = "debug_flags_guard: " .. path .. ":" .. line_no
              .. " debug_auto_all_roles 必须为 false(联调开关,#265)——改回 false 再发布"
          end
        end
      end
    end
  end

  return violations
end

local function _debug_dir(path)
  local prefix = "test"
  local parent = path:match("^test/(.*)/[^/]+$")
  for segment in tostring(parent or ""):gmatch("[^/]+") do
    prefix = prefix .. "/" .. segment
    if segment:sub(1, 6) == "debug_" then
      return prefix
    end
  end
  return nil
end

local function _marker_violations(path, content, violations)
  local line_no = 0
  for line in (content .. "\n"):gmatch("(.-)\n") do
    line_no = line_no + 1
    if line:find(_DEBUG_MARKER, 1, true) ~= nil then
      violations[#violations + 1] = "debug_flags_guard: " .. path .. ":" .. line_no
        .. " 含调试标记 " .. (line:match("%[DEBUG%-[^%]]*%]") or _DEBUG_MARKER) .. "——提交前清掉插桩"
    end
  end
end

-- 纯策略核:paths 是 test/ 与 src/ 下的 tracked + 未跟踪文件。debug_* 只认目录段,
-- test/guards/lib/debug_flags_guard.lua 这种同前缀文件不算。同目录多个文件只报一条。
function M.check_residue(paths, read)
  local violations = {}
  local file_counts = {}

  for _, path in ipairs(paths) do
    local dir = _debug_dir(path)
    if dir ~= nil then
      file_counts[dir] = (file_counts[dir] or 0) + 1
    end
    if path:sub(1, 4) == "src/" then
      local content = read(path)
      if content == nil then
        violations[#violations + 1] = "debug_flags_guard: 读不到 " .. path
      else
        _marker_violations(path, content, violations)
      end
    end
  end

  for dir, count in pairs(file_counts) do
    violations[#violations + 1] = "debug_flags_guard: " .. dir .. "/ 是调试残留目录(" .. count
      .. " 个文件,含未跟踪)——会被测试车道发现,确认后删除或改名归位"
  end
  table.sort(violations)
  return violations
end

local function _residue_violations()
  local paths = {}
  for _, scope in ipairs(_RESIDUE_SCOPES) do
    local files, err = git_query.list_files(scope)
    if files == nil then
      return { "debug_flags_guard error: " .. tostring(err) }
    end
    table.move(files, 1, #files, #paths + 1, paths)
  end
  return M.check_residue(paths, fs_lib.read_file)
end

-- IO 壳:取 tracked 的 gameplay 配置路径,把真实 reader 交给纯核。
function M.run()
  return git_query.run_tracked_guard("debug_flags_guard", "src/config/gameplay", function(lines)
    local violations = M.check(lines, fs_lib.read_file)
    local residue = _residue_violations()
    return table.move(residue, 1, #residue, #violations + 1, violations)
  end)
end

return M
