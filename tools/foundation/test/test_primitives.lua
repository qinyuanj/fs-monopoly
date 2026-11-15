---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/foundation/test/test_primitives.lua") end
require("test.bootstrap").install_package_paths()

-- foundation.primitives:全仓唯一一份 os/io 原语叶子(ADR 0083 深化)。
-- 约束:零 require、只碰 os/io/string/table/debug,故能在 package.path 装好前被 dofile。
local check = require("luassert")
local primitives = require("foundation.primitives")
local shell = require("foundation.shell")

describe("primitives.quote", function()
  it("matches shell.shell_quote byte for byte on hostile input", function()
    -- 引号只有一份口径:叶子与 shell 必须逐字相同,否则执行缝与调用方各说各话。
    local hazards = {
      "plain", "with space", "a'b", "a\"b", "%PATH%", "a&b|c<d>e^f(g)h!i",
      "中文 路径", "", "'", "''", "C:/Program Files/Git/bin/bash.exe",
    }
    for _, value in ipairs(hazards) do
      check.equal(shell.shell_quote(value), primitives.quote(value), "quote mismatch: " .. value)
    end
  end)

  it("rejects NUL and newlines the way the execution seam does", function()
    check.has_error(function() primitives.quote("a\nb") end)
    check.has_error(function() primitives.quote("a\0b") end)
  end)

  it("keeps a bare-word fast path separate from the always-quote form", function()
    -- lua_env 拼 env -u 前缀要的是"能省则省",与恒引号是两种形态,不能合并。
    check.equal("luarocks", primitives.quote_if_needed("luarocks"))
    check.equal("'with space'", primitives.quote_if_needed("with space"))
    check.equal("'a'\\''b'", primitives.quote_if_needed("a'b"))
  end)
end)

describe("primitives.probe_path", function()
  local fs = require("foundation.fs")
  local env = require("foundation.env")

  it("answers file dir missing without writing anything", function()
    local root = env.make_temp_path("primitives_probe", "")
    local ok, err = xpcall(function()
      check.truthy(fs.ensure_dir(root .. "/inner"))
      check.truthy(fs.write_file(root .. "/inner/a.lua", "x"))
      check.equal("dir", primitives.probe_path(root .. "/inner"))
      check.equal("file", primitives.probe_path(root .. "/inner/a.lua"))
      check.equal("missing", primitives.probe_path(root .. "/inner/nope"))
      check.is_true(primitives.exists(root .. "/inner"))
      check.is_true(primitives.readable(root .. "/inner/a.lua"))
      check.is_false(primitives.readable(root .. "/inner"))
    end, debug.traceback)
    check.truthy(fs.remove_path(root))
    check.is_true(ok, err)
  end)
end)

describe("primitives.tmp_dir and unique_name", function()
  it("resolves an absolute forward-slash temp dir", function()
    local dir = primitives.tmp_dir()
    check.matches("^%a:/", dir)
    check.is_nil(dir:find("\\"))
    check.is_nil(dir:match("/$"))
  end)

  it("produces distinct names for the same prefix", function()
    local seen = {}
    for _ = 1, 200 do
      local name = primitives.unique_name("eggy_exec", ".sh")
      check.is_nil(seen[name], "duplicate temp name: " .. name)
      seen[name] = true
      check.matches("^eggy_exec_.+%.sh$", name)
    end
  end)
end)

describe("primitives.self_dir and shared", function()
  it("finds the directory holding this module", function()
    -- level 0 = primitives.lua 自己;level 1 = self_dir 的调用者(供 shared 用)。
    local dir = primitives.self_dir(0)
    check.matches("/tools/foundation$", dir)
    check.is_nil(dir:find("\\"))
  end)

  it("resolves the caller directory at level 1", function()
    check.matches("/test$", primitives.self_dir(1))
  end)

  it("loads a sibling once and returns the same table afterwards", function()
    local first = primitives.shared("path")
    local second = primitives.shared("path")
    check.equal("table", type(first))
    check.equal("function", type(first.join_path))
    check.is_true(first == second, "shared must memoize: two loads split module state")
  end)

  it("returns nil for an unknown sibling instead of throwing", function()
    check.is_nil(primitives.shared("no_such_foundation_module"))
  end)
end)

describe("primitives is a leaf", function()
  it("declares no top-level require", function()
    -- 叶子一旦 require,就会在 package.path 装好前炸;这是它能被 dofile 的唯一理由。
    local handle = assert(io.open(primitives.self_dir(0) .. "/primitives.lua", "rb"))
    local source = handle:read("*a")
    handle:close()
    local body = source:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
    check.is_nil(body:find("require%s*%("), "primitives must not require anything")
  end)
end)
