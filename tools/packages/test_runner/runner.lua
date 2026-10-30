-- 直跑入口的解释器预检(#191 故事 3):与 tools/cli.lua 同口径,非 5.4 立即退 1。
if _VERSION ~= "Lua 5.4" then
  io.stderr:write("Lua 5.4 interpreter required; run `lua5.4 tools/cli.lua <子命令>` (found " .. tostring(_VERSION) .. ")\n")
  os.exit(1)
end
local source = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("\\", "/")
local root = source:match("^(.*)/tools/packages/test_runner/runner.lua$") or "."
-- #139: lanes merge stderr into stdout. Redirected stdout is block-buffered
-- while stderr is not, so finish every write before later stderr.
io.stdout:setvbuf("no")
local bootstrap = dofile(root .. "/tools/foundation/bootstrap.lua")
local env = bootstrap.install(source)
root = env.repo_root
local proc = require("foundation.proc")
local fs = require("foundation.fs")
local spec_sharding = require("foundation.spec_sharding")
if require("foundation.tool_cli").help_exit(arg, require("packages.test_runner.cli").usage) ~= nil then
  os.exit(0)
end
local opts = { files = {}, roots = {}, arguments = {} }
local after, index = false, 1
while index <= #arg do
  local value = arg[index]
  if after then opts.files[#opts.files + 1] = value
  elseif value == "--" then after = true; opts.explicit_files = true
  elseif value:match("^%-%-file%-list=") then
    opts.explicit_files = true
    local count = #opts.files
    local list = assert(io.open(value:match("=(.*)$"), "rb"))
    for file in list:lines() do
      file = file:gsub("\r$", "")
      assert(file ~= "" and file:match("%.lua$") and not file:find("%z"), "invalid file identity")
      opts.files[#opts.files + 1] = file
    end
    list:close()
    assert(#opts.files > count, "empty spec file list")
  elseif value:match("^%-%-durations%-out=") then opts.durations_out = value:match("=(.*)$")
  elseif value == "--run" or value == "--output" or value == "--helper" or value == "--pattern" then
    index = index + 1
    local name = value:sub(3)
    opts[name] = assert(arg[index], "missing " .. value .. " value")
  elseif value:match("^%-%-run=") or value:match("^%-%-output=") or value:match("^%-%-helper=") or value:match("^%-%-pattern=") then
    local name, parameter = value:match("^%-%-([%w]+)=(.*)$")
    opts[name] = parameter
  elseif value == "-Xoutput" then
    index = index + 1; opts.arguments[#opts.arguments + 1] = arg[index]
  else opts.roots[#opts.roots + 1] = value end
  index = index + 1
end
local profiles = assert(loadfile(root .. "/tools/packages/spec_lane/spec_profiles.lua"))()
local profile = profiles[opts.run or "default"]
if not profile then
  assert(fs.is_dir(opts.run), "unknown profile: " .. tostring(opts.run))
  profile = { ROOT = { opts.run }, helper = profiles.behavior.helper, output = profiles.behavior.output, pattern = profiles.behavior.pattern }
end
opts.helper = opts.helper or profile.helper
opts.output = opts.output or profile.output or "TAP"
opts.pattern = opts.pattern or profile.pattern or "test_"
local profile_output_args = profile.Xoutput or {}
if type(profile_output_args) == "string" then profile_output_args = { profile_output_args } end
for _, value in ipairs(profile_output_args) do
  opts.arguments[#opts.arguments + 1] = value
end
local targets = opts.roots
if not opts.explicit_files and #opts.files == 0 and #targets == 0 then targets = profile.ROOT or { "test" } end
for _, target in ipairs(targets) do
  if target:match("%.lua$") then opts.files[#opts.files + 1] = target
  else
    for _, file in ipairs(proc.collect_files(target, ".lua") or {}) do
      local base = file:match("([^/\\]+)%.lua$")
      if base and base:find(opts.pattern) then opts.files[#opts.files + 1] = file end
    end
  end
end
local ok, err = pcall(function()
  assert(#opts.files > 0, "no spec files selected")
  local files, seen = {}, {}
  for _, file in ipairs(opts.files) do
    local identity = file:gsub("\\", "/"):gsub("^%./", "")
    assert(not seen[identity], "duplicate file identity: " .. identity)
    seen[identity] = true
    local handle = assert(io.open(file, "rb"), "missing file identity: " .. file)
    handle:close()
    files[#files + 1] = file
  end
  assert(#files > 0, "no available spec files selected")
  -- 受控 Lua 环境预检(#151):busted / luassert 只从机器 LuaRocks tree 装载,
  -- 版本口径不满足是真实失败(退 1),不再在项目内自举安装。
  local lua_env = require("foundation.lua_env")
  local verified_env, env_err, env_info = lua_env.preflight()
  assert(verified_env, env_err)
  lua_env.install_paths(env_info.roots)
  require("packages.test_runner.cache_loader").install(root)
  -- --durations-out:busted file start/end 事件之间的墙钟秒数,取 busted.monotime
  -- (受控 Lua 环境里 luasystem 的单调时钟,busted 自身计时同源);os.clock 是进程
  -- CPU 时间,会把等待子进程的 spec 记成近 0。格式见 spec_sharding.format_durations,
  -- 供 spec_lane 实测时长缓存分片(#107)。
  local configure, durations
  if opts.durations_out then
    durations = {}
    configure = function(busted)
      local started = {}
      busted.subscribe({ "file", "start" }, function(file)
        started[file.name] = busted.monotime()
        return nil, true
      end)
      busted.subscribe({ "file", "end" }, function(file)
        if started[file.name] then durations[file.name] = busted.monotime() - started[file.name] end
        return nil, true
      end)
    end
  end
  local total = require("packages.test_runner.busted_backend").run(files, opts.helper, opts.output, opts.arguments, configure)
  if durations then assert(fs.write_file(opts.durations_out, spec_sharding.format_durations(durations))) end
  io.write(string.format("# COUNTS: files=%d cases=%d passed=%d failed=%d errors=%d\n", total.files, total.cases, total.passed, total.failed, total.errors))
  if total.cases == 0 then io.stderr:write("test_runner: busted backend empty result\n") end
  if total.cases == 0 or total.failed + total.errors > 0 then os.exit(1) end
end)
if not ok then io.stderr:write("test_runner: " .. tostring(err) .. "\n"); os.exit(1) end
