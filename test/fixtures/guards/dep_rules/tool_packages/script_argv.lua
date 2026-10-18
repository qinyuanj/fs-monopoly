local proc = require("foundation.proc")
return proc.run_command({ "lua", "tools/packages/test_runner/runner.lua", "--", "test_empty.lua" })
