-- 「带 reset 的默认值配置模块」工厂。
-- 收敛 config/content/constants 与 config/gameplay/debug_flags 的同形模块体：
-- defaults 表 → 已铺好默认值、且挂 reset() 的模块表。
-- reset() 清掉调用方后加的所有键,再铺回 defaults(元表上的 reset 自身不受影响)。
local M = {}

local function _apply_defaults(target, defaults)
  for key, value in pairs(defaults) do
    target[key] = value
  end
end

function M.build(defaults)
  local module_table = {}
  _apply_defaults(module_table, defaults)
  setmetatable(module_table, {
    __index = {
      reset = function()
        for key in pairs(module_table) do
          module_table[key] = nil
        end
        _apply_defaults(module_table, defaults)
      end,
    },
  })
  return module_table
end

return M

