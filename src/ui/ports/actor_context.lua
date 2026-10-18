local actor_context = require("src.ui.coord.actor_context")

local actor_context_ports = {}

-- 只暴露 resolve_role_by_id:「用例层经端口自行解析行动者」的通路已拆(#442)——
-- 行动者归属在事件边界裁定一次,用例层只消费 intent.actor_role_id(ADR 0054,
-- GLOSSARY.md「行动者」)。边界代码解析点击者仍走接缝 resolve_from_event。
function actor_context_ports.build()
  return {
    resolve_role_by_id = function(role_id)
      return actor_context.resolve_role_by_id(role_id)
    end,
  }
end

return actor_context_ports

