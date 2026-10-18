require("test.bootstrap").install_package_paths()

local git_query = require("test.guards.lib.git_query")

local M = {}

local function _gitlinks()
  local output, err = git_query.run_git({ "ls-files", "-s" })
  if output == nil then
    return nil, err
  end

  local links = {}
  for _, line in ipairs(git_query.split_lines(output)) do
    if line:match("^160000 ") then
      local path = line:match("%d+%s+[%da-f]+%s+%d+\t(.+)$")
      if path ~= nil then
        links[#links + 1] = path
      end
    end
  end
  return links
end

-- 拦截生成物/本地件误提交。
local _TRACKED_PATHSPEC_RULES = {
  { pathspec = ".claude/worktrees", message = "tracked generated/local artifact" },
}

function M.run()
  local violations = {}

  for _, rule in ipairs(_TRACKED_PATHSPEC_RULES) do
    local matches, tracked_err = git_query.tracked_matches(rule.pathspec)
    if matches == nil then
      return { ok = false, error = "repo_hygiene error: " .. tostring(tracked_err) }
    end
    for _, match in ipairs(matches) do
      violations[#violations + 1] = "repo_hygiene: " .. rule.message .. " " .. tostring(match)
    end
  end

  local gitlinks, gitlinks_err = _gitlinks()
  if gitlinks == nil then
    return { ok = false, error = "repo_hygiene error: " .. tostring(gitlinks_err) }
  end
  for _, path in ipairs(gitlinks) do
    violations[#violations + 1] = "repo_hygiene: gitlink " .. tostring(path)
  end

  if #violations > 0 then
    return {
      ok = false,
      error = table.concat(violations, "\n"),
    }
  end

  return { ok = true, message = "repo_hygiene ok" }
end

return M
