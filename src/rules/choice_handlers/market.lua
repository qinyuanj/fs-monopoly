local availability = require("src.rules.items.availability")
local number_utils = require("src.foundation.number")
local market_service = require("src.rules.market")
local purchase_settlement = require("src.rules.market.purchase_settlement")
local market_context = require("src.rules.market.query").context
local event_kinds = require("src.config.gameplay.event_kinds")
local dirty_tracker = require("src.state.dirty_tracker")

local M = {}

local TAB_ITEM = "item"

local function _normalize_market_tab(active_tab)
  if active_tab == TAB_ITEM then
    return active_tab
  end
  return TAB_ITEM
end

local function _normalize_page_value(value)
  local page_value = number_utils.to_integer(value) or 1
  if page_value < 1 then
    return 1
  end
  return page_value
end

local function _normalize_market_buy_meta(_, meta, choice_spec)
  local normalized_meta = availability.copy_table(meta)
  availability.normalize_integer_field(normalized_meta, "player_id", choice_spec.kind)
  normalized_meta.active_tab = _normalize_market_tab(normalized_meta.active_tab or choice_spec.active_tab)
  normalized_meta.page_index = _normalize_page_value(normalized_meta.page_index or choice_spec.page_index)
  normalized_meta.page_count = _normalize_page_value(normalized_meta.page_count or choice_spec.page_count)
  choice_spec.owner_role_id = choice_spec.owner_role_id or normalized_meta.player_id
  choice_spec.active_tab = normalized_meta.active_tab
  choice_spec.page_index = normalized_meta.page_index
  choice_spec.page_count = normalized_meta.page_count
  return normalized_meta
end

local function _validate_market_player(game, meta)
  return assert(game:find_player_by_id(meta.player_id), "missing player: " .. tostring(meta.player_id))
end

local function _validate_market_entry(product_id)
  return assert(market_context.entry_by_id(product_id), "missing market entry: " .. tostring(product_id))
end

local function _validate_market_buy_meta(game, meta)
  _validate_market_player(game, meta)
end

local function _normalize_market_buy_action(_, _, action)
  local normalized_action = availability.copy_table(action)
  availability.normalize_integer_field(normalized_action, "option_id", "market_buy", "action", true)
  return normalized_action
end

-- #543:获得展示统一为 item_gain_popup 纯等待动画,黑市来源仍靠
-- source=="market" 识别,取消购买时撤掉待播的揭示等待。
local function _is_market_item_reveal(anim)
  return anim ~= nil
    and anim.kind == event_kinds.item_gain_popup
    and anim.source == "market"
end

local function _remove_market_reveals_from_queue(queue)
  if type(queue) ~= "table" then
    return false
  end
  local removed = false
  for index = #queue, 1, -1 do
    if _is_market_item_reveal(queue[index]) then
      table.remove(queue, index)
      removed = true
    end
  end
  return removed
end

local function _clear_current_market_reveal(turn)
  if _is_market_item_reveal(turn.action_anim) then
    turn.action_anim = nil
    return true
  end
  return false
end

local function _turn_of(game)
  return game and game.turn or nil
end

-- 取消购买时,把已排上的「商店抽到道具」揭示动画撤干净(正在播的 + 队列里的)。
local function _clear_market_item_reveals(game)
  local turn = _turn_of(game)
  if turn == nil then
    return
  end
  local cleared_current = _clear_current_market_reveal(turn)
  local cleared_queued = _remove_market_reveals_from_queue(turn.action_anim_queue)
  if cleared_current or cleared_queued then
    dirty_tracker.mark(game.dirty, "turn")
  end
end

local function _build(helpers)
  local finish_choice = helpers.finish_choice

  local function _handle_market_buy(game, choice, action)
    local meta = choice.meta
    local player = _validate_market_player(game, meta)
    local product_id = assert(number_utils.to_integer(action.option_id), "missing product_id")
    local entry = _validate_market_entry(product_id)
    local result = market_service.purchase.execute(game, player, product_id)
    local verdict = purchase_settlement.resolve(game, choice, player, entry, result)
    if verdict.keep_open then
      return { stay = true }
    end
    return finish_choice(game, false)
  end

  return {
    market_buy = {
      required_meta = { "player_id" },
      normalize_meta = _normalize_market_buy_meta,
      meta_validator = _validate_market_buy_meta,
      normalize_action = _normalize_market_buy_action,
      cancel = {
        resolve = function(game)
          _clear_market_item_reveals(game)
        end,
      },
      execute = _handle_market_buy,
    },
  }
end

function M.register(registry, helpers)
  local handlers = _build(helpers)
  for kind, handler in pairs(handlers) do
    registry[kind] = handler
  end
end

return M

