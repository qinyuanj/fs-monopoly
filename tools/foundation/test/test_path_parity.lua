---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/foundation/test/test_path_parity.lua") end
require("test.bootstrap").install_package_paths()

-- 路径代数与运行时转发的独立行为证明(ADR 0083 深化)。
-- 期望值来自手写边角表与公开接口规约,不复制被测实现生成答案。
local check = require("luassert")
local path = require("foundation.path")

local test_source = debug.getinfo(1, "S").source:gsub("^@", "")
local test_dir = test_source:match("^(.*)/[^/]+$") or "tools/foundation/test"
local foundation_dir = test_dir .. "/.."
local runtime = dofile(foundation_dir .. "/runtime_path_ops.lua")

describe("path join root regression", function()
  -- 根基段与相对子段拼接不能丢根;两个公开入口必须保持同一答案。
  it("keeps the root when joining a relative child", function()
    check.equal("/x", path.join_path("/", "x"))
    check.equal("/x", runtime.join("/", "x"))
  end)
end)

-- 边角表:每个函数都过一遍。期望值手写,不做"实现算什么就是什么"的自证。
local EDGE_CASES = {
  { label = "empty", value = "", normalized = "", absolute = false, parent = nil, simplified = "", native = "" },
  { label = "posix root", value = "/", normalized = "/", absolute = true, parent = nil, simplified = "/", native = "/" },
  { label = "drive root", value = "C:/", normalized = "C:/", absolute = true, parent = nil, simplified = "C:", native = "C:/" },
  { label = "drive only", value = "C:", normalized = "C:", absolute = false, parent = nil, simplified = "C:", native = "C:" },
  { label = "double slash", value = "a//b", normalized = "a//b", absolute = false, parent = "a/", simplified = "a/b", native = "a//b" },
  { label = "dotdot", value = "D:/x/../y", normalized = "D:/x/../y", absolute = true, parent = "D:/x/..", simplified = "D:/y", native = "D:/x/../y" },
  { label = "nil", value = nil, normalized = "", absolute = false, parent = nil, simplified = "", native = "" },
  { label = "msys", value = "/d/dev", normalized = "/d/dev", absolute = true, parent = "/d", simplified = "/d/dev", native = "D:/dev" },
  { label = "unc", value = "//srv/share", normalized = "//srv/share", absolute = true, parent = "//srv", simplified = "/srv/share", native = "//srv/share" },
}

describe("path edge table", function()
  it("normalizes backslashes to forward slashes", function()
    for _, case in ipairs(EDGE_CASES) do
      check.equal(case.normalized, path.normalize_path(case.value), "normalize_path " .. case.label)
    end
    check.equal("D:/x", path.normalize_path("D:\\x"))
  end)

  it("recognizes drive and posix-root absolute forms", function()
    for _, case in ipairs(EDGE_CASES) do
      check.equal(case.absolute, path.is_absolute_path(case.value), "is_absolute_path " .. case.label)
    end
  end)

  it("returns nil for a path without a parent", function()
    for _, case in ipairs(EDGE_CASES) do
      check.equal(case.parent, path.split_parent(case.value), "split_parent " .. case.label)
      check.equal(case.parent, path.parent_dir(case.value), "parent_dir " .. case.label)
    end
  end)

  it("simplifies dot segments without touching the filesystem", function()
    for _, case in ipairs(EDGE_CASES) do
      check.equal(case.simplified, path.simplify_path(case.value), "simplify_path " .. case.label)
    end
  end)

  it("maps msys drive prefixes to native drive letters", function()
    for _, case in ipairs(EDGE_CASES) do
      check.equal(case.native, path.to_native_drive(case.value), "to_native_drive " .. case.label)
    end
  end)

  it("treats a single segment as its own normalization", function()
    for _, case in ipairs(EDGE_CASES) do
      check.equal(case.normalized, path.join_path(case.value), "join_path " .. case.label)
    end
  end)
end)

describe("runtime source path behavior", function()
  it("preserves source resolution and simplification semantics", function()
    check.equal("C:/x", runtime.strip_source_prefix("@C:/x"))
    -- resolve_source_path 只做"剥前缀 + 判绝对 + 拼",不 simplify:这是它原有的语义,
    -- 化简交给调用方按需走 path.resolve_path,不在这次收敛里顺手改行为。
    check.equal("D:/x/../y", runtime.resolve_source_path("D:/x/../y", "C:/base"))
    check.equal("D:/base/tools/cli.lua", runtime.resolve_source_path("@tools/cli.lua", "D:/base"))
    check.equal("D:/y", path.resolve_path("D:/x/../y", ""))
  end)

  it("probes existence through the primitives leaf", function()
    local env = require("foundation.env")
    local fs = require("foundation.fs")
    local root = env.make_temp_path("path_parity_probe", "")
    local ok, err = xpcall(function()
      check.truthy(fs.ensure_dir(root .. "/inner"))
      check.truthy(fs.write_file(root .. "/inner/a.lua", "x"))
      check.equal("dir", runtime.probe_path(root .. "/inner"))
      check.is_true(runtime.path_exists(root .. "/inner"))
      check.is_false(runtime.is_dir(root .. "/inner/a.lua"))
    end, debug.traceback)
    check.truthy(fs.remove_path(root))
    check.is_true(ok, err)
  end)
end)

-- 装载面:path.lua 必须能在 package.path 装好之前被 dofile —— 否则 bootstrap 用不了它。
describe("path is loadable without require", function()
  it("declares no require call at all", function()
    local handle = assert(io.open(foundation_dir .. "/path.lua", "rb"))
    local source = handle:read("*a")
    handle:close()
    local body = source:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
    check.is_nil(body:find("require%s*%("), "path.lua must not call require")
  end)

  it("dofiles from a bare directory with a sentinel package path", function()
    local env = require("foundation.env")
    local fs = require("foundation.fs")
    local root = env.make_temp_path("path_leaf_dofile", "")
    local saved_path = package.path
    local saved_primitives = package.loaded["foundation.primitives"]
    local ok, err = xpcall(function()
      check.truthy(fs.ensure_dir(root))
      check.truthy(fs.copy_file(foundation_dir .. "/path.lua", root .. "/path.lua"))
      check.truthy(fs.copy_file(foundation_dir .. "/primitives.lua", root .. "/primitives.lua"))
      package.loaded["foundation.primitives"] = nil
      package.path = "/sentinel/?.lua"
      local leaf = dofile(root .. "/path.lua")
      for _, name in ipairs({
        "normalize_path", "is_absolute_path", "join_path", "split_parent", "parent_dir",
        "simplify_path", "resolve_path", "to_native_drive",
      }) do
        check.equal("function", type(leaf[name]), "missing function: " .. name)
      end
      check.equal("/x", leaf.join_path("/", "x"))
      check.equal("D:/dev", leaf.to_native_drive("/d/dev"))
      check.is_nil(leaf.split_parent("/"))
      check.equal("D:/y", leaf.resolve_path("D:/x", "../y"))
    end, debug.traceback)
    package.path = saved_path
    package.loaded["foundation.primitives"] = saved_primitives
    check.truthy(fs.remove_path(root))
    check.is_true(ok, err)
  end)
end)
