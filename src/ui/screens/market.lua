-- market（商店）屏:点击意图 + 开/关/选面板,单一归宿(工单 #118 Phase C)。
--
-- 这是 canvas 面,不是选择屏:没有 descriptor / open / canvas 三契约(详见
-- screens_registry 的说明)。market 走自己的开屏路径 —— choice_openers.open_choice_modal
-- 对它直接 return false,不经选择屏的 open_screen,由 coord/modal 直呼本模块的
-- open/close。
--
-- items 与 controls 此前是 canvas_builders 里相邻的两个 builder,合并进一份
-- build_route_specs 时必须保持「先 items 后 controls」—— 发射序即点击回调的注册序。
local nodes = require("src.ui.schema.market")
local ui_event_intents = require("src.ui.input.event_intents")
local route_model = require("src.ui.input.route_model")
local runtime_state = require("src.ui.state.runtime")
local market_view = require("src.ui.render.market")
local canvas = require("src.ui.coord.canvas_coordinator")
local with_client_role = require("src.ui.render.support.with_client_role")
local runtime = require("src.ui.render.support.runtime_ui")
local role_context = require("src.ui.view.role_context")
local panel_interrupt = require("src.ui.state.panel_interrupt")
local item_slice = require("src.ui.view.item_slice")
local role_id_utils = require("src.foundation.identity")
local tip_queue = require("src.foundation.tips")

local M = { key = "market" }

local MARKET_SLOTS_FULL_TIP = "道具槽已满，无法购买"
local MARKET_SLOTS_FULL_TIP_SECONDS = 3.0

-- #178 点背景关闭暂时停用(2026-10-29,金豆单次限购改 1 后连续购买易误触关屏)。
-- 背景仍注册路由且保持触摸,只吞点击、不产出意图,避免点击穿透到下方棋盘;
-- 恢复时改回 true 即可。
M.BACKGROUND_CLICK_CLOSE_ENABLED = false

-- 槽满点击拦截(UI 本地闸):购买按钮在 build_intent 处打回 —— tip 告知 + 不生出
-- market_confirm intent,引擎往返整段跳过。槽位按 choice owner 取(视角玩家可能
-- 只是观战);模型缺槽位数据时放行,由引擎侧 purchase_fulfillment 的
-- inventory_full 校验兜底(覆盖 AI/auto 与刷新延迟穿透)。
local function _buyer_slots(state)
  local model = runtime_state.get_ui_model(state)
  if model == nil then
    return nil
  end
  local owner_id = model.item_choice_owner_id
  if owner_id ~= nil and type(model.item_slots_by_player) == "table" then
    local owner_slots = role_id_utils.read(model.item_slots_by_player, owner_id)
    if owner_slots ~= nil then
      return owner_slots
    end
  end
  return model.item_slots
end

local function _buyer_inventory_full(state)
  local slots = _buyer_slots(state)
  if type(slots) ~= "table" then
    return false
  end
  local slot_count = item_slice.resolve_slot_count(state.ui)
  if slot_count <= 0 then
    return false
  end
  for i = 1, slot_count do
    if slots[i] == nil then
      return false
    end
  end
  return true
end

local function _reject_buy_slots_full()
  tip_queue.enqueue({
    text = MARKET_SLOTS_FULL_TIP,
    duration = MARKET_SLOTS_FULL_TIP_SECONDS,
    dedupe_key = "market_buy_block_slots_full",
    blocks_inter_turn = false,
    source = "ui.market_slots_full",
  })
end

-- items 与 controls 保持两个具名 builder,而不是合成一坨:这个二分是真实的(items 由
-- nodes.item_buttons 数据驱动,controls 是固定集),且 canvas_route_market_baseline_spec
-- 正是分别钉住两者的产物。build_route_specs 只负责按序合成。
function M.build_items(state)
  local specs = {}
  for index, name in ipairs(nodes.item_buttons or {}) do
    specs[#specs + 1] = {
      name = name,
      build_intent = function()
        local market = route_model.market(state)
        if not market then return nil end
        local option_id = ui_event_intents.resolve_option_id(market, { index = index }, state)
        if not option_id then
          return nil
        end
        return { type = "market_select", option_id = option_id }
      end,
    }
  end
  return specs
end

function M.build_controls(state)
  local function _build_cancel_intent()
    return ui_event_intents.choice_cancel_intent(state, "market_close")
  end

  local function _build_choice_intent(intent_type)
    return function()
      local market = route_model.market(state)
      if not market then return nil end
      return { type = intent_type, choice_id = market.choice_id }
    end
  end

  return {
    {
      name = nodes.confirm,
      build_intent = function()
        local market = route_model.market(state)
        if not market then return nil end
        local ui_runtime = runtime_state.ensure_ui_runtime(state)
        local option_id = ui_runtime.pending_choice_selected_option_id
        if not option_id then
          return nil
        end
        if _buyer_inventory_full(state) then
          _reject_buy_slots_full()
          return nil
        end
        return { type = "market_confirm", choice_id = market.choice_id, option_id = option_id }
      end,
    },
    {
      name = nodes.cancel,
      build_intent = _build_cancel_intent,
    },
    {
      name = nodes.close,
      build_intent = _build_cancel_intent,
    },
    {
      -- #178 点背景关闭:与 close 同一取消意图,权限由同一校验裁定;开关见
      -- BACKGROUND_CLICK_CLOSE_ENABLED。
      name = nodes.background,
      build_intent = function()
        if M.BACKGROUND_CLICK_CLOSE_ENABLED ~= true then
          return nil
        end
        return _build_cancel_intent()
      end,
    },
    {
      name = nodes.page_prev,
      build_intent = _build_choice_intent("market_page_prev"),
    },
    {
      name = nodes.page_next,
      build_intent = _build_choice_intent("market_page_next"),
    },
    {
      name = nodes.tab_item,
      build_intent = function()
        local market = route_model.market(state)
        if not market then return nil end
        return { type = "market_tab_select", choice_id = market.choice_id, tab = "item" }
      end,
    },
  }
end

function M.build_route_specs(state)
  local specs = M.build_items(state)
  for _, spec in ipairs(M.build_controls(state)) do
    specs[#specs + 1] = spec
  end
  return specs
end

-- ===== 面板面(开/关/选) =====

local function _view_deps()
  return {
    runtime = runtime,
    modal_state = require("src.ui.state.modal"),
  }
end

local function _interrupt_panels_before_market_open(state)
  local ui = state and state.ui or nil
  if ui == nil then
    return
  end
  local was_market_active = ui.market_active
  ui.market_active = true
  panel_interrupt.interrupt(state)
  ui.market_active = was_market_active
end

-- 黑市开屏的 per-role 目标(#583):操作者进黑市;旁观者留在自己开着的面板
-- canvas(图鉴/皮肤),都没开才回基础屏——不再无条件把旁观者拽到基础屏。
local function _resolve_market_open_canvas(ui, ctx, role)
  if ctx.can_operate == true then
    return canvas.CANVAS_MARKET
  end
  return canvas.resolve_role_panel_canvas_or_base(ui, runtime.resolve_role_id(role))
end

function M.open_market_panel(state, choice, choice_id, market)
  local ui = state.ui
  local market_payload = market or {
    choice_id = choice_id,
    options = choice.options,
    allow_cancel = choice.allow_cancel,
    cancel_label = choice.cancel_label,
    selected_option_id = runtime_state.ensure_ui_runtime(state).pending_choice_selected_option_id,
    active_tab = choice.active_tab,
    page_index = choice.page_index,
    page_count = choice.page_count,
  }
  local opened = false
  -- #583:弹窗(「卡牌展示屏」等)存活期不抢任何角色的 canvas、也不动面板——
  -- 广播弹窗正盖着黑市 canvas,抢屏会把展示掐成一闪而过;面板早在黑市首开/
  -- 移动打断时已清场,弹窗期重跑 interrupt 只会误伤身份解析异常的旁观者面板。
  -- 数据刷新与 market_active 照常落,收屏回屏按关闭时刻 market_active 把买家
  -- 带回黑市屏。
  local popup_active = ui.popup_active == true

  if not popup_active then
    _interrupt_panels_before_market_open(state)
  end
  runtime.for_each_role_or_global(function(role)
    with_client_role(runtime, role, function()
      local current_model = runtime_state.get_ui_model(state)
      local ctx = role_context.resolve(role, current_model, { runtime = runtime })
      if not popup_active then
        local target = _resolve_market_open_canvas(ui, ctx, role)
        if role then
          canvas.switch_for_role(ui, target, role)
        else
          canvas.switch(ui, target)
        end
      end
      if ctx.can_operate == true then
        opened = market_view.refresh_market(state, market_payload, _view_deps()) == true or opened
      end
    end)
  end)
  runtime.set_client_role(nil)
  ui.market_active = opened
end

M.open = M.open_market_panel

function M.close_market_panel(state)
  market_view.close_market_panel(state, _view_deps())
end

M.close = M.close_market_panel

function M.select_market_option(state, option_id)
  market_view.select_market_option(state, option_id, _view_deps())
end

return M

