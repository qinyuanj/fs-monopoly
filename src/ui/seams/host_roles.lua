local host_slot = require("src.ui.seams.host_slot")

local _empty_roles = {}

-- 宿主角色名册 port：resolve_roles 未装配时返回共享空表，resolve_role_with
-- 返回 nil，语义对齐 host.role_resolver 在无 runtime context 时的降级。
return host_slot.new({
  { name = "resolve_roles", default = _empty_roles },
  { name = "resolve_role_with" },
})

