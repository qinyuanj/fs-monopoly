-- 黑市购买选择构建器与会话管理。
-- 负责构建 market_buy 选择规格、应用导航、在付费回调后刷新待处理选择,
-- 以及提供购买失败/库存已满等反馈事件。购买结果解释在 purchase_settlement。
local monopoly_event = require("src.foundation.events")
local number_utils = require("src.foundation.number")
local tables = require("src.foundation.tables")
local logger = require("src.foundation.log")
local choice_contract = require("src.config.choice.contract")
local dirty_tracker = require("src.state.dirty_tracker")
local market_query = require("src.rules.market.query")

local query_context = market_query.context
local query_eligibility = market_query.eligibility

local feedback = {}
local _emit_event = monopoly_event.emit

local popup_title = "黑市"

function feedback.emit_buy_failed(player, entry, reason, body)
  _emit_event(monopoly_event.market.buy_failed, {
    player = player,
    entry = entry,
    reason = reason,
    popup = { title = popup_title, body = body },
  })
end

function feedback.emit_inventory_full(player, entry)
  _emit_event(monopoly_event.market.inventory_full, {
    player = player,
    entry = entry,
    body = "卡槽已满，无法继续购买",
  })
end

local builder = {}
local PAGE_SIZE = 10
local TAB_ITEM = "item"

local function _normalize_tab(tab)
  if tables.contains({ TAB_ITEM }, tab) then
    return tab
  end
  return TAB_ITEM
end

-- page_index 缺省回落首页由 clamp 的 nil→min 承担;page_count 在唯一调用方
-- builder.build 处由 number_utils.page_count 保证为 ≥1 整数,两端点的
-- `or 1` 默认值均为死防御(#259 变异清扫删除)。
local function _clamp_page(page_index, page_count)
  return number_utils.clamp(number_utils.to_integer(page_index), 1, page_count)
end

local function _build_tab_entries(player, game, active_tab)
  local merged = {}
  for _, entry in ipairs(query_eligibility.sorted_entries()) do
    if entry.kind == active_tab
        and query_context.entry_market_enabled(entry) then
      local can_buy = query_eligibility.can_buy_entry(game, player, entry)
      merged[#merged + 1] = {
        entry = entry,
        can_buy = can_buy,
        sold_out = query_eligibility.is_sold_out(game, entry),
      }
    end
  end
  return merged
end

local function _build_options_for_page(visible, page_index, page_size)
  local start_index = (page_index - 1) * page_size + 1
  local last_index = start_index + page_size - 1
  local options = {}
  local body_lines = {}
  for index = start_index, last_index do
    local slot = visible[index]
    if not slot then
      break
    end
    local entry = slot.entry
    local name = query_context.entry_name(entry)
    local price = query_context.entry_price(entry)
    local currency = query_context.entry_currency(entry)
    local label = name .. " - " .. number_utils.format_integer_part(price) .. " " .. currency
    body_lines[#body_lines + 1] = label
    options[#options + 1] = {
      id = entry.product_id,
      label = label,
      can_buy = slot.can_buy,
      sold_out = slot.sold_out,
    }
  end
  return body_lines, options
end

function builder.build(player, game, state)
  state = state or {}
  local active_tab = _normalize_tab(state.active_tab)
  local visible = _build_tab_entries(player, game, active_tab)
  -- foundation 的 page_count 与本地实现逐点等价(含空列表 → 1 页),
  -- 本地化简后删除(#259 变异清扫:双默认值死防御不可达)。
  local page_count = number_utils.page_count(#visible, PAGE_SIZE)
  local page_index = _clamp_page(state.page_index, page_count)
  local body_lines, options = _build_options_for_page(visible, page_index, PAGE_SIZE)
  return {
    kind = "market_buy",
    route_key = "market",
    owner_role_id = player.id,
    title = "黑市",
    body_lines = body_lines,
    options = options,
    allow_cancel = true,
    cancel_label = "不买",
    active_tab = active_tab,
    page_index = page_index,
    page_count = page_count,
    meta = {
      player_id = player.id,
      active_tab = active_tab,
      page_index = page_index,
      page_count = page_count,
    },
  }
end

local session = {}

local function _mark_choice_dirty(game)
  if not game or not game.dirty then
    return
  end
  dirty_tracker.mark(game.dirty, "turn")
  dirty_tracker.mark(game.dirty, "market")
end

local function _current_choice_state(pending_choice)
  return {
    active_tab = pending_choice and pending_choice.active_tab or nil,
    page_index = pending_choice and pending_choice.page_index or nil,
  }
end

local _resolve_owner_role_id = choice_contract.resolve_owner_role_id

local function _apply_spec(game, pending_choice, spec)
  -- 无入口断言:两个调用方(rebuild_pending / _apply_navigation_spec)都在
  -- 进入前挡掉了 nil pending_choice 与 nil spec,守卫不可达(#259 删除)。
  pending_choice.title = spec.title
  pending_choice.body_lines = spec.body_lines
  pending_choice.options = spec.options
  pending_choice.allow_cancel = spec.allow_cancel
  pending_choice.cancel_label = spec.cancel_label
  pending_choice.active_tab = spec.active_tab
  pending_choice.page_index = spec.page_index
  pending_choice.page_count = spec.page_count
  pending_choice.owner_role_id = spec.owner_role_id
  pending_choice.meta = spec.meta
  _mark_choice_dirty(game)
end

local function _valid_market_buy(game, pending_choice)
  return game ~= nil and pending_choice ~= nil and pending_choice.kind == "market_buy"
end

function session.rebuild_pending(game, pending_choice, player, state)
  if not _valid_market_buy(game, pending_choice) then
    return false
  end
  if not player then
    return false
  end
  local spec = builder.build(player, game, state or _current_choice_state(pending_choice))
  if not spec then
    return false
  end
  _apply_spec(game, pending_choice, spec)
  return true
end

local NAVIGATION_ACTIONS = {
  market_tab_select = function(action, active_tab, page_index)
    if active_tab == action.tab then
      return active_tab, page_index, true
    end
    -- 页码用 nil 表达「回默认」:build 端 clamp(nil → 1) 承担,字面量 1 的
    -- 1→0 变异会被 clamp 吸收成等价体(#259 化简)。
    return action.tab, nil, false
  end,
  market_page_prev = function(_, active_tab, page_index)
    local current = number_utils.to_integer(page_index)
    -- nil 页码同样交 clamp 回落首页;`(x or 1) - 1` 的 1→0 变异在 clamp 下
    -- 不可观测,此形态下该变异体会跳过递减直接可杀。
    return active_tab, current and current - 1 or nil, false
  end,
  market_page_next = function(_, active_tab, page_index)
    return active_tab, (number_utils.to_integer(page_index) or 1) + 1, false
  end,
}

local function _apply_navigation_action(action, active_tab, page_index)
  local handler = NAVIGATION_ACTIONS[action.type]
  if handler then
    return handler(action, active_tab, page_index)
  end
  return active_tab, page_index, false
end

local function _resolve_navigation_player(game, pending_choice)
  if not game or not pending_choice or pending_choice.kind ~= "market_buy" then
    return nil
  end
  local player_id = _resolve_owner_role_id(pending_choice)
  if not player_id then
    return nil
  end
  return game:find_player_by_id(player_id)
end

local function _build_navigation_spec(player, game, pending_choice, active_tab, page_index)
  return builder.build(player, game, {
    active_tab = active_tab,
    page_index = page_index,
    page_count = pending_choice.page_count,
  })
end

local function _apply_navigation_spec(game, pending_choice, player, spec)
  if spec == nil then
    return false
  end
  if #spec.options == 0 then
    feedback.emit_buy_failed(player, nil, "empty_tab", "当前页签暂无可购买项")
  end
  _apply_spec(game, pending_choice, spec)
  return true
end

function session.apply_navigation(game, pending_choice, action)
  local player = _resolve_navigation_player(game, pending_choice)
  if not player then
    return false
  end
  local active_tab, page_index, unchanged = _apply_navigation_action(
    action, pending_choice.active_tab, pending_choice.page_index
  )
  if unchanged then
    return true
  end
  local spec = _build_navigation_spec(player, game, pending_choice, active_tab, page_index)
  return _apply_navigation_spec(game, pending_choice, player, spec)
end

local function _turn_pending_choice(game)
  return game and game.turn and game.turn.pending_choice or nil
end

local function _market_pending_choice(game)
  local pending_choice = _turn_pending_choice(game)
  if not pending_choice or pending_choice.kind ~= "market_buy" then
    return nil
  end
  return pending_choice
end

local function _is_pending_choice_owner(pending_choice, player)
  local owner_id = _resolve_owner_role_id(pending_choice)
  return owner_id == (player and player.id or nil)
end

local function _warn_refresh_skipped(player, entry)
  logger.warn(
    "market paid callback refresh skipped:",
    "player_id=" .. tostring(player and player.id or nil),
    "product_id=" .. tostring(entry and entry.product_id)
  )
end

function session.refresh_after_paid_callback(game, player, entry)
  local pending_choice = _market_pending_choice(game)
  if not pending_choice or not _is_pending_choice_owner(pending_choice, player) then
    return false
  end
  local rebuilt = session.rebuild_pending(game, pending_choice, player)
  if rebuilt then
    return true
  end
  _warn_refresh_skipped(player, entry)
  return false
end

return {
  builder = builder,
  feedback = feedback,
  session = session,
  _M_test = {
    _current_choice_state = _current_choice_state,
  },
}

