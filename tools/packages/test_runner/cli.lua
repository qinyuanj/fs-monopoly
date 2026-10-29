local M = {}
function M.usage()
  return table.concat({
    "用法: lua tools/packages/test_runner/runner.lua [--run <profile>|--helper=<path>|--output=<TAP|path>|--pattern=<pat>|-- <files...>]",
    "", "真实 busted 运行器；失败、errors、空集合或空文件使车道失败。",
    "支持 --file-list=<path> 纯文本逐行文件清单；拒绝缺失或重复文件身份。",
    "--durations-out=<path> 逐行写「秒数<TAB>文件」实测耗时（spec-lane 分片时长缓存数据源）。",
    "无 --run 回退 spec_profiles default profile。", "",
  }, "\n") .. "\n"
end
function M.main(args)
  local help = require("foundation.tool_cli").help_exit(args, M.usage)
  if help ~= nil then return help end
  local command = require("packages.test_runner.lua54").argv_prefix()
  for _, value in ipairs(args or {}) do command[#command + 1] = value end
  local result = require("foundation.proc").run_command(command)
  io.write(result.output or "")
  return result.code or (result.ok and 0 or 1)
end
return M
