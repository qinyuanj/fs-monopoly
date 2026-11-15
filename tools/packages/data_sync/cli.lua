-- packages/data_sync/cli.lua —— sync-data 子命令(部署目录 Data 导出回同步)
--
-- 统一接口形态(#300 决议):本文件 return 纯接口模块:
--   M.main(args, env) -> 退出码(0 成功 / 1 业务失败 / 2 用法错误 / 3 不可用)
--   M.usage()         -> 完整 usage 文本(包内单一真源,顶层 <cmd> --help 转发)
--
-- 实现:进程内调用 packages.data_sync.sync_data(零参数;--help/-h 在壳内消费)。
-- 行为真源见 packages/data_sync/sync_data.lua。
local M = {}

local tool_cli = require("foundation.tool_cli")

local sync_data = require("packages.data_sync.sync_data")

function M.usage()
  return table.concat({
    "用法: lua5.4 tools/cli.lua sync-data",
    "",
    "从部署目录(LuaSource_大富翁/)把编辑器最新导出回同步进仓库:",
    "  Data/Prefab.lua    字节原样拷贝;",
    "  Data/UINodes.lua   转换为 Data/UIManagerNodes.lua(按 id 聚合排序,无 length 行);",
    "  EggyAPI.lua / EggyEditorAPI.lua  字节原样拷贝到仓库根(宿主 API 存根,第三方边界)。",
    "零参数、零开关;家目录与部署目录解析复用 deploy(原生 %USERPROFILE%,ADR 0083),",
    "不出现第二份实现。本命令只读部署目录,不需要 robocopy。",
    "退出码: 0 成功 / 1 业务失败(部署目录缺文件或解析失败) / 2 多余参数 /",
    "3 不可用:取不到 %USERPROFILE%(status=unavailable,未写任何文件;环境问题不是业务失败)。",
    "行为真源见 packages/data_sync/sync_data.lua。",
    "",
  }, "\n") .. "\n"
end

function M.main(args, env)
  local help = tool_cli.help_exit(args, M.usage)
  if help ~= nil then
    return help
  end
  return sync_data.main(args)
end

return M
