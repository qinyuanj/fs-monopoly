local proc = require("foundation.proc")
-- Direct tool package scripts live under tools/packages/test_runner/runner.lua.
local description = "tools/packages/test_runner/runner.lua is a package script"
local primitive = loadfile("tools/foundation/proc.lua")
local result = proc.run_command({ "lua", "tools/cli.lua", "spec-lane", "--help" })
return { description = description, primitive = primitive, result = result }
