-- choice 归属者与本地身份解析(自 ui_sync/choice_state.lua 拆分,
-- >100 mutation sites 行为保持):choice 契约 owner/meta 角色 id 优先,
-- 回落当前回合玩家;房间席位判定只走 resolve_roles 遍历。
local choice_contract = require("src.config.choice.contract")
local role_id_utils = require("src.foundation.identity")
local runtime_ui = require("src.ui.render.support.runtime_ui")
local runtime_ports = require("src.foundation.ports.runtime_ports")

local choice_owner = {}

local function _current_player_index(game)
  return game and game.turn and game.turn.current_player_index or nil
end

local function _player_at_index(game, current_index)
  return current_index and game and game.players and game.players[current_index] or nil
end

function choice_owner.resolve_owner_role_id(game, choice)
  local owner_role_id = choice_contract.resolve_owner_or_meta_role_id(choice)
  if owner_role_id ~= nil then
    return owner_role_id
  end
  local player = _player_at_index(game, _current_player_index(game))
  return role_id_utils.normalize(player and player.id or nil)
end

-- 房间席位判定:owner 是否是本进程服务的席位之一。
-- 蛋仔运行时是「一个 Lua 进程服务整个房间」——resolve_roles() 取自
-- GameAPI.get_all_valid_roles()(host/role_ports.lua:31-40),无客户端归属过滤;
-- manager/host_push.lua:19-27 在 client_role 为 nil 时遍历 allroles 广播,
-- 只拥有自身席位的进程不可能广播到别人的席位。故「本机 role」在此模型下
-- 是错位概念:进程同时服务所有席位。
--
-- 开面板 ≠ 授权操作:可见性由下游逐席位决定(choice_helpers.switch_modal_canvas
-- 只给 can_operate 的席位模态画布,旁观者 CANVAS_BASE);操作授权独立走
-- validator_actor(校验 actor_role_id == current_role_id)与
-- item_slot_overlay.blocks_click,均从 data.role 取真实点击者。
--
-- 同类错误的既有先例(均真机复现):ui_sync/camera.lua:153-157 镜头焊死在
-- 「本机 role」;input/item_slot_overlay.lua:6-11 房间共享布尔量静音所有人点击。
--
-- 语义为「owner 是否是本进程该为之开面板的席位」,而非「是否是我的席位」。
-- 判定只走房间席位遍历——resolve_from_event 的「点击者」语义与「进程服务的席位」
-- 语义不兼容(#444):reconcile 路径无点击事件、client_role 在作用域外恒 nil,
-- 偶然导致席位判定生效;一旦 client_role 有值且不等于 owner,原第一级短路即回到
-- #438 的错误形状(四槽多真人落地面板永不弹)。
--
-- 原第二级 _single_local_role_id 一并删除,它是本判定的冗余快路径而非独立语义:
-- 它取 resolve_roles() 长度为 1 时那个 role_id 去比 owner,与遍历同一名册比
-- owner 在单席位下同解;多席位下只有遍历正确。边界亦无差异——名册非 table 时
-- 两者都不放行,空表时它返 nil 落到下一级、遍历零次返 false,同一出口。
--
-- 行为变更(#444 记):判定改为硬依赖 resolve_roles,名册未配置时恒 false。
-- 生产侧名册取自 GameAPI.get_all_valid_roles() 恒非空;测试侧须显式铺席位
-- (单字段 patch resolve_roles,勿用整表替换的 runtime_ports.configure)。
-- 名册遍历判定 owner 是否被服务(CRAP 门禁 #452):遍历与归一化比对收敛到
-- 独立小函数,owner_is_served_seat 只留前置短路与调用。
local function _roles_contain_owner(roles, owner_role_id)
  for _, role in ipairs(roles) do
    local role_id = role_id_utils.normalize(runtime_ui.resolve_role_id(role))
    if role_id ~= nil and role_id_utils.equals(role_id, owner_role_id) then
      return true
    end
  end
  return false
end

function choice_owner.owner_is_served_seat(owner_role_id)
  if owner_role_id == nil then
    return false
  end
  local roles = runtime_ports.resolve_roles()
  if type(roles) ~= "table" then
    return false
  end
  return _roles_contain_owner(roles, owner_role_id)
end

return choice_owner

