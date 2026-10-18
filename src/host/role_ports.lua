-- 角色解析与标记默认实现(自 default_ports.lua 拆分,行为保持):角色枚举、
-- 合成角色适配器回退、单角色解析、失败标记与出局的宿主侧执行。
local logger = require("src.foundation.log")
local role_die = require("src.host.role_die")

local role_ports = {}

local function _current_env(runtime_context)
  local ctx = runtime_context.current and runtime_context.current() or nil
  return ctx and ctx.env or nil
end

local function _current_game_api(runtime_context)
  local env = _current_env(runtime_context)
  return env and env["Game" .. "API"] or nil
end

local function _try_get_role_id(role)
  if role == nil then
    return nil
  end
  if type(role.get_roleid) == "function" then
    local ok, role_id = pcall(role.get_roleid)
    if ok then
      return role_id
    end
  end
  return role.id
end

local function _query_game_roles(runtime_context)
  local game_api = _current_game_api(runtime_context)
  if game_api and type(game_api.get_all_valid_roles) == "function" then
    local ok, roles = pcall(game_api.get_all_valid_roles)
    if ok and type(roles) == "table" then
      return roles
    end
  end
  return {}
end

local function _registry(ctx)
  return ctx and ctx.synthetic_actor_registry or nil
end

-- 注册表能力探测:runtime context 里的合成角色注册表在部分装配/测试桩下只实现
-- 部分方法,取用前逐个探测,缺失即按「无合成角色」降级。
local function _registry_supports(registry, method_name)
  return registry ~= nil and type(registry[method_name]) == "function"
end

local function _adapter_of(actor)
  if actor and actor.adapter then
    return actor.adapter
  end
  return nil
end

local function _try_resolve_synthetic_role(player_id, ctx)
  local synthetic_registry = _registry(ctx)
  if not _registry_supports(synthetic_registry, "resolve_actor") then
    return nil
  end
  return _adapter_of(synthetic_registry.resolve_actor(player_id))
end

local function _find_role_by_id(roles, player_id)
  if type(roles) ~= "table" then
    return nil
  end
  for _, role in ipairs(roles) do
    if _try_get_role_id(role) == player_id then
      return role
    end
  end
  return nil
end

local function _resolve_role_via_game_api(player_id, runtime_context)
  local game_api = _current_game_api(runtime_context)
  if not (game_api and type(game_api.get_role) == "function") then
    return nil
  end
  local ok, role = pcall(game_api.get_role, player_id)
  if ok then
    return role
  end
  return nil
end

local function _resolve_roles(runtime_context)
  local ctx = runtime_context.current()
  if ctx and type(ctx.roles) == "table" then
    if #ctx.roles > 0 then
      return ctx.roles
    end
    local refreshed = _query_game_roles(runtime_context)
    if #refreshed > 0 then
      ctx.roles = refreshed
      return refreshed
    end
    return ctx.roles
  end
  return _query_game_roles(runtime_context)
end

local function _resolve_role(player_id, runtime_context)
  if player_id == nil then
    return nil
  end
  local ctx = runtime_context.current()
  local synthetic_adapter = _try_resolve_synthetic_role(player_id, ctx)
  if synthetic_adapter then
    return synthetic_adapter
  end
  local role = _find_role_by_id(_resolve_roles(runtime_context), player_id)
  if role ~= nil then
    return role
  end
  return _resolve_role_via_game_api(player_id, runtime_context)
end

function role_ports.install(defaults, runtime_context)
  defaults.resolve_roles = function()
    return _resolve_roles(runtime_context)
  end

  defaults.resolve_role = function(player_id)
    return _resolve_role(player_id, runtime_context)
  end

  -- 名字即「标记失败」:破产淘汰的标记语义正确,保留 role.lose() 不换方法
  -- (#334);跳过分支必留痕(ADR 0046),禁止静默。
  defaults.mark_role_lose = function(role)
    if role == nil then
      logger.warn("mark_role_lose skip: role is nil")
      return
    end
    if type(role.lose) ~= "function" then
      logger.warn("mark_role_lose skip: role lacks lose method")
      return
    end
    role.lose()
  end

  -- 合成 AI 身份查询(#611):合成角色注册表是唯一真源,退役后仍答真;
  -- 注册表缺位(未装配/非合成局)一律 false,不猜负 player_id 之类的约定。
  defaults.is_synthetic_player = function(player_id)
    local registry = _registry(runtime_context.current())
    if not _registry_supports(registry, "is_synthetic_player") then
      return false
    end
    return registry.is_synthetic_player(player_id) == true
  end

  -- 出局的宿主侧执行(ADR 0046):宿主 Role 走控制单位、合成适配器走自带 die,
  -- 分支与判据收在 src/host/role_die,规则层只经端口触达。
  defaults.call_role_die = role_die.call_role_die
end

return role_ports

