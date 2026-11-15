---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/foundation/test/test_path_parity.lua") end
require("test.bootstrap").install_package_paths()

-- 路径代数收敛的对照证明(ADR 0083 深化 / 候选 2)。
--
-- 本文件回答两个问题:
--   1. foundation.path 收编 runtime_path_ops 的代数后,除**已钉住的差异**外逐字节不变?
--   2. 三种"无父"语义(→ nil / → "." / → 入参)各归其位,没有悄悄换语义?
-- 旧实现冻结为 oracle(见下),只用于等价证明,不参与生产。
local check = require("luassert")
local path = require("foundation.path")

local test_source = debug.getinfo(1, "S").source:gsub("^@", "")
local test_dir = test_source:match("^(.*)/[^/]+$") or "tools/foundation/test"
local foundation_dir = test_dir .. "/.."
local runtime = dofile(foundation_dir .. "/runtime_path_ops.lua")

-- oracle:runtime_path_ops 收编前的 join(base, child)。逐字照抄旧实现,
-- 只用于证明"新实现要么逐字节相同、要么差异恰好是修掉的 bug"。
local function _legacy_join(base, child)
  local normalized_base = tostring(base or ""):gsub("\\", "/"):gsub("/+$", "")
  local normalized_child = tostring(child or ""):gsub("\\", "/"):gsub("^/+", "")
  if normalized_base == "" then
    return normalized_child
  end
  if normalized_child == "" then
    return normalized_base
  end
  return normalized_base .. "/" .. normalized_child
end

-- oracle:runtime_path_ops.dirname(无父 → ".")。该函数已删,冻结它只为对照调用点改写。
local function _legacy_dirname(value)
  local normalized = tostring(value or ""):gsub("\\", "/")
  return normalized:match("^(.*)/[^/]+$") or "."
end

-- oracle:runtime_path_ops.parent_dir(无父 → 入参)。上溯循环已改用它处,这里冻结旧语义。
local function _legacy_parent_dir(value)
  local normalized = tostring(value or ""):gsub("\\", "/"):gsub("/+$", "")
  local parent = normalized:match("^(.*)/[^/]+$")
  if parent == nil or parent == "" then
    return normalized
  end
  return parent
end

-- 与 test_path_join.lua:63 同一份段池;nil 用哨兵存取,保住洞的位置。
local SEGMENT_POOL = { "root", "a", "b", "", "/abs", "C:/drive", "x/", "/y", "p\\q", "NIL" }

local function _decode(value)
  if value == "NIL" then
    return nil
  end
  return value
end

local function _label(value)
  if value == nil then
    return "<nil>"
  end
  if value == "" then
    return "<empty>"
  end
  return value
end

-- 唯一的**已知差异**集合:旧 join 在这几种形态下丢信息,新实现(path.join_path)保留。
--   1. 空基段 + 绝对子段:旧实现剥掉子段的头斜杠,把 "/abs" 变成 "abs"(真 bug);
--   2. 尾斜杠基段 + 空子段:旧实现顺手剥掉基段的尾斜杠,新实现原样返回。
-- 差异集本身也被钉住:多一条或少一条都会红。
local KNOWN_DIVERGENCE = {
  ["<nil>|/abs"] = { legacy = "abs", current = "/abs" },
  ["<nil>|/y"] = { legacy = "y", current = "/y" },
  ["<empty>|/abs"] = { legacy = "abs", current = "/abs" },
  ["<empty>|/y"] = { legacy = "y", current = "/y" },
  ["x/|<empty>"] = { legacy = "x", current = "x/" },
  ["x/|<nil>"] = { legacy = "x", current = "x/" },
}

describe("path join parity with the frozen oracle", function()
  it("stays byte identical on the whole segment pool except the pinned divergence", function()
    local seen = {}
    local pairs_checked = 0
    for base_index = 1, #SEGMENT_POOL do
      for child_index = 1, #SEGMENT_POOL do
        local base = _decode(SEGMENT_POOL[base_index])
        local child = _decode(SEGMENT_POOL[child_index])
        local key = _label(base) .. "|" .. _label(child)
        local legacy = _legacy_join(base, child)
        local current = path.join_path(base, child)
        local known = KNOWN_DIVERGENCE[key]
        if known == nil then
          check.equal(legacy, current, "undocumented join drift at " .. key)
        else
          check.equal(known.legacy, legacy, "oracle drifted at " .. key)
          check.equal(known.current, current, "pinned fix drifted at " .. key)
        end
        seen[key] = true
        pairs_checked = pairs_checked + 1
      end
    end
    check.equal(#SEGMENT_POOL * #SEGMENT_POOL, pairs_checked)
    for key in pairs(KNOWN_DIVERGENCE) do
      check.is_true(seen[key] == true, "pinned divergence case disappeared: " .. key)
    end
  end)

  -- 隐藏差异:runtime_path_ops.join("/", "x") 旧实现返回 "x"(丢了根),这是 bug 不是回归。
  it("keeps the leading slash of an absolute child on an empty base", function()
    check.equal("x", _legacy_join("/", "x"))
    check.equal("/x", path.join_path("/", "x"))
    check.equal("/x", runtime.join("/", "x"))
  end)

  it("agrees with the old join on every shape the seam actually feeds it", function()
    local real_shapes = {
      { "D:/repo", "tools" },
      { "D:/repo", "foundation/package_path_helper.lua" },
      { "D:/repo", "tools/cli.lua" },
      { "D:/repo/", "/tools" },
      { ".", "tools/foundation/bootstrap.lua" },
      { "D:\\repo", "tools" },
    }
    for _, shape in ipairs(real_shapes) do
      check.equal(_legacy_join(shape[1], shape[2]), path.join_path(shape[1], shape[2]),
        "join drift on " .. tostring(shape[1]) .. " + " .. tostring(shape[2]))
    end
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

-- 三种"无父"语义:真需求是**分开**的三种,不能合并成一种。
describe("the three no-parent semantics", function()
  it("keeps nil for consumers that fall back themselves", function()
    -- fs.lua:68 → ensure_dir(nil) 直接成功;arch_policy/init.lua:382 → 或 "." 兜底;
    -- deploy.lua:88 → 或 env.current_dir() 兜底。nil 是这三个调用点的契约。
    check.is_nil(path.split_parent("/"))
    check.is_nil(path.split_parent("C:/"))
    check.is_nil(path.split_parent(""))
    check.is_nil(path.split_parent(nil))
    check.is_nil(path.parent_dir("a.lua"))
  end)

  it("substitutes a dot only at the call site that needs one", function()
    -- runtime_path_ops 里那个 dirname 消费者:无父时取当前目录。
    check.equal(".", _legacy_dirname("/"))
    check.equal(".", path.parent_dir("/") or ".")
    check.equal("D:/x", path.parent_dir("D:/x/y.lua") or ".")
  end)

  it("breaks the repo-root walk instead of returning the input", function()
    -- 旧 parent_dir 用"无父 → 返回入参"来终止循环;"/" 归一后再剥尾斜杠就是 ""。
    check.equal("", _legacy_parent_dir("/"))
    check.equal("/d", _legacy_parent_dir("/d"), "old parent_dir echoes its input when there is no parent")
    local parent = path.parent_dir("/")
    check.is_nil(parent, "walk must stop on nil, not on parent == probe")
    check.equal("D:/repo/tools/foundation", path.parent_dir("D:/repo/tools/foundation/bootstrap.lua"))
  end)
end)

describe("runtime_path_ops forwards to foundation.path", function()
  it("keeps the forwarded names and drops the duplicated ones", function()
    check.equal("function", type(runtime.normalize))
    check.equal("function", type(runtime.strip_source_prefix))
    check.equal("function", type(runtime.join))
    check.equal("function", type(runtime.is_absolute))
    check.equal("function", type(runtime.resolve_source_path))
    check.equal("function", type(runtime.probe_path))
    -- 两种"自造语义"的 dirname/parent_dir 已删,只剩 path 里的 nil 口径。
    check.is_nil(runtime.dirname, "runtime_path_ops.dirname must be gone")
    check.is_nil(runtime.parent_dir, "runtime_path_ops.parent_dir must be gone")
  end)

  it("answers exactly like foundation.path on the edge table", function()
    for _, case in ipairs(EDGE_CASES) do
      check.equal(path.normalize_path(case.value), runtime.normalize(case.value), "normalize " .. case.label)
      check.equal(path.is_absolute_path(case.value), runtime.is_absolute(case.value), "is_absolute " .. case.label)
    end
    check.equal("C:/x", runtime.strip_source_prefix("@C:/x"))
    -- resolve_source_path 只做"剥前缀 + 判绝对 + 拼",不 simplify:这是它原有的语义,
    -- 化简交给调用方按需走 path.resolve_path,不在这次收敛里顺手改行为。
    check.equal("D:/x/../y", runtime.resolve_source_path("D:/x/../y", "C:/base"))
    check.equal("D:/base/tools/cli.lua", runtime.resolve_source_path("@tools/cli.lua", "D:/base"))
    check.equal("D:/y", path.resolve_path("D:/x/../y", ""))
  end)

  it("probes existence through the primitives leaf", function()
    local primitives = require("foundation.primitives")
    local env = require("foundation.env")
    local fs = require("foundation.fs")
    local root = env.make_temp_path("path_parity_probe", "")
    local ok, err = xpcall(function()
      check.truthy(fs.ensure_dir(root .. "/inner"))
      check.truthy(fs.write_file(root .. "/inner/a.lua", "x"))
      for _, target in ipairs({ root .. "/inner", root .. "/inner/a.lua", root .. "/inner/nope" }) do
        check.equal(primitives.probe_path(target), runtime.probe_path(target), "probe drift on " .. target)
      end
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
