local ui_nodes = require("src.ui.render.support.node_ops")
local role_id_utils = require("src.foundation.identity")
local runtime_assets = require("src.config.runtime_assets")
local item_options = require("src.ui.coord.item_slots_options")
local item_highlight = require("src.ui.coord.item_slots_highlight")

local M = {}

-- 无本地视角(单屏/headless 刷新,真机多客户端恒有 role_id):回退比 choice
-- 归属或行动者,保持既有单屏行为。
local function _fallback_owner_id(ui_model)
  return role_id_utils.normalize(ui_model and (ui_model.item_choice_owner_id or ui_model.current_player_id))
end

-- 全时段可点口径(#162 二次复验):touch 开关只看「显示的是本地玩家自己的卡且
-- allow_interact」。门比本地视角(opts.role_id),不比行动者(current_player_id)——
-- 他人回合行动者是对手,本地玩家的持卡槽仍须可点(点击由 route 层投提示)。
-- 空槽位在 _sync_one_slot 里维持 touch 关。
local function _allow_slot_click(opts, local_role_id, ui_model, display_player_id)
  if opts.allow_interact == false or display_player_id == nil then
    return false
  end
  if local_role_id ~= nil then
    return role_id_utils.equals(display_player_id, local_role_id)
  end
  return role_id_utils.equals(_fallback_owner_id(ui_model), display_player_id)
end

local _empty_items_fallback = {}

local function _resolve_item_slot_items(ui_model, display_player_id)
  local by_player = ui_model.item_slots_by_player_id or ui_model.item_slots_by_player or _empty_items_fallback
  return role_id_utils.read(by_player, display_player_id) or ui_model.item_slots or _empty_items_fallback
end

local _cached_ctx = {}

local function _choice_from_model(ui_model)
  if ui_model == nil then
    return nil
  end
  return ui_model.choice
end

local function _display_player_id(ui_model, opts)
  return role_id_utils.normalize(opts.display_player_id or ui_model.current_player_id)
end

local function _fill_refresh_context(ui, state, ui_model, opts, choice, display_player_id, asset_refs)
  local role_id = role_id_utils.normalize(opts.role_id)
  _cached_ctx.ui = ui
  _cached_ctx.slots = ui.item_slots
  _cached_ctx.role_id = role_id
  _cached_ctx.display_player_id = display_player_id
  _cached_ctx.items = _resolve_item_slot_items(ui_model, display_player_id)
  _cached_ctx.choice = choice
  _cached_ctx.allow_slot_click = _allow_slot_click(opts, role_id, ui_model, display_player_id)
  -- 高亮归属门:可选集来自全局 pending choice,他人回合时它属于行动方;
  -- 不比对归属会把对手的可选 id 套到本地同名卡上误抬(他人回合本地
  -- 请神卡/送神卡假高亮)。touch 门不受此限——持卡槽仍须可点弹拒因。
  _cached_ctx.choice_owned_by_display = role_id_utils.equals(_fallback_owner_id(ui_model), display_player_id)
  _cached_ctx.option_id_set = item_options.build(choice)
  local empty_image = runtime_assets.empty_image(asset_refs)
  _cached_ctx.asset_refs = asset_refs
  _cached_ctx.empty_key = empty_image.image_key
  return _cached_ctx
end

local function _build_refresh_context(state, ui_model, opts)
  local ui = state.ui
  assert(ui ~= nil and ui.item_slots ~= nil, "missing ui item slots")
  opts = opts or {}
  local choice = _choice_from_model(ui_model)
  local asset_refs = runtime_assets.asset_context(state)
  return _fill_refresh_context(ui, state, ui_model, opts, choice, _display_player_id(ui_model, opts), asset_refs)
end

local _slot_pickable = {}

-- 单槽图与高亮判定(CRAP 门禁):图 key 解析与高亮谓词各自成函数,
-- _sync_one_slot 只留有物/空槽两分支的落值。
local function _slot_image_key(ctx, item_id)
  local image = runtime_assets.image_for_item(item_id, ctx.asset_refs)
  return image.ok == true and image.image_key or ctx.empty_key
end

-- 不可用槽位也可点（点了由 turn 层裁定并弹原因提示）；高亮仍只按可选道具。
local function _is_highlightable(ctx, item_id)
  return ctx.allow_slot_click and ctx.choice_owned_by_display
    and ctx.option_id_set[tostring(item_id)] == true
end

local function _sync_one_slot(ctx, slot_name, item_id, index, slot_pickable)
  if item_id then
    ui_nodes.set_item_slot_image(slot_name, _slot_image_key(ctx, item_id))
    ctx.ui:set_touch_enabled(slot_name, ctx.allow_slot_click == true)
    slot_pickable[index] = _is_highlightable(ctx, item_id)
  else
    ui_nodes.set_item_slot_image(slot_name, ctx.empty_key)
    ctx.ui:set_touch_enabled(slot_name, false)
    slot_pickable[index] = false
  end
end

local function _sync_slot_images(ctx)
  -- pairs 清除:原 `for i = 1, #_slot_pickable` 的下界 1→0 变异逐值等价
  -- (槽位下标恒 ≥1,多清 [0] 无人观测)不可杀;pairs 无数字位点(#262 化简)。
  for key in pairs(_slot_pickable) do _slot_pickable[key] = nil end
  local slot_pickable = _slot_pickable
  for index, slot_name in ipairs(ctx.slots) do
    _sync_one_slot(ctx, slot_name, ctx.items[index], index, slot_pickable)
  end
  return slot_pickable
end

function M.refresh_item_slots(state, ui_model, opts)
  local ctx = _build_refresh_context(state, ui_model, opts)
  local slot_pickable = _sync_slot_images(ctx)
  -- #362 D3:hook 锚定可选槽集合签名,须先算出 slot_pickable 再喂入。
  item_highlight.maybe_emit_phase_advance_reset(state, slot_pickable)
  item_highlight.refresh_highlight_state(state, ctx, slot_pickable)
end

return M

