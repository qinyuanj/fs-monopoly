---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/packages/ops/test/test_deploy_diff.lua") end
require("test.bootstrap").install_package_paths()

-- deploy-diff 的聚焦单测:判定走假 fs 与注入的互操作探测,不访问 /mnt/c;
-- 只有与 deploy.copy_payload 的往返用例落真实沙箱,目录都在系统临时区。
local check = require("luassert")
local env_lib = require("foundation.env")
local fs_lib = require("foundation.fs")
local proc_lib = require("foundation.proc")
local deploy = require("packages.ops.deploy")
local deploy_diff = require("packages.ops.deploy_diff")

local _WORK = "/work"
local _HOME = "/fake/home"
local _TARGET = _HOME .. "/Desktop/dev/eggy/LuaSource_大富翁"

local function _sink()
  local chunks = {}
  return {
    write = function(_, text)
      chunks[#chunks + 1] = text
    end,
    text = function()
      return table.concat(chunks)
    end,
  }
end

-- files: 绝对路径 → 内容。目录由路径前缀隐含。
local function _fake_fs(files)
  local function is_dir(path)
    for file_path in pairs(files) do
      if file_path:sub(1, #path + 1) == path .. "/" then
        return true
      end
    end
    return false
  end
  return {
    is_dir = is_dir,
    path_exists = function(path)
      return files[path] ~= nil or is_dir(path)
    end,
    read = function(path)
      local content = files[path]
      return content ~= false and content or nil
    end,
    list_files = function(root)
      local listed = {}
      for file_path in pairs(files) do
        if file_path:sub(1, #root + 1) == root .. "/" then
          listed[#listed + 1] = file_path
        end
      end
      table.sort(listed)
      return listed
    end,
  }
end

local function _payload(root, overrides)
  local files = {
    [root .. "/src/a.lua"] = "return 1\n",
    [root .. "/src/sub/b.lua"] = "return 2\n",
    [root .. "/main.lua"] = "require('src.a')\n",
    [root .. "/Data/UIManagerNodes.lua"] = "return {}\n",
    [root .. "/Data/Prefab.lua"] = "return {}\n",
  }
  for path, content in pairs(overrides or {}) do
    files[root .. "/" .. path] = content or nil
  end
  return files
end

local function _merged(...)
  local files = {}
  for _, part in ipairs({ ... }) do
    for path, content in pairs(part) do
      files[path] = content
    end
  end
  return files
end

local function _run(files, overrides)
  local stdout, stderr = _sink(), _sink()
  local env = {
    detect_interop = function()
      return {}
    end,
    resolve_home = function()
      return _HOME
    end,
    project_root = _WORK,
    fs = _fake_fs(files),
    stdout = stdout,
    stderr = stderr,
  }
  for key, value in pairs(overrides or {}) do
    env[key] = value
  end
  local code = deploy_diff.main({}, env)
  return code, stdout.text(), stderr.text()
end

describe("deploy-diff read-only drift check", function()

it("identical payloads exit 0 and print the resolved target", function()
  local code, stdout = _run(_merged(_payload(_WORK), _payload(_TARGET)))
  check.equal(0, code)
  check.truthy(stdout:find("Deploy target: " .. _TARGET, 1, true), stdout)
  check.truthy(stdout:find("Compared: 5 file(s)", 1, true), stdout)
  check.truthy(stdout:find("OK:", 1, true), stdout)
end)

it("a one-line difference exits 1 and names the file", function()
  local code, stdout = _run(_merged(
    _payload(_WORK),
    _payload(_TARGET, { ["src/sub/b.lua"] = "return 2\nprint('debug')\n" })
  ))
  check.equal(1, code)
  check.truthy(stdout:find("DRIFT: 1 file(s)", 1, true), stdout)
  check.truthy(stdout:find("differs: src/sub/b.lua", 1, true), stdout)
end)

it("line endings count as drift because the comparison is byte exact", function()
  local code, stdout = _run(_merged(
    _payload(_WORK),
    _payload(_TARGET, { ["main.lua"] = "require('src.a')\r\n" })
  ))
  check.equal(1, code)
  check.truthy(stdout:find("differs: main.lua", 1, true), stdout)
end)

it("reports each payload single file", function()
  local code, stdout = _run(_merged(
    _payload(_WORK),
    _payload(_TARGET, {
      ["main.lua"] = "changed\n",
      ["Data/UIManagerNodes.lua"] = "changed\n",
      ["Data/Prefab.lua"] = "changed\n",
    })
  ))
  check.equal(1, code)
  check.truthy(stdout:find("DRIFT: 3 file(s)", 1, true), stdout)
  check.truthy(stdout:find("differs: Data/UIManagerNodes.lua", 1, true), stdout)
  check.truthy(stdout:find("differs: Data/Prefab.lua", 1, true), stdout)
end)

it("a stale file left in the deploy src counts as drift", function()
  local code, stdout = _run(_merged(
    _payload(_WORK),
    _payload(_TARGET, { ["src/stale.lua"] = "return 'old'\n" })
  ))
  check.equal(1, code)
  check.truthy(stdout:find("deploy-only: src/stale.lua", 1, true), stdout)
end)

it("a file not deployed yet counts as drift", function()
  local code, stdout = _run(_merged(
    _payload(_WORK, { ["src/new.lua"] = "return 'new'\n" }),
    _payload(_TARGET)
  ))
  check.equal(1, code)
  check.truthy(stdout:find("workspace-only: src/new.lua", 1, true), stdout)
end)

it("files outside the payload are ignored on both sides", function()
  local code = _run(_merged(
    _payload(_WORK, { ["tools/cli.lua"] = "workspace only\n", ["Data/Other.lua"] = "a\n" }),
    _payload(_TARGET, { ["log.txt"] = "editor log\n", ["Data/UINodes.lua"] = "export\n" })
  ))
  check.equal(0, code)
end)

it("a missing deploy target is a failure, not a clean result", function()
  local code, _, stderr = _run(_payload(_WORK))
  check.equal(1, code)
  check.truthy(stderr:find("Deploy target does not exist", 1, true), stderr)
end)

it("an unreadable file fails instead of being reported as matching", function()
  local code, _, stderr = _run(_merged(
    _payload(_WORK),
    _payload(_TARGET),
    { [_TARGET .. "/src/a.lua"] = false }
  ))
  check.equal(1, code)
  check.truthy(stderr:find("Cannot read file", 1, true), stderr)
end)

it("nothing to compare is a failure, not a clean result", function()
  local code, _, stderr = _run({ [_TARGET .. "/log.txt"] = "editor log\n" })
  check.equal(1, code)
  check.truthy(stderr:find("nothing was compared", 1, true), stderr)
end)

it("missing interop exits 3 with status=unavailable before touching the file system", function()
  local code, stdout, stderr = _run({}, {
    detect_interop = function()
      return { "cmd.exe", "wslpath" }
    end,
    resolve_home = function()
      error("must not resolve home without interop")
    end,
    fs = {},
  })
  check.equal(3, code)
  check.equal("", stdout)
  check.truthy(stderr:find("status=unavailable tool=deploy-diff step=interop", 1, true), stderr)
  check.truthy(stderr:find("cmd.exe, wslpath", 1, true), stderr)
end)

it("an unresolved home exits 3 with status=unavailable", function()
  local code, _, stderr = _run({}, {
    resolve_home = function()
      return ""
    end,
    fs = {},
  })
  check.equal(3, code)
  check.truthy(stderr:find("status=unavailable tool=deploy-diff step=home", 1, true), stderr)
end)

it("extra arguments are a usage error, distinct from drift", function()
  local stderr = _sink()
  local code = deploy_diff.main({ "src" }, {
    stderr = stderr,
    detect_interop = function()
      error("must not run the check")
    end,
  })
  check.equal(2, code)
  check.truthy(stderr.text():find("Unexpected argument: src", 1, true), stderr.text())
end)

-- 往返:真实 copy_payload 写沙箱目标,再用真实 fs 比对;钉住两边共用同一张清单,
-- 以及中文空格路径、隐藏文件。
it("a fresh copy_payload compares clean and a later edit is caught", function()
  local root = env_lib.make_temp_path("deploy_diff_中文 空格_", "")
  fs_lib.remove_path(root)
  local ok, err = xpcall(function()
    local project, target = root .. "/project", root .. "/target"
    for path, content in pairs(_payload(project, { ["src/.hidden/c.lua"] = "return 3\n" })) do
      check.is_true(fs_lib.write_file(path, content))
    end

    deploy.copy_payload(project, target)
    local clean = deploy_diff.compare(project, target)
    check.equal(6, clean.compared)
    check.same({}, clean.differs)
    check.same({}, clean.workspace_only)
    check.same({}, clean.deploy_only)

    check.is_true(fs_lib.write_file(project .. "/src/.hidden/c.lua", "return 4\n"))
    check.is_true(fs_lib.write_file(target .. "/src/stale.lua", "return 'old'\n"))
    local drifted = deploy_diff.compare(project, target)
    check.same({ "src/.hidden/c.lua" }, drifted.differs)
    check.same({ "src/stale.lua" }, drifted.deploy_only)
  end, debug.traceback)
  fs_lib.remove_path(root)
  if not ok then
    error(err)
  end
end)

local function _run_cli(extra_args)
  local args = { require("foundation.lua54").lua54_bin(), "tools/cli.lua", "deploy-diff" }
  for _, value in ipairs(extra_args) do
    args[#args + 1] = value
  end
  return proc_lib.run_command(args, { cwd = env_lib.current_dir() })
end

it("the CLI routes deploy-diff to the read-only module", function()
  local result = _run_cli({ "--help" })
  check.is_true(result.ok, result.output)
  check.truthy(result.output:find("deploy-diff", 1, true), result.output)
  check.truthy(result.output:find("只读", 1, true), result.output)
end)

it("help states the target rule", function()
  local usage = deploy_diff.usage()
  check.truthy(usage:find("Desktop/dev/eggy/LuaSource_大富翁", 1, true), usage)
  check.truthy(usage:find("%USERPROFILE%", 1, true), usage)
  check.truthy(usage:find("MONOPOLY_DEPLOY_HOME", 1, true), usage)
end)

-- 探测函数桩成抛错:help 一旦碰 cmd.exe 或 wslpath,子进程非零退出。
it("help does not probe cmd.exe or wslpath", function()
  local root = env_lib.make_temp_path("deploy_diff_help_spec", "")
  fs_lib.remove_path(root)
  check.is_true(fs_lib.ensure_dir(root))
  local repo = env_lib.current_dir()
  local driver = root .. "/driver.lua"
  check.is_true(fs_lib.write_file(driver, table.concat({
    "package.path = " .. string.format("%q", repo .. "/?.lua;" .. repo .. "/tools/?.lua;") .. " .. package.path",
    "local deploy = require('packages.ops.deploy')",
    "deploy.detect_interop = function() error('help probed interop') end",
    "deploy.resolve_home_dir = function() error('help resolved home') end",
    "os.exit(require('packages.ops.deploy_diff').main({ '--help' }))",
    "",
  }, "\n")))
  local result = proc_lib.run_command({ require("foundation.lua54").lua54_bin(), driver })
  fs_lib.remove_path(root)
  check.is_true(result.ok, result.output)
  check.truthy(result.output:find("用法", 1, true), result.output)
end)

end)
