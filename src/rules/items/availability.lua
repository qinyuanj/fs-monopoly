local effects = require("src.rules.items.post_effects")
local item_ids = require("src.config.gameplay.item_ids")
local inventory = require("src.rules.items.inventory")
local availability_special = require("src.rules.items.availability_special")
local offer_window = require("src.rules.items.offer_window")
local number_utils = require("src.foundation.number")
local tables = require("src.foundation.tables")

local availability = {}

local followup_choice_item_set = {
  [item_ids.remote_dice] = true,
  [item_ids.roadblock] = true,
  [item_ids.monster] = true,
  -- missile 不在此列:effects.target_item_ids() 已含导弹,下方循环会补进集合。
}

for _, target_item_id in ipairs(effects.target_item_ids()) do
  followup_choice_item_set[target_item_id] = true
end

local function normalize_integer_field(target, key, choice_kind, field_prefix, required)
  local value = target[key]
  if value == nil then
    if required then
      assert(false, tostring(choice_kind) .. " requires numeric " .. tostring(field_prefix or "meta") .. "." .. tostring(key))
    end
    return nil
  end
  target[key] = assert(
    number_utils.to_integer(value),
    tostring(choice_kind) .. " requires numeric " .. tostring(field_prefix or "meta") .. "." .. tostring(key)
  )
  return target[key]
end

availability.copy_table = tables.copy_table
availability.normalize_integer_field = normalize_integer_field

-- 行为测试公共接缝：test_item_availability_matrix 通过阶段窗口判定覆盖道具开放时机。
-- 生产 can_offer_in_phase 与这些入口共用 offer_window 的判定。
availability.resolve_offer_in_phases = offer_window.resolve_offer_in_phases
availability.trigger_timing_allowed = offer_window.trigger_timing_allowed

local function _used_effect_groups(game)
  return game and game.turn and game.turn.used_effect_groups or nil
end

local function _effect_group_used(game, cfg)
  local used_effect_groups = _used_effect_groups(game)
  return type(used_effect_groups) == "table" and cfg.effect_group ~= nil
    and used_effect_groups[cfg.effect_group] == true
end

-- 拒绝分类顺序(#205):租金上下文(无目标/现金不足独立原因)→ 阶段窗口 →
-- 特殊条件 → 同组已用;特殊条件谓词在 availability_special。
local function _denial_reason(game, player, item_id, cfg, phase)
  local rent_denial = availability_special.rent_denial_reason(game, player, item_id)
  if rent_denial then
    return rent_denial
  end
  if not offer_window.allowed(item_id, cfg, phase, false) then
    return "offer_in_phases_not_allowed"
  end
  local special_denial = availability_special.condition_denial_reason(game, player, item_id)
  if special_denial then
    return special_denial
  end
  if _effect_group_used(game, cfg) then
    return "effect_group_used"
  end
  return nil
end

function availability.can_offer_in_phase(game, player, item_id, phase)
  local cfg = inventory.cfg(item_id)
  if not cfg then
    return false, "missing_item_cfg"
  end
  local denial = _denial_reason(game, player, item_id, cfg, phase)
  if denial then
    return false, denial
  end
  return true, "ok"
end

local function _cfg_effect_group(item_id)
  local cfg = inventory.cfg(item_id)
  if type(cfg) == "table" and cfg.effect_group ~= nil then
    return cfg.effect_group
  end
  return nil
end

function availability.mark_effect_group_used(game, item_id)
  local effect_group = _cfg_effect_group(item_id)
  if effect_group == nil then
    return
  end
  local used_effect_groups = _used_effect_groups(game)
  if type(used_effect_groups) ~= "table" then
    return
  end
  used_effect_groups[effect_group] = true
end

availability.can_auto_consider_item = offer_window.can_auto_consider_item

function availability.requires_followup_choice(item_id)
  return followup_choice_item_set[item_id] == true
end

-- 行为测试公共接缝：test_item_availability_matrix / rent_response 通过报价结果
-- 验证各阶段、免租/强征条件与后续选择需求，不重算私有拒绝规则。
function availability.analyze_offer(game, player, item_id, phase)
  local can_offer, deny_reason = availability.can_offer_in_phase(game, player, item_id, phase)
  local requires_followup_choice = availability.requires_followup_choice(item_id)
  return {
    can_offer = can_offer == true,
    can_execute_now = can_offer == true and not requires_followup_choice,
    requires_followup_choice = requires_followup_choice,
    deny_reason = can_offer and nil or deny_reason,
  }
end

return availability

--[[ mutate4lua-manifest
version=4
projectHash=969b5ab02ae94a7f
scope.0.id=chunk:src/rules/items/availability.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=125
scope.0.semanticHash=f786276d385db167
scope.1.id=function:normalize_integer_field
scope.1.kind=function
scope.1.startLine=22
scope.1.endLine=35
scope.1.semanticHash=f99046345f9dccad
scope.2.id=function:_used_effect_groups
scope.2.kind=function
scope.2.startLine=45
scope.2.endLine=47
scope.2.semanticHash=c250138038aa193a
scope.3.id=function:_effect_group_used
scope.3.kind=function
scope.3.startLine=49
scope.3.endLine=53
scope.3.semanticHash=63b53808779e861f
scope.4.id=function:_denial_reason
scope.4.kind=function
scope.4.startLine=57
scope.4.endLine=73
scope.4.semanticHash=cc27e553d694118c
scope.5.id=function:availability.can_offer_in_phase
scope.5.kind=function
scope.5.startLine=75
scope.5.endLine=85
scope.5.semanticHash=c5be56d63f7aa6f1
scope.6.id=function:_cfg_effect_group
scope.6.kind=function
scope.6.startLine=87
scope.6.endLine=93
scope.6.semanticHash=591f1d0ee19076d0
scope.7.id=function:availability.mark_effect_group_used
scope.7.kind=function
scope.7.startLine=95
scope.7.endLine=105
scope.7.semanticHash=33762ff6a66ab7fe
scope.8.id=function:availability.requires_followup_choice
scope.8.kind=function
scope.8.startLine=109
scope.8.endLine=111
scope.8.semanticHash=92047a25c743520b
scope.9.id=function:availability.analyze_offer
scope.9.kind=function
scope.9.startLine=113
scope.9.endLine=122
scope.9.semanticHash=2cc56b4a6af9043a
]]
