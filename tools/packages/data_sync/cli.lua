-- packages/data_sync/cli.lua —— sync-data 子命令(部署目录 Data 导出回同步)
--
-- 统一接口形态(#300 决议):本文件 return 纯接口模块:
--   M.main(args, env) -> 退出码(0 成功 / 1 业务失败 / 2 用法错误 / 3 不在 WSL)
--   M.usage()         -> 完整 usage 文本(包内单一真源,顶层 <cmd> --help 转发)
--
-- 实现:进程内调用 packages.data_sync.sync_data(零参数;--help/-h 在壳内消费)。
-- 行为真源见 packages/data_sync/sync_data.lua。
local M = {}

local sync_data = require("packages.data_sync.sync_data")

function M.usage()
  return table.concat({
    "用法: lua5.4 tools/cli.lua sync-data",
    "",
    "从部署目录(LuaSource_大富翁/)把编辑器最新导出回同步进仓库:",
    "  Data/Prefab.lua    字节原样拷贝;",
    "  Data/UINodes.lua   转换为 Data/UIManagerNodes.lua(按 id 聚合排序,无 length 行);",
    "  EggyAPI.lua / EggyEditorAPI.lua  字节原样拷贝到仓库根(宿主 API 存根,第三方边界)。",
    "零参数、零开关;平台与部署目录解析复用 deploy(WSL 中运行,缺 cmd.exe/wslpath 退 3,ADR 0073)。",
    "行为真源见 packages/data_sync/sync_data.lua。",
    "",
  }, "\n") .. "\n"
end

function M.main(args, env)
  for _, value in ipairs(args or {}) do
    if value == "--help" or value == "-h" then
      io.write(M.usage())
      return 0
    end
  end
  return sync_data.main(args)
end

return M
