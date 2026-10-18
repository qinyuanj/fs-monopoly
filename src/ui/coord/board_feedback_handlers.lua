-- 棋盘反馈 cue 事件处理器(自 event_handlers.lua 拆分,行为保持):租金/税务/
-- 机会卡/回合开始/状态/神明/破产等事件的 player/tile 级 cue 与打断;
-- 踩雷/地块命中索引定位在 tile_index_handlers。
local board_feedback = require("src.ui.render.board_feedback.service")
local panel_interrupt = require("src.ui.state.panel_interrupt")

local board_feedback_handlers = {}
local context = { state = nil }

local function _event_data(data)
  if type(data) == "table" then
    return data
  end
  return nil
end

local function _event_field(event_data, key)
  return event_data and event_data[key] or nil
end

local function _cue_subject(event_data, subject_key)
  return event_data and event_data[subject_key] or nil
end

local function _player_cue_from_subject(cue_name, subject_key)
  return function(data)
    local event_data = _event_data(data)
    local ctx = context.state
    local subject = _cue_subject(event_data, subject_key)
    if ctx and subject and subject.id ~= nil then
      board_feedback.play_player_cue(ctx, cue_name, subject.id, event_data)
    end
  end
end

local function _player_id(player)
  return player and player.id or nil
end

local function _negative_card_ready(ctx, player_id, card)
  return ctx and player_id ~= nil and card and card.negative == true
end

-- 负向卡(negative=true)对持有者播一次 generic_negative cue;条件不齐
-- (ctx/player/card 缺省或非负卡)时静默。
local function _play_negative_card_cue(ctx, player, card, event_data)
  local player_id = _player_id(player)
  if _negative_card_ready(ctx, player_id, card) then
    board_feedback.play_player_cue(ctx, "generic_negative", player_id, event_data)
  end
end

local function _event_player_id(event_data)
  return event_data and (event_data.player_id or (event_data.player and event_data.player.id)) or nil
end

local function _player_cue_from_player_id(cue_name)
  return function(data)
    local event_data = _event_data(data)
    local ctx = context.state
    local player_id = _event_player_id(event_data)
    if ctx and player_id ~= nil then
      board_feedback.play_player_cue(ctx, cue_name, player_id, event_data)
    end
  end
end

-- 播 tile 级 cue;命中(条件齐)时返回 true 供调用方跳过 player 级兜底。
local function _play_tile_cue(ctx, cue_name, tile_index, event_data)
  if ctx and cue_name and tile_index ~= nil then
    board_feedback.play_tile_cue(ctx, cue_name, tile_index, event_data)
    return true
  end
  return false
end

local function _deity_cue_name(deity_type)
  if deity_type == "rich" then
    return "rich_deity"
  end
  if deity_type == "angel" then
    return "angel_deity"
  end
  return nil
end

function board_feedback_handlers.set_context(state)
  context.state = state
end

function board_feedback_handlers.install(register_handler, monopoly_event)
  local _handle_rent_cue = _player_cue_from_subject("cash_burst", "owner")
  register_handler(monopoly_event.land.rent_paid, _handle_rent_cue)
  register_handler(monopoly_event.land.rent_bankrupt, _handle_rent_cue)

  register_handler(monopoly_event.land.tax_paid, _player_cue_from_subject("tax_wave", "player"))

  register_handler(monopoly_event.chance.applied, function(data)
    local event_data = _event_data(data)
    local ctx = context.state
    local player = _event_field(event_data, "player")
    local card = _event_field(event_data, "card")
    _play_negative_card_cue(ctx, player, card, event_data)
  end)

  register_handler(monopoly_event.feedback.turn_started, function(data)
    local event_data = _event_data(data)
    local ctx = context.state
    local player_id = _event_player_id(event_data)
    if ctx and player_id ~= nil then
      board_feedback.play_player_cue(ctx, "turn_started", player_id, event_data)
      panel_interrupt.begin_player_action(ctx, player_id)
    end
  end)

  register_handler(monopoly_event.feedback.status_applied, function(data)
    local event_data = _event_data(data)
    local ctx = context.state
    local cue_name = _event_field(event_data, "cue_name")
    local tile_index = _event_field(event_data, "tile_index")
    if not _play_tile_cue(ctx, cue_name, tile_index, event_data) then
      local player_id = _event_player_id(event_data)
      if ctx and cue_name and player_id ~= nil then
        board_feedback.play_player_cue(ctx, cue_name, player_id, event_data)
      end
    end
  end)

  register_handler(monopoly_event.feedback.deity_applied, function(data)
    local event_data = _event_data(data)
    local ctx = context.state
    local player_id = _event_player_id(event_data)
    local cue_name = _deity_cue_name(_event_field(event_data, "deity_type"))
    if ctx and cue_name and player_id ~= nil then
      board_feedback.play_player_cue(ctx, cue_name, player_id, event_data)
    end
  end)

  register_handler(monopoly_event.feedback.angel_immune_blocked, function(data)
    local event_data = _event_data(data)
    local ctx = context.state
    local player_id = _event_player_id(event_data)
    if not _play_tile_cue(ctx, "angel_deity", _event_field(event_data, "tile_index"), event_data) then
      if ctx and player_id ~= nil then
        board_feedback.play_player_cue(ctx, "angel_deity", player_id, event_data)
      end
    end
  end)

  register_handler(monopoly_event.feedback.bankruptcy, _player_cue_from_player_id("bankruptcy_slam"))

  register_handler(monopoly_event.market.bought_item, _player_cue_from_subject("cash_burst", "player"))
end

return board_feedback_handlers

