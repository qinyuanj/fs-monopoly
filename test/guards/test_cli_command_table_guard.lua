require("test.bootstrap").install_package_paths()

local luassert = assert
local guard = require("test.guards.lib.cli_command_table_guard")

-- cli 子命令表 ↔ packages/ 一致性 guard(#316 / #300 Q4):commands 路由表与
-- tools/packages/ 目录一一对应,非路由包走白名单。下面每一条都喂合成的
-- 路由表/目录/白名单,断言它真的会红/会绿——门禁的价值全在能变红。

-- 精简的合成基线语料(5 条路由 + 1 个非路由包;真实仓库为 9 条路由 + 3 个
-- 非路由包,同构即可,判分支与数量无关)。
local _COMMANDS = {
  { name = "verify", pkg = "verify" },
  { name = "spec-lane", pkg = "spec_lane" },
  { name = "dry", pkg = "dry" },
  { name = "lint", pkg = "lint" },
  { name = "deploy", pkg = "ops" },
}
local _DIRS = { "verify", "spec_lane", "dry", "lint", "encoding", "ops" }
local _NON_ROUTED = { "encoding" }

local function _check(commands, dirs, non_routed)
  return guard.check(commands or _COMMANDS, dirs or _DIRS, non_routed or _NON_ROUTED)
end

local function _joined(violations)
  return table.concat(violations, "\n")
end

describe("TestCliCommandTableGuard", function()
  -- 从 cli.lua 源码形态解析出 name/pkg 对。
  it("test_parse_commands_extracts_entries", function()
    local source = table.concat({
      'local commands = {',
      '  { name = "verify",            pkg = "verify",             summary = "x" },',
      '  { name = "spec-lane",         pkg = "spec_lane",          summary = "y" },',
      '}',
    }, "\n")
    local commands, err = guard.parse_commands(source)
    luassert.is_not_nil(commands, tostring(err))
    luassert.is.equal(2, #commands)
    luassert.is.equal("verify", commands[1].name)
    luassert.is.equal("verify", commands[1].pkg)
    luassert.is.equal("spec-lane", commands[2].name)
    luassert.is.equal("spec_lane", commands[2].pkg)
  end)

  -- 源码里一条都解析不到(表被改名/搬走)必须失败,不能静默全绿。
  it("test_parse_commands_fails_on_unparseable_source", function()
    local commands, err = guard.parse_commands("-- 空源码,没有 commands 表")
    luassert.is_nil(commands)
    luassert.truthy(tostring(err):find("解析", 1, true) ~= nil)
  end)

  -- 现状同构语料必须全绿(路由 ⊆ 目录,目录 = 路由 ∪ 白名单)。
  it("test_current_shape_is_allowed", function()
    local violations = _check()
    luassert.is.equal(0, #violations, _joined(violations))
  end)

  -- 路由到不存在的包(错名/目录遗漏)必须被拦。
  it("test_routed_missing_pkg_is_blocked", function()
    local commands = { { name = "dry", pkg = "dryy" } }
    local violations = _check(commands, { "dry" }, {})
    luassert.is.equal(2, #violations, _joined(violations))
    luassert.truthy(_joined(violations):find("dryy", 1, true) ~= nil)
  end)

  -- 多余包(未路由也未豁免)必须被拦。
  it("test_unrouted_unlisted_pkg_is_blocked", function()
    local dirs = { "verify", "spec_lane", "dry", "lint", "encoding", "ops", "surprise" }
    local violations = _check(nil, dirs)
    luassert.is.equal(1, #violations, _joined(violations))
    luassert.truthy(violations[1]:find("surprise", 1, true) ~= nil)
  end)

  -- 白名单内的非路由包豁免。
  it("test_whitelisted_non_routed_pkg_is_allowed", function()
    local violations = _check({ { name = "verify", pkg = "verify" } }, { "verify", "encoding" }, { "encoding" })
    luassert.is.equal(0, #violations, _joined(violations))
  end)

  -- stale 白名单条目(包已消失)必须报错销账。
  it("test_stale_whitelist_entry_is_blocked", function()
    local violations = _check(nil, nil, { "encoding", "ghost" })
    luassert.is.equal(1, #violations, _joined(violations))
    luassert.truthy(violations[1]:find("ghost", 1, true) ~= nil)
  end)

  -- 已挂路由的包仍留白名单里必须报错销账。
  it("test_routed_but_whitelisted_pkg_is_blocked", function()
    local violations = _check(nil, nil, { "encoding", "lint" })
    luassert.is.equal(1, #violations, _joined(violations))
    luassert.truthy(violations[1]:find("lint", 1, true) ~= nil)
  end)

  -- 子命令重名必须被拦。
  it("test_duplicate_command_name_is_blocked", function()
    local commands = {
      { name = "verify", pkg = "verify" },
      { name = "verify", pkg = "verify" },
    }
    local violations = _check(commands, { "verify" }, {})
    luassert.is.equal(1, #violations, _joined(violations))
    luassert.truthy(violations[1]:find("重复", 1, true) ~= nil)
  end)
end)
