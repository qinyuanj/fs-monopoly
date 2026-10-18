local logger = require("src.foundation.log")
local role_id_utils = require("src.foundation.identity")

local role_context = {}

local warned_unmapped_role_ids = {}
local _cached_ctx = {}

local function _resolve_unmapped_role_context(role_id, current_player_id, ui_model)
  if role_id ~= nil and ui_model ~= nil and not warned_unmapped_role_ids[role_id] then
    warned_unmapped_role_ids[role_id] = true
    logger.warn(
      "role->player 映射失败，按观战回退:",
      "role_id=" .. tostring(role_id),
      "current_player_id=" .. tostring(current_player_id)
    )
  end
  _cached_ctx.role_id = role_id
  _cached_ctx.display_player_id = current_player_id
  _cached_ctx.can_operate = false
  _cached_ctx.is_player_role = false
  return _cached_ctx
end

local function _resolve_mapped_role_context(role_id, current_player_id)
  _cached_ctx.role_id = role_id
  _cached_ctx.display_player_id = role_id
  _cached_ctx.can_operate = role_id_utils.equals(role_id, current_player_id)
  _cached_ctx.is_player_role = true
  return _cached_ctx
end

local function _require_runtime(deps)
  local runtime = deps and deps.runtime or nil
  assert(runtime ~= nil and runtime.resolve_role_id ~= nil, "missing runtime.resolve_role_id")
  return runtime
end

local function _current_player_id(ui_model)
  return role_id_utils.normalize(ui_model and ui_model.current_player_id or nil)
end

local function _item_slots_by_player(ui_model)
  return ui_model and (ui_model.item_slots_by_player_id or ui_model.item_slots_by_player) or nil
end

local function _resolve_self_role_context(current_player_id)
  _cached_ctx.role_id = nil
  _cached_ctx.display_player_id = current_player_id
  _cached_ctx.can_operate = true
  _cached_ctx.is_player_role = true
  return _cached_ctx
end

function role_context.resolve(role, ui_model, deps)
  local runtime = _require_runtime(deps)
  local current_player_id = _current_player_id(ui_model)
  local role_id = role_id_utils.normalize(runtime.resolve_role_id(role))
  local mapped = role_id ~= nil and role_id_utils.read(_item_slots_by_player(ui_model), role_id) ~= nil

  if role_id == nil and role == nil then
    return _resolve_self_role_context(current_player_id)
  end

  if mapped then
    return _resolve_mapped_role_context(role_id, current_player_id)
  end

  return _resolve_unmapped_role_context(role_id, current_player_id, ui_model)
end

return role_context

