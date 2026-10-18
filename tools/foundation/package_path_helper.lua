-- package.path 装配:把仓库的 tools/ / test/ / 根目录接进 Lua 的模块搜索路径。
--
-- ⚠️ 下面的 _normalize_path / _join 与 foundation(fs/path)的同名工具**结构重复,
-- 而且这个重复是故意的,别合并**(工单 #126)。
--
-- 原因:本文件是 bootstrap 的**第一块砖**,被 `dofile` 而非 `require` 加载 ——
--   tools/foundation/bootstrap.lua:25
--   test/bootstrap.lua:22
-- 在它跑完之前,package.path 还没装好,`require("foundation.fs")` 这类 require **根本不可用**。
-- 也就是说它不可能复用 foundation —— 它正是那个让 foundation 变得可 require 的东西。
--
-- ⚠️ 这条约束**没有任何测试能钉住**。`/dry` 是 report-only 的顾问工具,不是 merge gate;
-- 它会反复把这两处报成结构重复(实测相似度 0.75 / 0.81)。谁要是「顺手修好」它,
-- **不会有任何测试变红** —— 只会在下一次 bootstrap 时炸。注释是这里唯一的护栏。
local package_path_helper = {}

local function _normalize_path(path)
  return tostring(path or ""):gsub("\\", "/")
end

local function _join(base, child)
  local normalized_base = _normalize_path(base):gsub("/+$", "")
  local normalized_child = _normalize_path(child):gsub("^/+", "")
  if normalized_base == "" then
    return normalized_child
  end
  if normalized_child == "" then
    return normalized_base
  end
  return normalized_base .. "/" .. normalized_child
end

local function _contains_path(haystack, path_pattern)
  return tostring(haystack):find(path_pattern, 1, true) ~= nil
end

local function _prepend_path(path_pattern)
  if not _contains_path(package.path, path_pattern) then
    package.path = path_pattern .. ";" .. package.path
  end
end

function package_path_helper.install_eggy_package_paths(opts)
  opts = opts or {}
  local repo_root = _normalize_path(opts.repo_root or ".")

  local canonical_patterns = {
    _join(repo_root, "tools/?.lua"),
    _join(repo_root, "tools/?/init.lua"),
    _join(repo_root, "tools/bridge/?.lua"),
    _join(repo_root, "tools/bridge/?/init.lua"),
    _join(repo_root, "test/?.lua"),
    _join(repo_root, "test/?/init.lua"),
    _join(repo_root, "test/fixtures/?.lua"),
    _join(repo_root, "?.lua"),
    _join(repo_root, "?/init.lua"),
  }

  for index = #canonical_patterns, 1, -1 do
    _prepend_path(canonical_patterns[index])
  end
end

-- LuaRocks 模块路径不在这里装配:测试与质量工具统一从受控 Lua 环境装载
-- (foundation.lua_env.install_paths / require_controlled),本仓不自举、不写任何 tree。

return package_path_helper
