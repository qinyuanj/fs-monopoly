---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/packages/ops/test/test_deploy_native.lua") end
require("test.bootstrap").install_package_paths()
local check = require("luassert")
local env = require("foundation.env")
local fs = require("foundation.fs")
local deploy = require("tools.packages.ops.deploy")

describe("native deploy copy sandbox", function()

local function sandbox(fn)
  local root = env.make_temp_path("deploy_native_中文 空格_", "")
  fs.ensure_dir(root)
  local ok, err = xpcall(function() fn(root) end, debug.traceback)
  fs.remove_path(root)
  if not ok then error(err) end
end

it("missing source preserves existing target", function()
  sandbox(function(root)
    assert(fs.write_file(root .. "/target/保留.txt", "keep"))
    check.has_error(function()
      deploy.copy_directory_tree(root .. "/missing", root .. "/target")
    end)
    check.same("keep", fs.read_raw(root .. "/target/保留.txt"))
  end)
end)

-- robocopy /MIR 的命令形态:源/目标都是正斜杠 Windows 绝对路径,开关不被 MSYS 改写。
it("robocopy command is the native mirror form", function()
  local command = deploy.robocopy_command("C:/repo/src", "C:/Users/x/Desktop/dev/eggy/LuaSource_大富翁/src")
  check.truthy(command:find("robocopy", 1, true), command)
  check.truthy(command:find("'C:/repo/src'", 1, true), command)
  check.truthy(command:find("'C:/Users/x/Desktop/dev/eggy/LuaSource_大富翁/src'", 1, true), command)
  check.truthy(command:find("/MIR", 1, true), command)
  -- 开关保持裸形:经 MSYS 系 bash 时 /MIR 会被改写成 C:/Program Files/Git/MIR,
  -- 命令前置这两个变量关掉参数转换。
  check.truthy(command:find("MSYS2_ARG_CONV_EXCL", 1, true), command)
  check.truthy(command:find("MSYS_NO_PATHCONV", 1, true), command)
  check.is_nil(command:find("wslpath", 1, true), command)
  check.is_nil(command:find("/mnt/c", 1, true), command)
end)

-- 真跑一次 robocopy:钉住「目标侧陈旧项消失、源侧隐藏项与空目录保留、字节原样」。
it("real mirror preserves bytes and removes stale files", function()
  sandbox(function(root)
    assert(fs.write_file(root .. "/source/子 目录/中文.lua", "return '中文'\n"))
    assert(fs.write_file(root .. "/source/.hidden", "\0binary\255"))
    fs.ensure_dir(root .. "/source/空目录")
    assert(fs.write_file(root .. "/target/stale.txt", "stale"))
    deploy.copy_directory_tree(root .. "/source", root .. "/target")
    check.same("return '中文'\n", fs.read_raw(root .. "/target/子 目录/中文.lua"))
    check.same("\0binary\255", fs.read_raw(root .. "/target/.hidden"))
    check.is_true(fs.is_dir(root .. "/target/空目录"))
    check.is_false(fs.path_exists(root .. "/target/stale.txt"))
    -- 第二次跑:无变化时 robocopy 退 0,不得被判成失败。
    deploy.copy_directory_tree(root .. "/source", root .. "/target")
    check.same("\0binary\255", fs.read_raw(root .. "/target/.hidden"))
  end)
end)

-- 二进制逐字节复制:CRLF 与 NUL 必须原样落盘。
it("binary bytes survive the copy", function()
  sandbox(function(root)
    local payload = "line\r\nline\r\n\0\1\2\255"
    assert(fs.write_file(root .. "/source/raw.bin", payload))
    deploy.copy_directory_tree(root .. "/source", root .. "/target")
    check.same(payload, fs.read_raw(root .. "/target/raw.bin"))
  end)
end)

it("project root resolves current repository", function()
  check.same(env.current_dir(), deploy.resolve_project_root())
end)

-- 家目录桩成固定值:真实解析读本机 %USERPROFILE%,落点随机器变(ADR 0083)。
it("default target retains the Windows deploy location", function()
  local original = deploy.resolve_home_dir
  deploy.resolve_home_dir = function() return "C:/Users/玩家/" end
  local ok, target = pcall(deploy.resolve_default_target_path)
  deploy.resolve_home_dir = original
  check.is_true(ok, target)
  check.same("C:/Users/玩家/Desktop/dev/eggy/LuaSource_大富翁", target)
end)

-- 取不到家目录是不可用(退 3),不是部署失败:这里钉 (nil, 原因) 的返回形态。
it("default target reports an unresolvable home instead of failing the deploy", function()
  local original = deploy.resolve_home_dir
  deploy.resolve_home_dir = function() return "" end
  local ok, target, reason = pcall(deploy.resolve_default_target_path)
  deploy.resolve_home_dir = original
  check.is_true(ok, target)
  check.is_nil(target)
  check.truthy(tostring(reason):find("USERPROFILE", 1, true), tostring(reason))
end)

it("project root resolves from other working directory", function()
  sandbox(function(root)
    local proc = require("foundation.proc")
    local repo = env.current_dir()
    local script = "package.path=" .. string.format("%q", repo .. "/?.lua;" .. repo .. "/tools/?.lua;")
      .. "..package.path; io.write(require('tools.packages.ops.deploy').resolve_project_root())"
    assert(fs.write_file(root .. "/root_driver.lua", script))
    local result = proc.run_command({ require("foundation.lua54").lua54_bin(), root .. "/root_driver.lua" }, { cwd = root })
    check.is_true(result.ok, result.output)
    check.same(repo, result.output)
  end)
end)

end)
