---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/foundation/test/test_skip_flag_contract.lua") end
require("test.bootstrap").install_package_paths()

-- --skip-if-unavailable 入口契约(#129)。#122/#123 让 dry 撤出
-- 平台边界后,该开关仍兼容接受,由各入口经 platform_boundary.strip_skip_flag 消费;
-- 漏给上游会被当成未知选项退 2(cb44141 前 dry 即如此)。
--
-- entries 是保留开关入口的单一真源:增删入口必须同步本清单,否则扫描用例判红。
-- 每个入口真实起进程,带/不带开关各跑一次,断言退出码与核心输出一致、上游收到的
-- argv 完全相同。上游 argv 由 argv_recorder 经 LUA_INIT_5_4 注入观测(只记录不改
-- 行为),按 process:<脚本> 看跨进程转发。
local check = assert
local env_lib = require("foundation.env")
local fs_lib = require("foundation.fs")
local proc_lib = require("foundation.proc")
local boundary = require("foundation.platform_boundary")
local lua = require("foundation.lua54").lua54_bin()

local repo_root = require("foundation.bootstrap").resolve("tools/foundation/test/test_skip_flag_contract.lua").repo_root
local recorder = repo_root .. "/tools/foundation/test/fixtures/skip_flag_contract/argv_recorder.lua"
-- 定义处(含 evaluate 内部调用)不是入口。
local definition = "tools/foundation/platform_boundary.lua"

-- #147/#148 退役 acceptance-mutate 与 dry4lua 后暂无保留开关的入口;清单为空,新增入口时在此登记。
local entries = {}

-- 按标识符出现判调用点,而不是逐行找 strip_skip_flag(:别名调用或函数名与
-- 左括号跨行同样算入口,不能靠换写法绕开清单。
local function _call_sites()
  local files = assert(proc_lib.collect_lua_files(repo_root .. "/tools"))
  local sites = {}
  for _, path in ipairs(files) do
    local relative = path:sub(#repo_root + 2)
    if not relative:find("/test/", 1, true) and relative ~= definition then
      for line in (fs_lib.read_raw(path) or ""):gmatch("[^\n]+") do
        if not line:match("^%s*%-%-") and line:find("strip_skip_flag", 1, true) then
          sites[#sites + 1] = relative
          break
        end
      end
    end
  end
  table.sort(sites)
  return sites
end

local function _manifest_scripts()
  local scripts = {}
  for _, entry in ipairs(entries) do
    scripts[#scripts + 1] = entry.script
  end
  table.sort(scripts)
  return scripts
end

-- 解析 recorder 日志,取第一条匹配 tag 的 argv。
local function _upstream_argv(log_path, tag)
  for line in (fs_lib.read_raw(log_path) or ""):gmatch("[^\n]+") do
    local where, joined = line:match("^([^\t]*)\t(.*)$")
    if where == tag then
      local values = {}
      for value in (joined .. "\31"):gmatch("(.-)\31") do
        values[#values + 1] = value
      end
      return values
    end
  end
  return nil
end

-- 核心输出:去掉 CR 与耗时字段,其余逐字比较。
local function _core(output)
  return (tostring(output):gsub("\r", ""):gsub("elapsed=%d+s", "elapsed=_"))
end

local function _run(entry, root, with_flag)
  local log_path = root .. (with_flag and "/flag.log" or "/plain.log")
  fs_lib.remove_path(root .. "/work")
  local command = { lua, entry.script }
  if with_flag then
    command[#command + 1] = boundary.SKIP_FLAG
  end
  for _, value in ipairs(entry.argv(root)) do
    command[#command + 1] = value
  end
  local result = proc_lib.run_command(command, {
    cwd = repo_root,
    env = { LUA_INIT_5_4 = "@" .. recorder, SKIP_FLAG_CONTRACT_LOG = log_path },
  })
  return result, _upstream_argv(log_path, entry.upstream)
end

local function _with_root(fn)
  local root = env_lib.make_temp_path("skip_flag_contract", ""):gsub("\\", "/")
  fs_lib.remove_path(root)
  assert(fs_lib.ensure_dir(root), "夹具目录建不起来: " .. root)
  local ok, err = xpcall(fn, debug.traceback, root)
  fs_lib.remove_path(root)
  if not ok then
    error(err)
  end
end

describe("skip flag entry contract", function()

it("manifest lists exactly the strip_skip_flag call sites under tools", function()
  check.same(_manifest_scripts(), _call_sites())
end)

for _, entry in ipairs(entries) do
  it(entry.script .. " consumes the flag and forwards identical argv upstream", function()
    _with_root(function(root)
      local plain, plain_argv = _run(entry, root, false)
      local flagged, flagged_argv = _run(entry, root, true)

      check.same(0, plain.code, plain.output)
      check.same(plain.code, flagged.code, flagged.output)
      check.same(_core(plain.output), _core(flagged.output))
      check.is_table(plain_argv, "未观测到上游 " .. entry.upstream .. ":\n" .. plain.output)
      check.is_table(flagged_argv, "未观测到上游 " .. entry.upstream .. ":\n" .. flagged.output)
      check.is_nil(table.concat(flagged_argv, " "):find(boundary.SKIP_FLAG, 1, true),
        "开关漏给了上游 " .. entry.upstream)
      check.same(plain_argv, flagged_argv)
    end)
  end)
end

end)
