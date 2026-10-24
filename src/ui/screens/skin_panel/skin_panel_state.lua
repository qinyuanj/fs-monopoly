-- 皮肤商店屏的展示状态(#204):只有开关、页码与所属角色;归属、穿戴与在途购买
-- 归皮肤归属模块。
local state = {}

function state.ensure(root_state)
  local ui = assert(assert(root_state, "missing_state").ui, "missing_state")
  ui.skin_panel = ui.skin_panel or { open = false, page_index = 1 }
  return ui.skin_panel
end

return state
