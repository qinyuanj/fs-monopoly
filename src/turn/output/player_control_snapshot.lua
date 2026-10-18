-- turn 输出侧的玩家控制快照:UI 不依赖玩家领域模块,只消费本模块物化的
-- 不可变布尔快照。字段至少包含 is_delegated 与 is_computer_controlled;
-- 每次 build 返回全新的 map 与条目,调用方不得改写快照内容。
local control = require("src.player.control")
local identity = require("src.foundation.identity")

local snapshot = {}

local function _freeze(value)
  return setmetatable({}, {
    __index = value,
    __newindex = function()
      error("player control snapshot is immutable", 2)
    end,
    __pairs = function()
      return pairs(value)
    end,
    __len = function()
      return #value
    end,
  })
end

local function _entry(player)
  return _freeze({
    is_delegated = control.is_delegated(player),
    is_computer_controlled = control.is_computer_controlled(player),
  })
end

-- 单条落表(CRAP 门禁):归一化与空 id 跳过收敛到本函数,build 只留遍历。
local function _write_entry(by_player, player)
  local player_id = identity.normalize(player and player.id or nil)
  if player_id == nil then
    return
  end
  identity.write(by_player, player_id, _entry(player))
end

function snapshot.build(game)
  local by_player = {}
  for _, player in ipairs(game and game.players or {}) do
    _write_entry(by_player, player)
  end
  return _freeze(by_player)
end

function snapshot.install(game)
  local by_player = snapshot.build(game)
  if game ~= nil then
    game.player_control_snapshots = by_player
  end
  return by_player
end

function snapshot.find(game, role_id)
  local by_player = game and game.player_control_snapshots or nil
  if by_player == nil then
    return nil
  end
  return identity.read(by_player, identity.normalize(role_id))
end

return snapshot

