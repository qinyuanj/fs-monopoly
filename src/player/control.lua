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

