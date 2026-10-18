local logger = require("src.foundation.log")
local runtime_constants = require("src.config.gameplay.runtime_constants")
local role_id_utils = require("src.foundation.identity")
local host_types = require("src.foundation.host_types")

local synthetic_actor_registry = {}

local function _zero_pos()
  return host_types.vec3(0.0, 0.0, 0.0)
end

local function _resolve_start_tile_id(map_cfg)
  local path = map_cfg and map_cfg.path or nil
  if type(path) ~= "table" then
    return nil
  end
  return path[1]
end

local function _query_start_tile_unit(lua_api, start_tile_id)
  if not (lua_api and type(lua_api.query_unit) == "function" and start_tile_id ~= nil) then
    return nil
  end
  local ok_unit, tile_unit = pcall(lua_api.query_unit, "t" .. tostring(start_tile_id))
  if ok_unit then
    return tile_unit
  end
  return nil
end

local function _query_tile_position(tile_unit)
  if not (tile_unit and type(tile_unit.get_position) == "function") then
    return nil
  end
  local ok_pos, pos = pcall(tile_unit.get_position)
  if ok_pos then
    return pos
  end
  return nil
end

local function _safe_query_start_pos(env, map_cfg)
  local lua_api = env and env.LuaAPI or nil
  local start_tile_id = _resolve_start_tile_id(map_cfg)
  local tile_unit = _query_start_tile_unit(lua_api, start_tile_id)
  local pos = _query_tile_position(tile_unit)
  if pos == nil then
    return _zero_pos()
  end
  return pos
end

local function _resolve_destroy_unit(game_api)
  if game_api and type(game_api.destroy_unit) == "function" then
    return game_api.destroy_unit
  end
  return nil
end

local function _game_api_of(env)
  return env and env.GameAPI or nil
end

local function _actor_unit(actor)
  return actor and actor.unit or nil
end

local function _destroy_actor(env, actor)
  local destroy_unit = _resolve_destroy_unit(_game_api_of(env))
  local unit = _actor_unit(actor)
  if destroy_unit == nil or unit == nil then
    return
  end
  pcall(destroy_unit, unit)
end

-- 退役幂等(#610 遗留收口):已退役再调 die/lose 视为「出局态成立」返回 true,与宿主
-- 单位路径的「已死幂等算成功」对齐;否则 role_die 会把 lose 之后的 die 误判为失败留痕。
-- 单位只销毁一次由 destroyed 标志把门。
local function _retire_actor(registry, actor)
  if actor == nil then
    return false
  end
  if actor.destroyed == true then
    return true
  end
  actor.destroyed = true
  _destroy_actor(registry.env, actor)
  role_id_utils.write(registry.actors_by_player_id, actor.player_id, nil)
  return true
end

local function _build_adapter(registry, actor)
  return {
    id = actor.player_id,
    is_synthetic_actor = true,
    get_roleid = function()
      return actor.player_id
    end,
    get_name = function()
      return actor.name
    end,
    get_ctrl_unit = function()
      return actor.unit
    end,
    get_head_icon = function()
      return actor.avatar_image_key
    end,
    send_ui_custom_event = function()
      return false
    end,
    die = function()
      return _retire_actor(registry, actor)
    end,
    lose = function()
      return _retire_actor(registry, actor)
    end,
    game_win_and_show_result_panel = function()
      return false
    end,
  }
end

local function _spec_field(spec, key)
  return spec and spec[key] or nil
end

local function _normalize_pending_spec(spec)
  return {
    player_id = role_id_utils.normalize(spec and spec.player_id),
    name = _spec_field(spec, "name"),
    unit_key = _spec_field(spec, "unit_key"),
    avatar_image_key = _spec_field(spec, "avatar_image_key"),
  }
end

local function _validate_spawn_preconditions(registry, spec)
  local game_api = registry.env and registry.env.GameAPI or nil
  local player_id = role_id_utils.normalize(spec.player_id)
  assert(player_id ~= nil, "missing synthetic player_id")
  assert(spec.unit_key ~= nil, "missing synthetic unit_key")
  assert(game_api and type(game_api.create_creature_fixed_scale) == "function",
    "missing GameAPI.create_creature_fixed_scale")
  return game_api, player_id
end

local function _spawn_unit(game_api, spec, spawn_pos, player_id)
  local ok_spawn, unit = pcall(
    game_api.create_creature_fixed_scale,
    spec.unit_key,
    spawn_pos,
    runtime_constants.q_left,
    1.0,
    nil
  )
  assert(ok_spawn and unit ~= nil, "failed to spawn synthetic actor: " .. tostring(player_id))
  return unit
end

local function _start_actor_ai(unit, player_id, unit_key)
  if type(unit.start_ai) == "function" then
    local ok_start, err = pcall(unit.start_ai)
    if not ok_start then
      logger.warn("[Eggy]", "synthetic actor start_ai failed", tostring(player_id), tostring(err))
    end
    return
  end
  logger.warn("[Eggy]", "synthetic actor missing start_ai", tostring(player_id), tostring(unit_key))
end

local function _spawn_actor(registry, spec, spawn_pos)
  local game_api, player_id = _validate_spawn_preconditions(registry, spec)
  local unit = _spawn_unit(game_api, spec, spawn_pos, player_id)
  local actor = {
    player_id = player_id,
    name = spec.name or ("AI" .. tostring(player_id)),
    unit = unit,
    unit_key = spec.unit_key,
    avatar_image_key = spec.avatar_image_key,
  }
  actor.adapter = _build_adapter(registry, actor)
  role_id_utils.write(registry.actors_by_player_id, player_id, actor)
  _start_actor_ai(unit, player_id, spec.unit_key)
end

function synthetic_actor_registry.new(env)
  local registry = {
    env = env or {},
    pending_specs = {},
    actors_by_player_id = {},
    -- 合成 AI 身份集合(#611):开局登记后只由 reset 清空,不随退役擦除。
    -- actors_by_player_id 在 die/lose 退役时删表项,因此不能兼任身份真源。
    synthetic_player_ids = {},
  }

  function registry.reset()
    for _, actor in pairs(registry.actors_by_player_id) do
      if actor.destroyed ~= true then
        actor.destroyed = true
        _destroy_actor(registry.env, actor)
      end
    end
    registry.pending_specs = {}
    registry.actors_by_player_id = {}
    registry.synthetic_player_ids = {}
  end

  function registry.register_specs(specs)
    registry.reset()
    if type(specs) ~= "table" then
      return
    end
    for _, spec in ipairs(specs) do
      local normalized = _normalize_pending_spec(spec)
      registry.pending_specs[#registry.pending_specs + 1] = normalized
      role_id_utils.write(registry.synthetic_player_ids, normalized.player_id, true)
    end
  end

  function registry.resolve_actor(player_id)
    return role_id_utils.read(registry.actors_by_player_id, player_id)
  end

  -- 「该 player 是合成 AI 吗」的唯一真源:据开局登记的 spec 回答,对已退役
  -- (resolve_actor 已返回 nil)的合成 AI 同样为真(#611)。
  function registry.is_synthetic_player(player_id)
    return role_id_utils.read(registry.synthetic_player_ids, player_id) == true
  end

  local function _registry_game_api(reg)
    return reg.env and reg.env.GameAPI or nil
  end

  local function _assert_spawn_api(game_api)
    assert(game_api and type(game_api.create_creature_fixed_scale) == "function",
      "missing GameAPI.create_creature_fixed_scale")
  end

  function registry.spawn_pending(map_cfg)
    if #registry.pending_specs == 0 then
      return
    end
    local game_api = _registry_game_api(registry)
    _assert_spawn_api(game_api)
    local spawn_pos = _safe_query_start_pos(registry.env, map_cfg)
    for _, spec in ipairs(registry.pending_specs) do
      _spawn_actor(registry, spec, spawn_pos)
    end
  end

  return registry
end

return synthetic_actor_registry

