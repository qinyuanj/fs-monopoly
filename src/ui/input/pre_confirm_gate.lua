-- 预确认门控:授权判定与免预确认屏规则。
-- 原 ui/input/pre_confirm.lua 的判定段;pre_confirm.lua 保留会话流程与公共面。
local choice_contract = require("src.config.choice.contract")
local role_id_utils = require("src.foundation.identity")
local runtime_state = require("src.ui.state.runtime")
local modal_state = require("src.ui.state.modal")

local M = {}

local function _resolve_choice_owner_role_id(state, choice)
  local owner_role_id = choice_contract.resolve_owner_or_meta_role_id(choice)
  if owner_role_id ~= nil then
    return owner_role_id
  end
  local current_model = runtime_state.get_ui_model(state)
  return role_id_utils.normalize(current_model and current_model.current_player_id or nil)
end

-- 授权只认事件载荷里的真实点击者(ADR 0054,#443):「上一次点击者缓存」已随
-- #601 整体退役,更不得当作身份来源。choice_select 经 event_actor_policy attach
-- 后才到这里,actor_role_id 保证非 nil;nil 兜底拒绝开屏。
function M.can_actor_open(state, intent, choice)
  local owner_role_id = _resolve_choice_owner_role_id(state, choice)
  local actor_role_id = role_id_utils.normalize(intent and intent.actor_role_id or nil)
  if owner_role_id == nil or actor_role_id == nil then
    return false
  end
  return role_id_utils.equals(actor_role_id, owner_role_id)
end

-- 免预确认的屏幕:未指明来源屏或已自带确认形态的屏。
local function _exempt_screen(screen_key)
  return screen_key == nil or screen_key == "secondary_confirm" or screen_key == "market" or screen_key == "target"
end

local function _requires_choice_select_pre_confirm(choice, screen_key)
  if _exempt_screen(screen_key) then
    return false
  end
  if choice and choice.pre_confirm_on_select == false then
    return false
  end
  return true
end

function M.needs_pre_confirm(state, intent)
  local intent_type = intent.type
  local ui = state.ui
  local current_model = runtime_state.get_ui_model(state)
  local choice = current_model and current_model.choice or nil
  if not ui then
    return false
  end

  if intent_type == "choice_select" then
    local screen_key = modal_state.get_active_choice_screen_key(state)
    return _requires_choice_select_pre_confirm(choice, screen_key)
  end

  return false
end

return M

