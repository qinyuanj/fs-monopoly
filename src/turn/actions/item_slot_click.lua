-- 道具槽点击的唯一裁定入口。
--
-- 契约：展示层只报事实（谁点了第几个槽），不做任何「在不在道具阶段」的猜测；
-- 本模块独占裁定并对每一条非放行路径发出反馈。早先的设计把裁定切成两半——
-- UI 猜一次阶段（猜错就自己发提示），turn 再猜一次（猜错就静默 reject）——
-- 两次猜测口径不一致时点击落进夹缝，两边都不提示，这是真机「点了没反应」的根因。
--
-- 槽位 → 道具的解析直接读行动者的真实背包：背包是固定槽位，
-- 空洞以 false 占位、不因其他卡的进出而移位；展示层 item_slice 按槽位索引直映射，
-- 两者索引恒等（含空洞——空槽点击落空槽静默口径）。因此裁定不依赖任何
-- UI 镜像（原先的 ui.item_slot_item_ids 是「当前回合玩家」口径，他人回合读它
-- 会索引到对手背包）。
--
-- 裁定结果三选一：
--   { status = "select", action = <choice_select> }  放行，转成 choice 选择
--   { status = "denied", reason = <拒因> }           已发提示
--   { status = "empty" }                             槽位无卡，静默（与空槽位口径一致）
local logger = require("src.foundation.log")
local role_id_utils = require("src.foundation.identity")
local inventory = require("src.rules.items.inventory")
local slot_utils = require("src.turn.actions.item_slot_utils")
local denial = require("src.turn.actions.item_slot_denial")

local M = {}

local function _resolve_actor(game, actor_role_id)
  if game == nil or type(game.find_player_by_id) ~= "function" then
    return nil
  end
  return game:find_player_by_id(actor_role_id)
end

local function _current_turn_player(game)
  if type(game) ~= "table" or type(game.turn) ~= "table" or type(game.players) ~= "table" then
    return nil
  end
  return game.players[game.turn.current_player_index]
end

local function _current_turn_role_id(game)
  local current = _current_turn_player(game)
  if current == nil then
    return nil
  end
  return role_id_utils.normalize(current.id)
end

local function _slot_item_id(actor, slot_index)
  local ok, items = pcall(inventory.items, actor)
  if not ok or type(items) ~= "table" then
    return nil
  end
  local item = items[slot_index]
  return item and item.id or nil
end

-- 归属点击者的活道具窗：turn 的 pending_choice 是全场共享的单个 choice，
-- 他人回合拿到的是对手的窗，必须比归属才算「我的阶段内」。
local function _turn_pending_choice(game)
  return game and game.turn and game.turn.pending_choice or nil
end

local function _passive_item_choice(choice)
  return type(choice) == "table" and choice.kind == "item_phase_passive"
end

local function _own_item_window(game, actor_role_id)
  local choice = _turn_pending_choice(game)
  if not _passive_item_choice(choice) then
    return nil
  end
  local owner_role_id = role_id_utils.normalize(choice.owner_role_id)
  if owner_role_id ~= nil and not role_id_utils.equals(owner_role_id, actor_role_id) then
    return nil
  end
  return choice
end

function M.resolve_slot_index(slot_index_or_id)
  return slot_utils.resolve_slot_index(slot_index_or_id)
end

-- 裁定前置：把「谁点的、点到哪张卡」解析出来。任一环缺位都返回 nil 让裁定落到
-- 静默（空槽位口径）——这些是展示数据缺失，不是用户可理解的拒绝原因。
local function _resolve_click_target(game, action)
  local slot_index = M.resolve_slot_index(action and action.slot_index)
  if slot_index == nil then
    logger.warn("item slot click without slot index:", tostring(action and action.slot_index))
    return nil
  end
  local actor_role_id = role_id_utils.normalize(action.actor_role_id)
  local actor = _resolve_actor(game, actor_role_id)
  if actor == nil then
    logger.warn("item slot click without a mapped actor:", tostring(action.actor_role_id))
    return nil
  end
  return { actor = actor, actor_role_id = actor_role_id, item_id = _slot_item_id(actor, slot_index) }
end

local function _select_action(choice, action, item_id)
  return {
    status = "select",
    action = {
      type = "choice_select",
      choice_id = choice.id,
      option_id = item_id,
      actor_role_id = action.actor_role_id,
      input_source = action.input_source,
    },
  }
end

-- 目标解析 + 当前回合裁定:直接有结果时返回 (result),放行时返回 (nil, target)。
local function _early_resolve_result(game, action)
  local target = _resolve_click_target(game, action)
  if target == nil or target.item_id == nil then
    return { status = "empty" }
  end
  if not role_id_utils.equals(target.actor_role_id, _current_turn_role_id(game)) then
    return denial.deny(game, target.actor_role_id, target.item_id, "not_current_turn")
  end
  return nil, target
end

-- 单一裁定。action 需带 actor_role_id 与 slot_index。
function M.resolve(game, action)
  local early, target = _early_resolve_result(game, action)
  if early ~= nil then
    return early
  end
  local actor_role_id, item_id = target.actor_role_id, target.item_id

  local choice = _own_item_window(game, actor_role_id)
  if choice == nil then
    return denial.deny(game, actor_role_id, item_id, "no_item_window")
  end

  if not denial.choice_offers_item(choice, item_id) then
    return denial.deny(game, actor_role_id, item_id, denial.unavailable_reason(game, target.actor, choice, item_id))
  end

  return _select_action(choice, action, item_id)
end

return M

