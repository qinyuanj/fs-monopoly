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

-- 每个遍历位置保留对象身份、归一 ID 和公开事实,包括无效/重复 ID。
-- 比较不分配签名表;只有当前 game 持有当前结果,不保留历史版本。
local function _matches(cache, players)
  if players == nil then
    return #cache.records == 0
  end
  local count = 0
  for index, player in ipairs(players) do
    local record = cache.records[index]
    if record == nil or record.player ~= player
      or record.id ~= identity.normalize(player and player.id or nil)
      or record.is_delegated ~= control.is_delegated(player)
      or record.is_computer_controlled ~= control.is_computer_controlled(player or nil) then
      return false
    end
    count = index
  end
  return count == #cache.records
end

local function _remember(cache, players)
  local count = 0
  for index, player in ipairs(players or {}) do
    local record = cache.records[index] or {}
    record.player = player
    record.id = identity.normalize(player and player.id or nil)
    record.is_delegated = control.is_delegated(player)
    record.is_computer_controlled = control.is_computer_controlled(player or nil)
    cache.records[index] = record
    count = index
  end
  for index = #cache.records, count + 1, -1 do
    cache.records[index] = nil
  end
end

function snapshot.install(game)
  if game == nil then
    return snapshot.build(nil)
  end
  local players = game.players
  local cache = game._player_control_snapshot_cache
  if cache ~= nil and game.player_control_snapshots == cache.result and _matches(cache, players) then
    return cache.result
  end
  local by_player = snapshot.build(game)
  cache = cache or { records = {} }
  _remember(cache, players)
  cache.result = by_player
  game._player_control_snapshot_cache = cache
  game.player_control_snapshots = by_player
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

