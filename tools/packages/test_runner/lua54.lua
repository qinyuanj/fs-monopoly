--- Neutral command prefix; interpreter selection lives in foundation.lua54.
local path = require("foundation.path")
local interpreter = require("foundation.lua54")
local M = {}
function M.runner_path()
  local source = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("\\", "/")
  local dir = source:match("^(.*)/[^/]+$") or "tools/packages/test_runner"
  return path.normalize_path(path.join_path(dir, "runner.lua"))
end
function M.argv_prefix()
  return { interpreter.lua54_bin(), M.runner_path() }
end
return M
