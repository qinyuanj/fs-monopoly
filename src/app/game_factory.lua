local board = require("src.rules.board")
local tile = require("src.rules.board.tile")
local player = require("src.player.actions.player")
local control = require("src.player.control")
local balance_ops = require("src.player.actions.balance")
local inventory = require("src.player.actions.inventory")
local constants = require("src.config.content.constants")
local roles_cfg = require("src.config.content.roles")
local runtime_ports = require("src.foundation.ports.runtime_ports")

local game_factory = {}

local function _new_rng(random_fn)
  random_fn = random_fn or GameAPI.random_int
  local rng = {}
  function rng:next_int(min, max)
    return random_fn(min, max)
  end
  return rng
end

local function _create_board(opts)
  assert(opts ~= nil, "missing board opts")
  local tiles = assert(opts.tiles, "missing tiles config")
  local map_cfg = assert(opts.map, "missing map config")

  local tile_lookup = {}
  for _, cfg in ipairs(tiles) do
    tile_lookup[cfg.id] = tile:new(cfg)
  end

  local path = {}
  for _, id in ipairs(map_cfg.path) do
    table.insert(path, tile_lookup[id])
  end

  return board:new({
    path = path,
    tile_lookup = tile_lookup,
    branches = map_cfg.branches,
    map = map_cfg,
    overlays = { roadblocks = {}, mines = {} },
  })
end

local function _resolve_coin_role(entry, player_id)
  if entry and entry.role ~= nil then
    return entry.role
  end
  local runtime_role = runtime_ports.resolve_role(player_id)
  if runtime_role ~= nil then
    return runtime_role
  end
  return balance_ops.new_memory_coin_role()
end

local function _new_player_entry(id, name, role_id, is_ai, is_auto, coin_role)
  local created = player:new({
    id = id,
    name = name,
    role_id = role_id,
    is_ai = is_ai,
    start_index = 1,
    constants = constants,
    coin_role = coin_role,
    deity_duration_turns = constants.deity_duration_turns,
    inventory = inventory:new({ constants = constants }),
  })
  -- 全员自动调试/测试档案映射为明确的手动托管命令；补位电脑命令无副作用。
  if is_auto then
    control.toggle_manual_delegation(created)
  end
  balance_ops.seed_player_coins(created, constants.starting_cash)
  return created
end

local function _resolve_roster_name(entry, index)
  local name = entry and entry.name or nil
  if not name or name == "" then
    return "玩家" .. tostring(index)
  end
  return name
end

local function _resolve_auto_flag(opts, auto_players, role_id)
  return opts.auto_all or (auto_players and auto_players[role_id]) or false
end

local function _create_players_from_roster(opts, role_roster, ai_map)
  local players = {}
  local auto_players = opts.auto_players
  for i, entry in ipairs(role_roster) do
    local role_id = entry and (entry.role_id or entry.id) or nil
    assert(role_id ~= nil, "missing role_id in role_roster: " .. tostring(i))
    local name = _resolve_roster_name(entry, i)
    local is_ai = ai_map[role_id]
    local is_auto = _resolve_auto_flag(opts, auto_players, role_id)
    table.insert(players, _new_player_entry(role_id, name, role_id, is_ai, is_auto, _resolve_coin_role(entry, role_id)))
  end
  return players
end

local function _create_players_from_names(opts, ai_map)
  local players = {}
  local names = assert(opts.players, "missing player names")
  if #names == 1 then
    names = { names[1], "玩家2", "玩家3", "玩家4" }
  end
  for i, name in ipairs(names) do
    local role = roles_cfg[((i - 1) % #roles_cfg) + 1]
    local is_ai = ai_map[i]
    table.insert(players, _new_player_entry(i, name, role.id, is_ai, opts.auto_all, _resolve_coin_role(nil, i)))
  end
  return players
end

local function _create_players(opts)
  local ai_map = opts.ai or {}
  local role_roster = opts.role_roster
  if type(role_roster) == "table" and #role_roster > 0 then
    return _create_players_from_roster(opts, role_roster, ai_map)
  end
  return _create_players_from_names(opts, ai_map)
end

function game_factory.build_rng(random_fn)
  return _new_rng(random_fn)
end

function game_factory.build_board(opts)
  return _create_board(opts)
end

function game_factory.build_players(opts)
  return _create_players(opts)
end

return game_factory

