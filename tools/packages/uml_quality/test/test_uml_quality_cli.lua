---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/packages/uml_quality/test/test_uml_quality_cli.lua") end
require("test.bootstrap").install_package_paths()

-- uml 子命令(#93)的退出码契约。真跑 crapper/mutator 不在本套件内;
-- 预检失败面用一个不含 .uml-viewer 检出、受控 Lua 环境不可用的临时仓根驱动。
local check = require("luassert")
local cli = require("packages.uml_quality.cli")
local lua_env = require("foundation.lua_env")
local env_lib = require("foundation.env")
local fs = require("foundation.fs")

local function _quiet(fn)
  local captured = {}
  local sink = { write = function(_, ...) for _, part in ipairs({ ... }) do captured[#captured + 1] = tostring(part) end end }
  local original_write, original_stderr = io.write, io.stderr
  rawset(io, "write", function(...) return sink:write(...) end)
  rawset(io, "stderr", sink)
  local ok, result = pcall(fn)
  rawset(io, "write", original_write)
  rawset(io, "stderr", original_stderr)
  if not ok then error(result, 0) end
  return result, table.concat(captured)
end

local function _with_unavailable_lua_env(fn)
  local saved = lua_env.preflight
  lua_env.preflight = function() return nil, "controlled Lua environment unavailable" end
  local ok, err = pcall(fn)
  lua_env.preflight = saved
  if not ok then error(err, 0) end
end

describe("uml quality cli", function()

it("prints usage on --help", function()
  local code, output = _quiet(function() return cli.main({ "--help" }, {}) end)
  check.equal(0, code)
  check.truthy(output:find("check|crap|mutate|ir|view", 1, true))
end)

it("rejects a missing or unknown operation as usage error", function()
  check.equal(2, (_quiet(function() return cli.main({}, {}) end)))
  check.equal(2, (_quiet(function() return cli.main({ "graph" }, {}) end)))
  check.equal(2, (_quiet(function() return cli.main({ "check", "--extra" }, {}) end)))
  check.equal(2, (_quiet(function() return cli.main({ "ir", "out.edn" }, {}) end)))
end)

-- 反例:依赖缺失必须大声失败(非零,不是 3——3 是 mutate 的有效结果),
-- 且不能留下上一轮的 quality-result.json 让消费方读成本轮结果。
it("fails preflight loudly and clears a stale quality result", function()
  local root = env_lib.make_temp_path("uml_quality_cli", "")
  local stale = root .. "/.uml-viewer/quality-result.json"
  fs.ensure_parent_dir(stale)
  fs.write_file(stale, '{"version":1,"exitCode":0,"validResult":true}')
  local code, output
  _with_unavailable_lua_env(function()
    code, output = _quiet(function() return cli.main({ "crap" }, { repo_root = root }) end)
  end)
  local stale_left = fs.path_exists(stale)
  fs.remove_path(root)
  check.equal(1, code)
  check.is_false(stale_left)
  check.truthy(output:find("FAIL controlled Lua environment: controlled Lua environment unavailable", 1, true))
  check.truthy(output:find("uml_posix.py missing", 1, true))
  check.truthy(output:find("crapper: ", 1, true))
  check.truthy(output:find("crap was not started", 1, true))
end)

it("rejects missing mutation evidence even when upstream reports success", function()
  local root = env_lib.make_temp_path("uml_mutation_missing", "")
  fs.ensure_dir(root)
  local code, output = _quiet(function()
    return cli.main({ "mutate", "src/demo.lua" }, {
      repo_root = root,
      preflight = function() return { ok = true, scripts = root, env_list = {} } end,
      launch = function() return 0 end,
    })
  end)
  fs.remove_path(root)
  check.equal(1, code)
  check.truthy(output:find("mutation", 1, true))
end)

-- ir / view(#99 / ADR 0070):上游启动器用替身 launch 记录 argv 与子进程环境;
-- ir 的生成面从临时仓根读 policy.json 与覆盖文件,写出 policy.edn。
local POLICY_JSON = "tools/packages/arch_policy/policy.json"
local OVERRIDE = "docs/architecture.proposals.edn"

local function _temp_root(override)
  local root = env_lib.make_temp_path("uml_quality_ir", "")
  fs.ensure_parent_dir(root .. "/" .. POLICY_JSON)
  fs.write_file(root .. "/" .. POLICY_JSON, assert(fs.read_raw(POLICY_JSON)))
  if override ~= nil then
    fs.ensure_parent_dir(root .. "/" .. OVERRIDE)
    fs.write_file(root .. "/" .. OVERRIDE, override)
  end
  return root
end

local function _stubs(state, code)
  local calls = { preflight = 0, launch = {} }
  return calls, {
    preflight = function(_, op)
      calls.preflight = calls.preflight + 1
      calls.op = op
      return state
    end,
    launch = function(root, env_list, argv)
      calls.launch[#calls.launch + 1] = { root = root, env_list = env_list, argv = argv }
      return code or 0
    end,
  }
end

local function _run_ir(root, calls_state, code)
  local calls, hooks = _stubs(calls_state or { ok = true, scripts = "/up/scripts", env_list = {} }, code)
  hooks.repo_root = root
  local exit_code, output = _quiet(function() return cli.main({ "ir" }, hooks) end)
  local policy = fs.read_raw(root .. "/policy.edn")
  local out_dir = fs.is_dir(root .. "/tmp/uml")
  fs.remove_path(root)
  return exit_code, policy, calls, output, out_dir
end

it("ir writes policy.edn from the projection and passes the upstream exit code through", function()
  local root = _temp_root(nil)
  local code, policy, calls, _, out_dir = _run_ir(root, nil, 7)
  check.equal(7, code)
  check.truthy(policy:find(":levels [[:foundation]", 1, true))
  check.truthy(policy:find(':out "tmp/uml/fs-monopoly.edn"', 1, true))
  check.truthy(policy:find(":proposals []", 1, true))
  check.truthy(policy:find(":omit []", 1, true))
  check.is_true(out_dir)
  check.equal("ir", calls.op)
  check.equal(1, #calls.launch)
  check.same({ "python3", "-I", "-B", calls.launch[1].root .. "/.uml-viewer/uml-viewer/scripts/uml_posix.py",
    "command", calls.launch[1].root, "ir", "policy.edn", "tmp/uml/fs-monopoly.edn" }, calls.launch[1].argv)
end)

-- 推演只写覆盖文件;每次重生都必须把它带回 policy.edn,不被投影冲掉。
it("ir keeps a proposal from the override file across regeneration", function()
  local proposal = '{:id :split :name "rules split" :layers [:rules :turn]}'
  local root = _temp_root("{:proposals [" .. proposal .. "]\n :omit []}\n")
  local code, policy = _run_ir(root)
  check.equal(0, code)
  check.truthy(policy:find(":proposals [" .. proposal .. "]", 1, true))
end)

it("ir treats an empty override file as no proposals", function()
  local code, policy = _run_ir(_temp_root(""))
  check.equal(0, code)
  check.truthy(policy:find(":proposals []", 1, true))
end)

-- 反例:非法或含多余键的覆盖文件退 1、可读报错、不写半成品 policy.edn、不起上游。
it("ir rejects an invalid or over-wide override file without writing policy.edn", function()
  for _, override in ipairs({ "{:proposals [", "{:proposals [] :levels []}" }) do
    local code, policy, calls, output = _run_ir(_temp_root(override))
    check.equal(1, code, override)
    check.is_nil(policy, override)
    check.equal(0, calls.preflight, override)
    check.equal(0, #calls.launch, override)
    check.truthy(output:find(OVERRIDE, 1, true), override)
    check.truthy(output:find("policy.edn was not written", 1, true), override)
  end
end)

it("ir writes nothing and starts nothing when the preflight fails", function()
  local code, policy, calls = _run_ir(_temp_root(nil), { ok = false })
  check.equal(1, code)
  check.is_nil(policy)
  check.equal(0, #calls.launch)
end)

-- view 用预检钉死的 LUA_PATH/LUA_CPATH(受控 Lua 环境)启动上游;PATH 原序下传,
-- herdr 由上游从中选(不钉版本、不置前)。钉环境只发生在子进程里,父进程环境不变。
it("view launches with the preflight's pinned environment and leaves the parent environment unchanged", function()
  local before = { os.getenv("PATH"), os.getenv("LUA_PATH"), os.getenv("LUA_CPATH") }
  local pinned = require("packages.uml_quality.runtime").pinned_env("/repo", { "/rocks/tree" },
    "/lua/bin", "/sys:/herdr/0.9.4")
  local calls, hooks = _stubs({ ok = true, scripts = "/up/scripts", env_list = pinned }, 0)
  hooks.repo_root = "."
  local code = _quiet(function() return cli.main({ "view", "--restart" }, hooks) end)
  check.equal(0, code)
  check.equal("view", calls.op)
  check.equal(1, #calls.launch)
  local launched = calls.launch[1]
  check.equal(pinned, launched.env_list)
  local env = {}
  for _, entry in ipairs(launched.env_list) do env[entry[1]] = entry[2] end
  check.equal("/lua/bin:/sys:/herdr/0.9.4", env.PATH)
  check.same({ "python3", "-I", "-B", launched.root .. "/.uml-viewer/uml-viewer/scripts/uml_posix.py",
    "command", launched.root, "--restart" }, launched.argv)
  check.same(before, { os.getenv("PATH"), os.getenv("LUA_PATH"), os.getenv("LUA_CPATH") })
end)

it("view fails before launching when no herdr >= 0.9.3 is on PATH or the upstream checkout is missing", function()
  local root = env_lib.make_temp_path("uml_quality_view", "")
  fs.ensure_dir(root)
  local launched = 0
  local code, output
  _with_unavailable_lua_env(function()
    code, output = _quiet(function()
      return cli.main({ "view" }, { repo_root = root, path = root,
        launch = function() launched = launched + 1 return 0 end })
    end)
  end)
  fs.remove_path(root)
  check.equal(1, code)
  -- lint-allow: call-count launch 经 opts 注入,预检失败不拉起是对外契约
  check.equal(0, launched)
  check.truthy(output:find("FAIL herdr >= 0.9.3: none on PATH", 1, true))
  check.truthy(output:find("uml_posix.py missing", 1, true))
  check.truthy(output:find("view was not started", 1, true))
end)

end)
