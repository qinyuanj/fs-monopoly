---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/packages/data_sync/test/test_sync_data.lua") end
require("test.bootstrap").install_package_paths()

-- sync_data.lua 的聚焦单测:UINodes → UIManagerNodes 转换(parse/render,移植自
-- UIManager_web script.js,无 length 行)+ sync_from_deploy 沙箱文件系统行为。
local check = require("luassert")
local env_lib = require("foundation.env")
local fs_lib = require("foundation.fs")
local sync_data = require("packages.data_sync.sync_data")

local SAMPLE_UINODES = table.concat({
  "---AUTTO EXPORT BY EGGITOR PLUGIN, PLEASE DO NOT EDIT",
  "",
  "return {",
  '\t["位置-槽位1投影"] = "1519736575|1821865760" --[[@as EImage]],',
  '\t基础屏 = "1519736575|2147314485" --[[@as ECanvas]],',
  '\t--["旧节点"] = "1519736575|2147314485" --[[@as EImage]],',
  '\t["日志"] = "1519736575|1002562102" --[[@as ELabel]],',
  "}",
  "",
}, "\n")

local EXPECTED_RENDER = table.concat({
  "---AUTTO EXPORT BY EGGITOR PLUGIN, PLEASE DO NOT EDIT",
  "",
  "return {",
  '\t["1519736575|1002562102"] = {"日志", "ELabel"},',
  '\t["1519736575|1821865760"] = {"位置-槽位1投影", "EImage"},',
  '\t["1519736575|2147314485"] = {"旧节点", "EImage"},',
  "}",
  "",
}, "\n")

local function _with_sandbox(fn)
  local root = env_lib.make_temp_path("sync_data_spec_", "")
  fs_lib.remove_path(root)
  local ok, err = xpcall(function()
    fn(root)
  end, debug.traceback)
  fs_lib.remove_path(root)
  if not ok then
    error(err)
  end
end

local function _write(path, content)
  local ok, err = fs_lib.write_file(path, content)
  if not ok then
    error(err)
  end
end

local function _make_deploy_dir(root)
  local deploy_dir = root .. "/deploy"
  _write(deploy_dir .. "/Data/Prefab.lua", "---AUTTO EXPORT BY EGGITOR PLUGIN, PLEASE DO NOT EDIT\n\nreturn {\n\tunit = {\n\t\tlv1 = 1073786977,\n\t},\n}\n")
  _write(deploy_dir .. "/Data/UINodes.lua", SAMPLE_UINODES)
  _write(deploy_dir .. "/EggyAPI.lua", "-- EggyAPI: 游戏API\n-- Auto-generated, do not edit\n\n---@class Other\n\nOther = {}\n")
  _write(deploy_dir .. "/EggyEditorAPI.lua", "-- EggyEditorAPI: 编辑器编辑时API\n-- Auto-generated, do not edit\n\n---@class Other\n\nOther = {}\n")
  return deploy_dir
end

describe("parse UI nodes", function()

it("parses bracket bare and commented forms", function()
  local data = sync_data.parse_uinodes(SAMPLE_UINODES)
  check.same({ name = "位置-槽位1投影", node_type = "EImage" }, data["1519736575|1821865760"])
  check.same({ name = "日志", node_type = "ELabel" }, data["1519736575|1002562102"])
  -- 同 id 后者覆盖:注释行里的"旧节点"覆盖裸键形式的"基础屏"(与 JS 一致)。
  check.same({ name = "旧节点", node_type = "EImage" }, data["1519736575|2147314485"])
end)

it("ignores non entry lines", function()
  local data = sync_data.parse_uinodes(SAMPLE_UINODES)
  local count = 0
  for _ in pairs(data) do
    count = count + 1
  end
  check.same(3, count)
end)

it("empty input yields an empty map", function()
  check.same(nil, next(sync_data.parse_uinodes("")))
  check.same(nil, next(sync_data.parse_uinodes(nil)))
end)
end)

describe("render UI manager nodes", function()

it("renders sorted nodes without a length line", function()
  local rendered = sync_data.render_ui_manager_nodes(sync_data.parse_uinodes(SAMPLE_UINODES))
  check.same(EXPECTED_RENDER, rendered)
  check.is_nil(rendered:find("length", 1, true))
end)
end)

describe("sync from sandbox deploy directory", function()

it("sync writes all files", function()
  _with_sandbox(function(root)
    local deploy_dir = _make_deploy_dir(root)
    local repo_root = root .. "/repo"
    fs_lib.ensure_dir(repo_root .. "/Data")

    local stats, err = sync_data.sync_from_deploy(deploy_dir, repo_root)
    check.is_not_nil(stats, tostring(err))
    check.same(3, stats.node_count)
    check.is_true(stats.prefab_changed)
    check.is_true(stats.nodes_changed)
    check.is_true(stats.prefab_bytes > 0)
    check.is_true(stats.api_changed)
    check.is_true(stats.editor_api_changed)
    check.is_true(stats.api_bytes > 0)
    check.is_true(stats.editor_api_bytes > 0)

    check.same(EXPECTED_RENDER, fs_lib.read_file(repo_root .. "/Data/UIManagerNodes.lua"))
    check.same(
      fs_lib.read_file(deploy_dir .. "/Data/Prefab.lua"),
      fs_lib.read_file(repo_root .. "/Data/Prefab.lua")
    )
    check.same(
      fs_lib.read_file(deploy_dir .. "/EggyAPI.lua"),
      fs_lib.read_file(repo_root .. "/EggyAPI.lua")
    )
    check.same(
      fs_lib.read_file(deploy_dir .. "/EggyEditorAPI.lua"),
      fs_lib.read_file(repo_root .. "/EggyEditorAPI.lua")
    )
  end)
end)

it("second run reports no change", function()
  _with_sandbox(function(root)
    local deploy_dir = _make_deploy_dir(root)
    local repo_root = root .. "/repo"
    fs_lib.ensure_dir(repo_root .. "/Data")

    sync_data.sync_from_deploy(deploy_dir, repo_root)
    local stats, err = sync_data.sync_from_deploy(deploy_dir, repo_root)
    check.is_not_nil(stats, tostring(err))
    check.is_false(stats.prefab_changed)
    check.is_false(stats.nodes_changed)
    check.is_false(stats.api_changed)
    check.is_false(stats.editor_api_changed)
  end)
end)

it("missing prefab is an error and writes nothing", function()
  _with_sandbox(function(root)
    local deploy_dir = root .. "/deploy"
    _write(deploy_dir .. "/Data/UINodes.lua", SAMPLE_UINODES)
    local repo_root = root .. "/repo"
    fs_lib.ensure_dir(repo_root .. "/Data")

    local stats, err = sync_data.sync_from_deploy(deploy_dir, repo_root)
    check.is_nil(stats)
    check.matches("Prefab.lua", tostring(err), 1, true)
    check.is_false(fs_lib.path_exists(repo_root .. "/Data/UIManagerNodes.lua"))
  end)
end)

it("missing UI nodes is an error", function()
  _with_sandbox(function(root)
    local deploy_dir = root .. "/deploy"
    _write(deploy_dir .. "/Data/Prefab.lua", "return {}\n")
    local repo_root = root .. "/repo"
    fs_lib.ensure_dir(repo_root .. "/Data")

    local stats, err = sync_data.sync_from_deploy(deploy_dir, repo_root)
    check.is_nil(stats)
    check.matches("UINodes.lua", tostring(err), 1, true)
  end)
end)

it("unparseable UI nodes is an error and writes nothing", function()
  _with_sandbox(function(root)
    local deploy_dir = root .. "/deploy"
    _write(deploy_dir .. "/Data/Prefab.lua", "return {}\n")
    _write(deploy_dir .. "/Data/UINodes.lua", "return {}\n")
    _write(deploy_dir .. "/EggyAPI.lua", "Other = {}\n")
    _write(deploy_dir .. "/EggyEditorAPI.lua", "Other = {}\n")
    local repo_root = root .. "/repo"
    fs_lib.ensure_dir(repo_root .. "/Data")

    local stats, err = sync_data.sync_from_deploy(deploy_dir, repo_root)
    check.is_nil(stats)
    check.matches("未解析出任何节点", tostring(err), 1, true)
    check.is_false(fs_lib.path_exists(repo_root .. "/Data/Prefab.lua"))
  end)
end)

it("missing Eggy API is an error and writes nothing", function()
  _with_sandbox(function(root)
    local deploy_dir = root .. "/deploy"
    _write(deploy_dir .. "/Data/Prefab.lua", "return {}\n")
    _write(deploy_dir .. "/Data/UINodes.lua", SAMPLE_UINODES)
    _write(deploy_dir .. "/EggyEditorAPI.lua", "Other = {}\n")
    local repo_root = root .. "/repo"
    fs_lib.ensure_dir(repo_root .. "/Data")

    local stats, err = sync_data.sync_from_deploy(deploy_dir, repo_root)
    check.is_nil(stats)
    check.matches("EggyAPI.lua", tostring(err), 1, true)
    check.is_false(fs_lib.path_exists(repo_root .. "/Data/Prefab.lua"))
    check.is_false(fs_lib.path_exists(repo_root .. "/EggyEditorAPI.lua"))
  end)
end)

it("missing Eggy editor API is an error and writes nothing", function()
  _with_sandbox(function(root)
    local deploy_dir = root .. "/deploy"
    _write(deploy_dir .. "/Data/Prefab.lua", "return {}\n")
    _write(deploy_dir .. "/Data/UINodes.lua", SAMPLE_UINODES)
    _write(deploy_dir .. "/EggyAPI.lua", "Other = {}\n")
    local repo_root = root .. "/repo"
    fs_lib.ensure_dir(repo_root .. "/Data")

    local stats, err = sync_data.sync_from_deploy(deploy_dir, repo_root)
    check.is_nil(stats)
    check.matches("EggyEditorAPI.lua", tostring(err), 1, true)
    check.is_false(fs_lib.path_exists(repo_root .. "/Data/Prefab.lua"))
    check.is_false(fs_lib.path_exists(repo_root .. "/EggyAPI.lua"))
  end)
end)
end)

describe("sync data CLI arguments", function()

it("unexpected argument is a usage error", function()
  check.equal(2, sync_data.main({ "extra" }))
end)

-- 家目录与部署目录解析只有 deploy 一份实现:取不到 %USERPROFILE% 就是不可用(退 3),
-- 与 deploy 的退码口径一致,不是业务失败(退 1)。
it("an unresolvable home directory is unavailable, not a business failure", function()
  local deploy = require("packages.ops.deploy")
  local original = deploy.resolve_default_target_path
  deploy.resolve_default_target_path = function()
    return nil, "无法解析原生 Windows 家目录(%USERPROFILE%)。"
  end
  local ok, code = pcall(sync_data.main, {})
  deploy.resolve_default_target_path = original
  check.is_true(ok, tostring(code))
  check.equal(3, code)
end)

-- 回同步只读部署目录,不依赖 robocopy:即使 robocopy 探测会抛错,流程也不该碰它。
it("sync-back never probes robocopy", function()
  local deploy = require("packages.ops.deploy")
  local original_target, original_tools = deploy.resolve_default_target_path, deploy.detect_native_tools
  deploy.resolve_default_target_path = function() return "C:/sandbox/no-such-deploy-dir" end
  deploy.detect_native_tools = function() error("sync-back must not probe robocopy") end
  local ok, code = pcall(sync_data.main, {})
  deploy.resolve_default_target_path, deploy.detect_native_tools = original_target, original_tools
  check.is_true(ok, tostring(code))
  -- 部署目录缺 Data/Prefab.lua:业务失败退 1,而不是不可用退 3。
  check.equal(1, code)
end)
end)
