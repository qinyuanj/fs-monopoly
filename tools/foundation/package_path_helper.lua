-- package.path 装配:把仓库的 tools/ / test/ / 根目录接进 Lua 的模块搜索路径。
--
-- 硬约束:本文件必须**自包含**。它会被单独复制进临时仓根运行 ——
-- test_bootstrap.lua 的 install 用例只拷这一份文件进临时目录,并且是在
-- `package.path = "/sentinel/?.lua"` 的哨兵状态下 dofile 的。也就是说:
--   * 不能 require 任何东西(那时 package.path 里没有仓库模式);
--   * 不能 dofile 任何兄弟文件(临时目录里没有它们);
--   * 下面的 _normalize_path / _join 因此只能自带一份,与 foundation 的同名工具
--     结构重复是**约束的结果**,不是疏忽,别合并。
-- 合并的后果不是测试变红,而是 bootstrap 在哨兵/临时仓根下直接炸 —— 这两条测试
-- (install adds repository paths / loading bootstrap touches no module search path)
-- 是唯一的机械护栏。
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
