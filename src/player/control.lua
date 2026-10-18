-- 玩家控制深模块:补位电脑身份与控制模式两轴语义的唯一拥有者。
--
-- * 席位身份(补位电脑)继续由 player.is_ai 表示,本模块只提供查询;
-- * 控制模式以扁平字段 player.control_mode 保存,只允许本模块解释或修改;
-- * 派生查询 is_computer_controlled 统一回答「当前是否由电脑执行」,
--   消费者不得再拼装 is_ai / auto / ai 等旧字段或分支解释模式枚举。
--
-- 本模块不执行任何 UI、广播、分享面板或宿主副作用;入口代码按返回的
-- structured result 自行决定副作用。
local control = {}

local DIRECT = "direct"
local MANUAL_DELEGATION = "manual_delegation"
local AFK_DELEGATION = "afk_delegation"

local function _result(changed, enabled, source, reason)
  return {
    changed = changed == true,
    enabled = enabled == true,
    source = source,
    reason = reason,
  }
end

local function _mode(player)
  return player and player.control_mode or nil
end

function control.initialize(player)
  if player ~= nil then
    player.control_mode = DIRECT
  end
  return player
end

function control.is_replacement_computer(player)
  return player ~= nil and player.is_ai == true
end

function control.is_delegated(player)
  local mode = _mode(player)
  return mode == MANUAL_DELEGATION or mode == AFK_DELEGATION
end

-- ADR 0061 点名的领域窄查询；消费者无需解释 control_mode 枚举。
function control.is_afk_delegated(player)
  return _mode(player) == AFK_DELEGATION
end

function control.is_computer_controlled(player)
  return control.is_replacement_computer(player) or control.is_delegated(player)
end

-- 模式枚举校验单独成谓词(CRAP 门禁):_command_target 只留三级前置短路。
local function _is_known_mode(mode)
  return mode == DIRECT or mode == MANUAL_DELEGATION or mode == AFK_DELEGATION
end

local function _command_target(player)
  if player == nil then
    return nil, "missing_player", false
  end
  if control.is_replacement_computer(player) then
    return nil, "replacement_computer", control.is_delegated(player)
  end
  local mode = _mode(player)
  if not _is_known_mode(mode) then
    return nil, "invalid_control_mode", false
  end
  return mode, nil, nil
end

function control.toggle_manual_delegation(player)
  local mode, reason, enabled = _command_target(player)
  if mode == nil then
    return _result(false, enabled, nil, reason)
  end
  if mode == MANUAL_DELEGATION or mode == AFK_DELEGATION then
    player.control_mode = DIRECT
    return _result(true, false, "manual", nil)
  end

  player.control_mode = MANUAL_DELEGATION
  return _result(true, true, "manual", nil)
end

function control.enable_afk_delegation(player)
  local mode, reason, enabled = _command_target(player)
  if mode == nil then
    return _result(false, enabled, nil, reason)
  end
  if mode == AFK_DELEGATION then
    return _result(false, true, nil, "already_afk_delegated")
  end
  if mode == MANUAL_DELEGATION then
    return _result(false, true, nil, "already_manual_delegated")
  end

  player.control_mode = AFK_DELEGATION
  return _result(true, true, "afk", nil)
end

return control

--[[ mutate4lua-manifest
version=4
projectHash=8e9dc51f0831dcc1
scope.0.id=chunk:src/player/control.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=103
scope.0.semanticHash=d061616890491170
scope.1.id=function:_result
scope.1.kind=function
scope.1.startLine=16
scope.1.endLine=23
scope.1.semanticHash=d21181d486dd8ad6
scope.2.id=function:_mode
scope.2.kind=function
scope.2.startLine=25
scope.2.endLine=27
scope.2.semanticHash=616a2ca60599c94f
scope.3.id=function:control.initialize
scope.3.kind=function
scope.3.startLine=29
scope.3.endLine=34
scope.3.semanticHash=300b54f4a6c9387f
scope.4.id=function:control.is_replacement_computer
scope.4.kind=function
scope.4.startLine=36
scope.4.endLine=38
scope.4.semanticHash=be8994585243633b
scope.5.id=function:control.is_delegated
scope.5.kind=function
scope.5.startLine=40
scope.5.endLine=43
scope.5.semanticHash=c54a51b38aee42ac
scope.6.id=function:control.is_afk_delegated
scope.6.kind=function
scope.6.startLine=45
scope.6.endLine=47
scope.6.semanticHash=cbc50c0c0c0152e1
scope.7.id=function:control.is_computer_controlled
scope.7.kind=function
scope.7.startLine=49
scope.7.endLine=51
scope.7.semanticHash=2ee715b033a18468
scope.8.id=function:_is_known_mode
scope.8.kind=function
scope.8.startLine=54
scope.8.endLine=56
scope.8.semanticHash=db11c5df3657c06d
scope.9.id=function:_command_target
scope.9.kind=function
scope.9.startLine=58
scope.9.endLine=70
scope.9.semanticHash=10a84c2dfaee1ad6
scope.10.id=function:control.toggle_manual_delegation
scope.10.kind=function
scope.10.startLine=72
scope.10.endLine=84
scope.10.semanticHash=f378987291e7af0b
scope.11.id=function:control.enable_afk_delegation
scope.11.kind=function
scope.11.startLine=86
scope.11.endLine=100
scope.11.semanticHash=54fcb848600caaa5
]]
