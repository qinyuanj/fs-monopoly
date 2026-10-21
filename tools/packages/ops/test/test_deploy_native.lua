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
    deploy.copy_directory_tree(root .. "/source", root .. "/target")
    check.same("\0binary\255", fs.read_raw(root .. "/target/.hidden"))
  end)
end)

-- 二进制逐块复制:CRLF 与 NUL 必须原样落盘(按行读会改写它们)。
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

it("default target retains the Windows deploy location", function()
  local home = deploy.resolve_home_dir():gsub("/$", "")
  check.same(home .. "/Desktop/dev/eggy/LuaSource_大富翁", deploy.resolve_default_target_path("win"))
end)

it("project root resolves from other working directory", function()
  sandbox(function(root)
    local proc = require("foundation.proc")
    local repo = env.current_dir()
    local script = "package.path=" .. string.format("%q", repo .. "/?.lua;")
      .. "..package.path; io.write(require('tools.packages.ops.deploy').resolve_project_root())"
    assert(fs.write_file(root .. "/root_driver.lua", script))
    local result = proc.run_command({ require("foundation.lua54").lua54_bin(), root .. "/root_driver.lua" }, { cwd = root })
    check.is_true(result.ok, result.output)
    check.same(repo, result.output)
  end)
end)

end)
