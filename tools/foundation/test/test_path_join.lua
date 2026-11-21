---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/foundation/test/test_path_join.lua") end
require("test.bootstrap").install_package_paths()

-- join_path 的变参折叠规约(issue #211)。纯字符串演算，不碰文件系统。
local check = require("luassert")
local path = require("foundation.path")
local property = require("test.support.property")

describe("path join segment count", function()
  it("joins two segments", function()
    check.equal("root/tmp", path.join_path("root", "tmp"))
  end)
  it("joins three segments instead of dropping the third", function()
    check.equal("root/tmp/lua54-shim", path.join_path("root", "tmp", "lua54-shim"))
  end)
  it("joins an arbitrary number of segments", function()
    check.equal("root/a/b/c/d", path.join_path("root", "a", "b", "c", "d"))
  end)
  it("returns the sole segment when only one is given", function()
    check.equal("root", path.join_path("root"))
  end)
  it("returns an empty string when no segment is given", function()
    check.equal("", path.join_path())
  end)
end)

describe("path join empty and nil segments", function()
  it("skips an empty leading segment", function()
    check.equal("tmp/lua54-shim", path.join_path("", "tmp", "lua54-shim"))
  end)
  it("skips an empty middle segment", function()
    check.equal("root/lua54-shim", path.join_path("root", "", "lua54-shim"))
  end)
  it("skips an empty trailing segment", function()
    check.equal("root/tmp", path.join_path("root", "tmp", ""))
  end)
  -- nil 洞不能让 ipairs 提前截断而吞掉后续段。
  it("treats a nil segment as empty and keeps the segments after it", function()
    check.equal("root/lua54-shim", path.join_path("root", nil, "lua54-shim"))
  end)
  it("treats a nil leading segment as empty", function()
    check.equal("tmp/lua54-shim", path.join_path(nil, "tmp", "lua54-shim"))
  end)
  it("preserves an absolute child when the base is empty or nil", function()
    check.equal("/abs", path.join_path("", "/abs"))
    check.equal("/abs", path.join_path(nil, "/abs"))
  end)
  it("preserves a trailing base separator when the child is empty or nil", function()
    check.equal("x/", path.join_path("x/", ""))
    check.equal("x/", path.join_path("x/", nil))
  end)
end)

describe("path join separator normalization", function()
  it("collapses redundant separators between segments", function()
    check.equal("root/tmp/lua54-shim", path.join_path("root/", "/tmp/", "/lua54-shim"))
  end)
  it("normalizes backslashes across every segment", function()
    check.equal("root/a/b/c", path.join_path("root\\a", "b\\c"))
  end)
  it("preserves an absolute base across multiple segments", function()
    check.equal("/root/tmp/lua54-shim", path.join_path("/root", "tmp", "lua54-shim"))
  end)
  it("preserves a windows drive base across multiple segments", function()
    check.equal("C:/root/tmp/lua54-shim", path.join_path("C:/root", "tmp", "lua54-shim"))
  end)
end)

-- nil 用哨兵存取，并靠 count 保住洞的位置。
local SEGMENT_POOL = { "root", "a", "b", "", "/abs", "C:/drive", "x/", "/y", "p\\q", "NIL" }
local function _generate_segments(rng)
  local count = rng:int(1, 5)
  local values = {}
  for index = 1, count do values[index] = rng:pick(SEGMENT_POOL) end
  return { count = count, values = values }
end
local function _unpack_segments(case)
  local args = {}
  for index = 1, case.count do
    local value = case.values[index]
    args[index] = (value ~= "NIL") and value or nil
  end
  return table.unpack(args, 1, case.count)
end

describe("path join folding laws", function()
  it("is associative folding n segments at once equals folding them pairwise", function()
    property.for_all(_generate_segments, function(case)
      local at_once = path.join_path(_unpack_segments(case))
      local pairwise = path.join_path(case.values[1] ~= "NIL" and case.values[1] or nil)
      for index = 2, case.count do
        local value = case.values[index]
        pairwise = path.join_path(pairwise, (value ~= "NIL") and value or nil)
      end
      check.equal(at_once, pairwise)
    end)
  end)
  it("agrees with normalize path on a single segment", function()
    property.for_all(_generate_segments, function(case)
      local value = case.values[1]
      local segment = (value ~= "NIL") and value or nil
      check.equal(path.normalize_path(segment), path.join_path(segment))
    end)
  end)
  it("is idempotent re joining an already joined path changes nothing", function()
    property.for_all(_generate_segments, function(case)
      local joined = path.join_path(_unpack_segments(case))
      check.equal(joined, path.join_path(joined))
    end)
  end)
end)
