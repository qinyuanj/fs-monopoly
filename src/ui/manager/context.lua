-- ui.manager.context — UIManager 子树共享运行时状态 + 对外 facade 表底座。
-- 簇内子模块显式 require 本模块取共享态(nodes_list / client_role / allroles 等),
-- 替代旧的全局 UIManager 互引（#61）：子树内部不再读全局 UIManager。
-- utils.lua 在本表上挂类、枚举与查询函数,组装成对外 UIManager facade 并发布到 _G。
-- 因 utils 返回的正是本表,`_G.UIManager.client_role` 与簇内 `context.client_role`
-- 指向同一存储,runtime_ui 等消费点的 client_role 读写语义原样保留。
--
-- 角色列表经 foundation runtime port 取,避免 ui 层直读 host 角色全局(dep_rules 规则)。
-- ui_bootstrap 在 GAME_INIT 里 require 本子树前已 resolve_roles() 并 install 全局角色,
-- 故此处取到同一批角色。仅 ui_bootstrap 惰性 require 子树,不会提前触发角色解析。
local runtime_ports = require("src.foundation.ports.runtime_ports")

---@class UIManager
---@field client_role Role?
local context = {}

context.allroles = runtime_ports.resolve_roles()
context.client_role = nil
context.nodes_list = {} --[[@as table<ENode, UIManager.ENode?>]]
context.name_node_mapping = {} --[[@as table<string, UIManager.ENode[]?> ]]
---@type
--- {
---     [string]: {
---         trigger: integer,
---         [ENode]: {
---             callbacks: fun(data: {
---                 role: Role,
---                 target: UIManager.ENodeUnion,
---                 listener: UIManager.Listener
---             })[],
---             node: UIManager.ENodeUnion
---         }?
---     }?
--- }
context.event_handlers = {}
context.config_list = nil

return context

