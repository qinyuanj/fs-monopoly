local bootstrap = require("test.bootstrap")
local env_lib = require("foundation.env")
local fs_lib = require("foundation.fs")
local path_lib = require("foundation.path")
local proc_lib = require("foundation.proc")
local text_lib = require("foundation.text")

bootstrap.install_package_paths()
local check = require("luassert")

local project_root = path_lib.normalize_path(env_lib.current_dir())

local function _make_tmp_root(tag)
  return env_lib.make_temp_path("script_tools_contract_" .. tostring(tag or "tmp"), "") .. "_中文 English"
end

local function _assert_contains(text, expected, message)
  check.matches(expected, tostring(text or ""), 1, true, message)
end

local function _assert_not_contains(text, unexpected, message)
  check.is_nil(tostring(text or ""):find(unexpected, 1, true), message)
end

local function _cleanup_tmp(tmp_root)
  local ok, err = fs_lib.remove_path(tmp_root)
  if ok == nil then
    error(err)
  end
end

local function _with_clean_tmp(tag, fn)
  local tmp_root = _make_tmp_root(tag)
  _cleanup_tmp(tmp_root)
  local ok, err = xpcall(function()
    fn(tmp_root)
  end, debug.traceback)
  _cleanup_tmp(tmp_root)
  if not ok then
    error(err)
  end
end

local function _with_ascii_tmp(tag, fn)
  local tmp_root = env_lib.make_temp_path("script_tools_contract_" .. tostring(tag or "tmp"), "")
  _cleanup_tmp(tmp_root)
  local ok, err = xpcall(function()
    fn(tmp_root)
  end, debug.traceback)
  _cleanup_tmp(tmp_root)
  if not ok then
    error(err)
  end
end

local function _run_lua(args)
  -- 工具入口统一 lua5.4(ADR 0073);本机 PATH 上的 `lua` 是 5.1。
  local command = { require("foundation.lua54").lua54_bin() }
  for _, value in ipairs(args or {}) do
    command[#command + 1] = value
  end
  return proc_lib.run_command(command, {
    cwd = project_root,
  })
end


local function _write_fixture_file(path, content)
  local ok, err = fs_lib.write_file(path, content)
  if not ok then
    error(err)
  end
end

local function _test_encoding_check_accepts_utf8_chinese_strings()
  _with_ascii_tmp("encoding_chinese_strings", function(tmp_root)
    local src_dir = path_lib.join_path(tmp_root, "src")
    local fixture_path = path_lib.join_path(src_dir, "ui/prompt.lua")
    _write_fixture_file(fixture_path, table.concat({
      'local prompt = "中文提示…继续"',
      "return prompt",
      "",
    }, "\n"))

    local result = _run_lua({
      "tools/packages/encoding/encoding.lua",
      "check",
      "--root",
      src_dir,
    })

    check.is_true(result.ok == true, "encoding check should allow utf-8 Chinese business strings")
    _assert_contains(result.output, "encoding check ok",
      "encoding check should report success for Chinese business strings")
  end)
end

local function _test_encoding_check_reports_suspicious_english_comment()
  _with_ascii_tmp("encoding_english_comment", function(tmp_root)
    local src_dir = path_lib.join_path(tmp_root, "src")
    local fixture_path = path_lib.join_path(src_dir, "ui/anim.lua")
    _write_fixture_file(fixture_path, table.concat({
      "-- Fallback: no scheduler — preserve original call order",
      "return true",
      "",
    }, "\n"))

    local result = _run_lua({
      "tools/packages/encoding/encoding.lua",
      "check",
      "--root",
      src_dir,
    })

    check.is_true(result.ok == false, "encoding check should fail on suspicious punctuation in English comments")
    _assert_contains(result.output, "U+2014",
      "encoding check should report the em dash codepoint")
    _assert_contains(result.output, 'replace with "-"',
      "encoding check should suggest the ASCII replacement")
    _assert_contains(result.output, "comment",
      "encoding check should classify the violation as a comment issue")
  end)
end

local function _test_encoding_check_reports_invalid_utf8_bytes()
  _with_ascii_tmp("encoding_invalid_utf8", function(tmp_root)
    local src_dir = path_lib.join_path(tmp_root, "src")
    local fixture_path = path_lib.join_path(src_dir, "broken.lua")
    _write_fixture_file(fixture_path, "local broken = '" .. string.char(0xFF) .. "'\n")

    local result = _run_lua({
      "tools/packages/encoding/encoding.lua",
      "check",
      "--root",
      src_dir,
    })

    check.is_true(result.ok == false, "encoding check should fail on invalid utf-8 bytes")
    _assert_contains(result.output, "invalid UTF-8 byte sequence",
      "encoding check should report invalid utf-8 bytes")
    _assert_contains(result.output, "broken.lua:1:",
      "encoding check should include the file and line location")
  end)
end

local function _test_foundation_handles_unicode_paths_for_file_ops()
  _with_clean_tmp("common_file_ops", function(tmp_root)
    local base = path_lib.join_path(tmp_root, "common_子目录/更多目录")
    local file_path = path_lib.join_path(base, "测试_文件.lua")
    local copy_source = path_lib.join_path(tmp_root, "copy_source")
    local copy_target = path_lib.join_path(tmp_root, "copy_target_中文/复制目录")

    local ok, err = fs_lib.ensure_dir(base)
    if not ok then
      error(err)
    end

    ok, err = fs_lib.write_file(file_path, 'return { value = "中文 English" }\n')
    if not ok then
      error(err)
    end

    ok, err = fs_lib.append_file(file_path, "-- appended\n")
    if not ok then
      error(err)
    end

    check.is_true(fs_lib.path_exists(file_path) == true, "unicode file path should exist after write")

    local content, read_err = fs_lib.read_file(file_path)
    if content == nil then
      error(read_err)
    end
    _assert_contains(content, "中文 English", "unicode file content should round-trip through file io")
    _assert_contains(content, "-- appended", "append_file should preserve appended content")

    local files, list_err = proc_lib.collect_lua_files(tmp_root)
    if files == nil then
      error(list_err)
    end
    check.equal(1, #files, "collect_lua_files should find the unicode fixture file")
    _assert_contains(files[1], "测试_文件.lua", "collect_lua_files should preserve unicode file names")

    ok, err = fs_lib.ensure_dir(path_lib.join_path(copy_source, "nested"))
    if not ok then
      error(err)
    end
    ok, err = fs_lib.write_file(path_lib.join_path(copy_source, "nested/sample.lua"), "return 1\n")
    if not ok then
      error(err)
    end

    ok, err = fs_lib.copy_tree(copy_source, copy_target)
    if not ok then
      error(err)
    end
    check.is_true(fs_lib.path_exists(path_lib.join_path(copy_target, "nested/sample.lua")) == true,
      "copy_tree should support unicode target directories")
  end)
end

local function _test_command_exists_reports_present_and_missing_commands()
  check.is_true(proc_lib.command_exists(require("foundation.lua54").lua54_bin()) == true,
    "the Lua 5.4 interpreter should exist in the test environment")
  check.is_true(proc_lib.command_exists("monopoly_command_that_should_not_exist_12345") == false,
    "command_exists should return false for missing commands")
end

-- arity 是这条契约的重点,不是顺手加的。tools/ 下先前有三处 _trim 写成
--   return tostring(v):gsub("^%s+",""):gsub("%s+$","")
-- gsub 返回 (结果, 替换次数),于是 `return _trim(x)` 的函数悄悄多吐一个数字:
-- 某返回 repo_root 的契约本是 (path) / (nil, err),成功时实际返回 (path, 1)。
-- 调用方恰好按 `if root == nil` 判断才没炸——改成 `if root_err` 就炸。
-- 所以这里钉死:trim 只返回一个值。
local function _test_trim_strips_whitespace_and_returns_one_value()
  check.equal("padded", text_lib.trim("  padded  "), "trim should strip leading and trailing whitespace")
  check.equal("", text_lib.trim(""), "trim should map empty string to empty string")
  check.equal("", text_lib.trim(nil), "trim should map nil to empty string")
  check.equal("mixed", text_lib.trim("\n\tmixed \r\n"), "trim should strip mixed whitespace")
  check.equal("in  ner", text_lib.trim("in  ner"), "trim should not touch interior whitespace")

  check.equal(1, select("#", text_lib.trim("  x  ")),
    "trim must return exactly one value; returning gsub's replacement count corrupts (value)/(nil, err) contracts")
end

-- 同一缺陷类的第三、四例(前两例见 trim 那条契约)。path_exists / is_dir 先前直接
-- `return _os_execute_success(...)`,而它返回 (成功, 退出码),于是这两个谓词实际返回
-- (true, 0)。verify_full 与 packages/test_runner/lua54.lua 的
-- _path_or_command_available 又原样 `return fs_lib.path_exists(text)` 把这对值
-- 继续上传。谓词只该答"是/否"。
local function _test_path_predicates_return_one_boolean()
  check.is_true(fs_lib.path_exists("tools") == true, "path_exists should find an existing directory")
  check.is_true(fs_lib.path_exists("tools/foundation/fs.lua") == true, "path_exists should find an existing file")
  check.is_true(fs_lib.path_exists("monopoly_missing_path_12345") == false, "path_exists should reject a missing path")

  check.is_true(fs_lib.is_dir("tools") == true, "is_dir should accept a directory")
  check.is_true(fs_lib.is_dir("tools/foundation/fs.lua") == false, "is_dir should reject a regular file")
  check.is_true(fs_lib.is_dir("monopoly_missing_path_12345") == false, "is_dir should reject a missing path")

  check.equal(1, select("#", fs_lib.path_exists("tools")),
    "path_exists must return exactly one value; leaking os.execute's exit code corrupts predicate contracts")
  check.equal(1, select("#", fs_lib.is_dir("tools")),
    "is_dir must return exactly one value; leaking os.execute's exit code corrupts predicate contracts")
end


local function _test_cli_help_text_is_bilingual()
  local help_commands = {
    { "tools/packages/encoding/encoding.lua", "--help" },
  }

  -- 并行执行所有 help 命令以减少总耗时
  local results = {}
  local threads = {}

  for i, args in ipairs(help_commands) do
    threads[i] = coroutine.create(function()
      results[i] = {
        args = args,
        result = _run_lua(args),
      }
    end)
  end

  -- 轮询执行所有协程直到完成
  local running = #threads
  while running > 0 do
    running = 0
    for _, thread in ipairs(threads) do
      if coroutine.status(thread) ~= "dead" then
        coroutine.resume(thread)
        if coroutine.status(thread) ~= "dead" then
          running = running + 1
        end
      end
    end
  end

  -- 验证所有结果
  for _, item in ipairs(results) do
    check.is_true(item.result.ok, "help command should exit successfully for " .. table.concat(item.args, " "))
    _assert_contains(item.result.output, "用法", "help output should include Chinese usage text")
    _assert_contains(item.result.output, "Usage", "help output should include English usage text")
  end
end

-- 入口解释器预检(#191 用户故事 3):本机 PATH 上的 `lua` 是 5.1,入口必须拦下。
local function _test_cli_entry_rejects_non_lua54_interpreter()
  -- 静态契约:版本闸必须在装载子命令之前,且提示指向受支持入口。
  local cli_source = assert(fs_lib.read_file(path_lib.join_path(project_root, "tools/cli.lua")))
  local guard_at = cli_source:find('_VERSION ~= "Lua 5.4"', 1, true)
  local dispatch_at = cli_source:find("pcall(require", 1, true)
  check.truthy(guard_at ~= nil, "tools/cli.lua must gate on the interpreter version")
  check.truthy(guard_at < dispatch_at, "version gate must run before subcommand dispatch")
  _assert_contains(cli_source, "lua5.4 tools/cli.lua", "gate must print the supported entry")

  -- 动态契约:机器上有非 5.4 解释器时真跑一次,确认真被拦下且不退 0。
  for _, candidate in ipairs({ "lua5.1", "lua5.3", "lua5.2" }) do
    if proc_lib.command_exists(candidate) then
      local result = proc_lib.run_command({ candidate, "tools/cli.lua", "verify" }, { cwd = project_root })
      check.truthy(not result.ok, "entry must reject " .. candidate)
      check.equal(1, result.code, result.output)
      _assert_contains(result.output, "Lua 5.4 interpreter required", "rejection must name the requirement")
      _assert_not_contains(result.output, "[verify]", "preflight must run before lane dispatch")
      return
    end
  end
end

-- WSL 部署契约:文本检查与安全帮助入口;复制由 ops 隔离目录测试覆盖。
local function _test_deploy_lua_matches_simplified_cli()
  local script_text = assert(fs_lib.read_file(path_lib.join_path(project_root, "tools/packages/ops/deploy.lua")))

  -- 零参数 CLI:任何参数都 ERROR + exit 1。
  _assert_contains(
    script_text,
    "Unexpected argument",
    "deploy.lua should reject any CLI argument (zero-parameter interface)"
  )

  -- cli.lua 顶层路由:deploy 子命令挂载到 ops 包(命令集 ↔ packages/ 一致性由
  -- cli_command_table_guard 结构保证,这里钉行为面:入口必须经 cli.lua 可达)。
  local cli_source = assert(fs_lib.read_file(path_lib.join_path(project_root, "tools/cli.lua")))
  _assert_contains(cli_source, 'name = "deploy"', "cli.lua should route the deploy subcommand")
  _assert_contains(cli_source, 'pkg = "ops"', "cli.lua deploy should route to packages.ops")

  -- 退役全局/参数:不再注入 build-mode / deploy-target / startup-test-profile。
  _assert_not_contains(
    script_text,
    "MONOPOLY_BUILD_MODE",
    "deploy.lua should no longer inject any build-mode global"
  )
  _assert_not_contains(
    script_text,
    "MONOPOLY_DEPLOY_TARGET",
    "deploy.lua should no longer read MONOPOLY_DEPLOY_TARGET fallback"
  )
  _assert_not_contains(
    script_text,
    "STARTUP_TEST_PROFILE",
    "deploy.lua should no longer inject the retired STARTUP_TEST_PROFILE global"
  )

  -- LuaSource 目录名集中构造。
  _assert_contains(
    script_text,
    "function M.join_lua_source_dir_name",
    "deploy.lua should centralize the LuaSource directory name construction"
  )

  -- Windows 侧落点:~/Desktop/dev/eggy/LuaSource_大富翁(经 %USERPROFILE% + wslpath 换算)。
  _assert_contains(
    script_text,
    '_join_path(_join_path(_join_path(_join_path(home_dir, "Desktop"), "dev"), "eggy"), M.join_lua_source_dir_name())',
    "deploy.lua should keep the Windows default deploy path semantics"
  )
  _assert_contains(script_text, "wslpath", "deploy.lua should convert the Windows profile through wslpath")
  _assert_contains(script_text, "%USERPROFILE%", "deploy.lua should resolve the Windows profile dynamically")
  _assert_not_contains(script_text, "C:/Users/", "deploy.lua must not hardcode a Windows user name")

  -- ADR 0073:原生 Windows 原语退场。
  for _, retired in ipairs({ "cmd.exe /d /v:off /c", "chcp", "robocopy", "if exist", "if not exist", "rmdir", "del /f" }) do
    _assert_not_contains(script_text, retired, "deploy should retire " .. retired)
  end

  -- 非目标平台落点与检测已删除。
  _assert_not_contains(
    script_text,
    "function M.test_is_macos_host",
    "deploy.lua should no longer detect macOS (Windows-only deploy target)"
  )
  _assert_not_contains(
    script_text,
    "function M.test_is_linux_host",
    "deploy.lua should no longer detect native Linux (Windows-only deploy target)"
  )
  _assert_not_contains(
    script_text,
    '"Documents"',
    "deploy.lua should no longer keep mac/native-linux deploy targets (Windows-only)"
  )

  -- 不再使用发布/备份后缀路径。
  _assert_not_contains(
    script_text,
    "LuaSource_大富翁-发布",
    "deploy.lua should no longer keep suffix-based default deploy paths"
  )
  _assert_not_contains(
    script_text,
    "LuaSource_大富翁-备份",
    "deploy.lua should no longer keep suffix-based backup deploy paths"
  )
end

local function _test_deploy_comprehensive()
  _test_deploy_lua_matches_simplified_cli()
  -- 帮助在壳内结束,不会进入部署主流程或写入实际目标。
  local result = _run_lua({ "tools/cli.lua", "deploy", "--help" })
  check.is_true(result.ok == true, "deploy help should succeed")
  _assert_contains(result.output, "WSL", "help should declare the WSL platform")
  _assert_contains(result.output, "退 3", "help should explain the unavailable exit code")
end

local function _test_run_command_preserves_bilingual_stderr_and_utf8_stdin()
  _with_clean_tmp("run_command_stderr_capture", function(tmp_root)
    local script_path = path_lib.join_path(tmp_root, "capture_output.lua")
    local stdin_path = path_lib.join_path(tmp_root, "stdin.txt")
    local ok, err = fs_lib.write_file(script_path, table.concat({
      "local input = io.read('*a') or ''",
      "if input ~= '' then",
      "  io.write(input)",
      "  if input:sub(-1) ~= '\\n' then",
      "    io.write('\\n')",
      "  end",
      "end",
      "io.stderr:write('未知参数 / Unknown flag: --bad-flag\\n')",
      "os.exit(7)",
      "",
    }, "\n"))
    if not ok then
      error(err)
    end

    ok, err = fs_lib.write_file(stdin_path, "stdin 中文 / utf8 stdin")
    if not ok then
      error(err)
    end

    local result = proc_lib.run_command({ require("foundation.lua54").lua54_bin(), script_path }, {
      cwd = project_root,
      stdin_path = stdin_path,
    })

    check.is_true(result.ok == false, "run_command should surface non-zero exit codes")
    check.is_true(result.code ~= 0, "run_command should preserve the child exit code")
    _assert_contains(result.output, "stdin 中文 / utf8 stdin", "run_command should preserve utf8 stdin content")
    _assert_contains(result.output, "未知参数", "run_command should preserve Chinese stderr text")
    _assert_contains(result.output, "Unknown flag", "run_command should preserve English stderr text")
    _assert_not_contains(result.output, "System.Management.Automation.RemoteException",
      "run_command should not wrap native stderr as a PowerShell exception")
  end)
end

local function _test_bootstrap_resolves_repo_root_from_non_repo_cwd()
  _with_ascii_tmp("bootstrap_non_repo_cwd", function(tmp_root)
    local outside_dir = path_lib.join_path(tmp_root, "outside")
    local ok, err = fs_lib.ensure_dir(outside_dir)
    if not ok then
      error(err)
    end

    local bootstrap_path = path_lib.join_path(project_root, "tools/foundation/bootstrap.lua")
    local script_path = path_lib.join_path(project_root, "tools/packages/encoding/encoding.lua")
    local expected_root = path_lib.normalize_path(project_root)
    local lua_snippet = table.concat({
      "local bootstrap = dofile(" .. string.format("%q", bootstrap_path) .. ")",
      "local env = bootstrap.install(" .. string.format("%q", script_path) .. ")",
      "assert(env.repo_root == " .. string.format("%q", expected_root) .. ", 'repo root mismatch')",
      "io.write(env.repo_root)",
    }, "; ")

    local bootstrap_result = proc_lib.run_command({ require("foundation.lua54").lua54_bin(), "-e", lua_snippet }, {
      cwd = outside_dir,
    })
    check.is_true(bootstrap_result.ok, "bootstrap helper should resolve repo_root outside the repo cwd")
    _assert_contains(bootstrap_result.output, expected_root,
      "bootstrap helper should report the normalized repo root")

    local help_result = proc_lib.run_command({ require("foundation.lua54").lua54_bin(), script_path, "--help" }, {
      cwd = outside_dir,
    })
    check.is_true(help_result.ok, "tool entrypoint should resolve bootstrap dependencies outside the repo cwd")
    _assert_contains(help_result.output, "Usage",
      "tool help should still render when launched outside the repo cwd")
  end)
end

local contract_tests = {
  { group = "shared", owner = "foundation", name = "command_exists_reports_present_and_missing_commands", run = _test_command_exists_reports_present_and_missing_commands },
  { group = "shared", owner = "foundation", name = "trim_strips_whitespace_and_returns_one_value", run = _test_trim_strips_whitespace_and_returns_one_value },
  { group = "shared", owner = "foundation", name = "path_predicates_return_one_boolean", run = _test_path_predicates_return_one_boolean },
  { group = "shared", owner = "foundation", name = "foundation_handles_unicode_paths_for_file_ops", run = _test_foundation_handles_unicode_paths_for_file_ops },
  { group = "shared", owner = "tooling_policy", name = "cli_help_text_is_bilingual", run = _test_cli_help_text_is_bilingual },
  { group = "shared", owner = "tooling_policy", name = "cli_entry_rejects_non_lua54_interpreter", run = _test_cli_entry_rejects_non_lua54_interpreter },
  { group = "shared", owner = "bootstrap", name = "bootstrap_resolves_repo_root_from_non_repo_cwd", run = _test_bootstrap_resolves_repo_root_from_non_repo_cwd },
  { group = "ops", owner = "deploy", name = "deploy_lua_matches_simplified_cli", run = _test_deploy_lua_matches_simplified_cli },
}

local tooling_tests = {
  { group = "quality", owner = "encoding", name = "encoding_check_accepts_utf8_chinese_strings", run = _test_encoding_check_accepts_utf8_chinese_strings },
  { group = "quality", owner = "encoding", name = "encoding_check_reports_suspicious_english_comment", run = _test_encoding_check_reports_suspicious_english_comment },
  { group = "quality", owner = "encoding", name = "encoding_check_reports_invalid_utf8_bytes", run = _test_encoding_check_reports_invalid_utf8_bytes },
  { group = "ops", owner = "deploy", name = "deploy_comprehensive", run = _test_deploy_comprehensive },
  { group = "shared", owner = "foundation", name = "run_command_preserves_bilingual_stderr_and_utf8_stdin", run = _test_run_command_preserves_bilingual_stderr_and_utf8_stdin },
}

local valid_groups = {
  ops = true,
  quality = true,
  shared = true,
}

local valid_owners = {
  bootstrap = true,
  foundation = true,
  deploy = true,
  encoding = true,
  tooling_policy = true,
}

local function _validate_cases(cases, label)
  for _, case in ipairs(cases or {}) do
    if valid_groups[case.group] ~= true then
      error(string.format(
        "%s case %s has invalid tooling group: %s",
        label,
        tostring(case.name),
        tostring(case.group)
      ))
    end
    if valid_owners[case.owner] ~= true then
      error(string.format(
        "%s case %s has invalid tooling owner: %s",
        label,
        tostring(case.name),
        tostring(case.owner)
      ))
    end
  end
end

local function _cases_for_group(cases, group)
  local selected = {}
  for _, case in ipairs(cases or {}) do
    if case.group == group then
      selected[#selected + 1] = case
    end
  end
  return selected
end

local function _cases_for_owner(cases, owner)
  local selected = {}
  for _, case in ipairs(cases or {}) do
    if case.owner == owner then
      selected[#selected + 1] = case
    end
  end
  return selected
end

_validate_cases(contract_tests, "contract")
_validate_cases(tooling_tests, "tooling")

return {
  name = "script_tools_contract",
  tests = contract_tests,
  tooling_tests = tooling_tests,
  cases_for_group = _cases_for_group,
  cases_for_owner = _cases_for_owner,
}
