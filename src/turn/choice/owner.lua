-- pending-choice owner/actor 解析唯一权威。
-- 收编原 waits/choice_dispatch.resolve_choice_owner_id、
-- policies/choice_auto._resolve_choice_owner、deadlines/choice_ports 的
-- actor 补全三份散落实现——同一「这个 choice 归谁」问题只在此有一份答案。
local choice_contract = require("src.config.choice.contract")

local owner = {}

local function _current_player_index(game)
  return game.turn and game.turn.current_player_index or nil
end

local function _player_at_index(game, current)
  return current and game.players and game.players[current] or nil
end

local function _player_id(player)
  return player and player.id or nil
end

-- owner 解析不到时的兜底：当前回合玩家的 id。
local function _current_turn_player_id(game)
  return _player_id(_player_at_index(game, _current_player_index(game)))
end

function owner.resolve_role_id(game, choice)
  local owner_role_id = choice_contract.resolve_owner_role_id(choice)
  if owner_role_id ~= nil and game.find_player_by_id then
    local player = game:find_player_by_id(owner_role_id)
    if player then
      return player.id
    end
  end
  return _current_turn_player_id(game)
end

local function _contract_player(game, owner_role_id)
  if owner_role_id ~= nil and game and game.find_player_by_id then
    return game:find_player_by_id(owner_role_id)
  end
  return nil
end

local function _current_player(game)
  if game and game.current_player then
    return game:current_player()
  end
  return nil
end

function owner.resolve_player(game, choice)
  local owner_role_id = choice_contract.resolve_owner_role_id(choice)
  local player = _contract_player(game, owner_role_id)
  if player then
    return player
  end
  return _current_player(game)
end

-- choice 显式 owner 引用在 players 里查无此人（断线重连/读档重建后悬空）。
-- 此时 resolve_role_id 的「兜底当前回合玩家」会制造一个注定被 actor 校验拦截的
-- 代答动作,每轮超时重复派发 → blocked warn 马灯刷屏。调用方必须先判此条件并
-- force_skip 清窗,而不是带着兜底 actor 去派发。find_player_by_id 缺席判 false:
-- 该宿主上 resolve_role_id 的兜底是合法语义,不算悬空。
function owner.has_dangling_owner(game, choice)
  local owner_role_id = choice_contract.resolve_owner_role_id(choice)
  if owner_role_id == nil or not (game and game.find_player_by_id) then
    return false
  end
  return _contract_player(game, owner_role_id) == nil
end

function owner.ensure_actor_role_id(game, choice, action)
  if not action or action.actor_role_id ~= nil then
    return action
  end
  local owner_id = owner.resolve_role_id(game, choice)
  if owner_id ~= nil then
    action.actor_role_id = owner_id
  end
  return action
end

return owner

