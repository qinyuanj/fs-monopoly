require("test.bootstrap").install_package_paths()

local path_lib = require("foundation.path")
local git_query = require("test.guards.lib.git_query")

local M = {}

-- 根部显式白名单。当前工作树的已跟踪与未跟踪文件都检查，已删除路径不参与。
-- 仅包含项目主动承诺保持在根目录的文件与一级目录。
-- 生成物（build/、tmp/、luacov 残留等）由 `lua5.4 tools/cli.lua clean` 清理，
-- 因此不在白名单内；guard 通过 git 跟踪 + 未忽略未跟踪项检查，自然排除它们。
-- agent 在根目录新建任何未跟踪条目都会在此报违规。
local _WHITELIST = {
  ["main.lua"] = true,
  ["Data"] = true,
  ["EggyAPI.lua"] = true,
  -- 宿主 API 参考面第二件:编辑器 EUI 节点 API(2f6fb3d),与 EggyAPI.lua 同类,
  -- 宿主目录里即住根部。
  ["EggyEditorAPI.lua"] = true,
  ["CLAUDE.md"] = true,
  ["AGENTS.md"] = true,
  -- v1.0 基线变更记录（#68）。
  ["CHANGELOG.md"] = true,
  ["GLOSSARY.md"] = true,
  ["CODING_STANDARDS.md"] = true,
  -- 项目使命。
  ["mission.md"] = true,
  [".gitignore"] = true,
  -- 文本源码统一 LF 的唯一真源（#475）：部署目录 = 仓库字节级 LF 镜像契约的源侧保证。
  [".gitattributes"] = true,
  ["src"] = true,
  ["test"] = true,
  ["docs"] = true,
  ["tools"] = true,
  [".agents"] = true,
  [".claude"] = true,
  ["skills-lock.json"] = true,
  -- 邻接 uml-viewer 的质量配置(#93):上游 uml_posix.py 只在项目根读 uml-quality.json,
  -- 位置由上游契约决定。.uml-viewer/、target/ 等本地产物走 .gitignore,不进白名单。
  ["uml-quality.json"] = true,
  -- 真实 uml crap|mutate 跑出的度量(.metrics/crap.edn、mutate/*.edn)按上游 README
  -- 入库(#69 维护者决定),是已跟踪的根级目录。
  [".metrics"] = true,
  -- crapper / mutator 以最近的 .busted 定模块根并读 busted 配置(#99),只认仓根。
  [".busted"] = true,
  -- 可选 pre-push hook(#126),经 `git config core.hooksPath .githooks` 启用。
  [".githooks"] = true,
  -- Eggy 编辑器同步配置(projectID / mapDir / excludePatterns),由编辑器在项目根读取,
  -- 维护者决定入库(2026-10-29)。
  ["eggy.json"] = true,
  -- `uml ir` 生成的仓根 policy.edn(ADR 0070 / #99)走 .gitignore,不进白名单;
  -- 人手维护的推演在 docs/architecture.proposals.edn。
}

local function _top_level_name(path)
  local normalized = path_lib.normalize_path(path)
  return normalized:match("^([^/]+)")
end

-- 核心判定（供 spec 注入合成输入;run 也走同一逻辑,保证 spec 约束真实行为）:
-- 给定根级条目名列表,返回不在白名单中的名字,同名只报一次。
-- 可选 seen 表用于跨批次去重（run 里 tracked/untracked 两批共用）。
function M.check(names, seen)
  local violations = {}
  seen = seen or {}
  for _, name in ipairs(names or {}) do
    if not seen[name] then
      seen[name] = true
      if not _WHITELIST[name] then
        violations[#violations + 1] = name
      end
    end
  end
  return violations
end

function M.run()
  local paths, err = git_query.list_files(".")
  if paths == nil then
    return { ok = false, error = "root_whitelist_guard error: " .. tostring(err) }
  end
  local names = {}
  local seen = {}
  for _, path in ipairs(paths) do
    local name = _top_level_name(path)
    if name ~= nil and not seen[name] then
      seen[name] = true
      names[#names + 1] = name
    end
  end
  local violations = {}
  for _, name in ipairs(M.check(names)) do
    violations[#violations + 1] = "root_whitelist_guard: non-whitelisted root entry: " .. name
  end

  if #violations > 0 then
    return {
      ok = false,
      error = table.concat(violations, "\n"),
    }
  end

  return { ok = true, message = "root_whitelist_guard ok" }
end

return M
