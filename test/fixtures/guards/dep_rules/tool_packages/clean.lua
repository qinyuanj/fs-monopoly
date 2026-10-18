local proc = require("foundation.proc")
-- Direct tool package scripts live under tools/packages/test_runner/runner.lua.
local description = "tools/packages/test_runner/runner.lua is a package script"
local primitive = loadfile("tools/foundation/proc.lua")
local result = proc.run_command({ "lua", "tools/cli.lua", "spec-lane", "--help" }); local after_call = "tools/packages/test_runner/runner.lua"
local function command_for_description(_)
  return { "lua", "tools/cli.lua", "--help" }
end
local nested = proc.run_command(
  command_for_description("tools/packages/test_runner/runner.lua")
)
return { description = description, primitive = primitive, result = result, after_call = after_call, nested = nested }
