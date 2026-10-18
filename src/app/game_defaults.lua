-- 初始游戏对象构造助手(自 compose_game.lua 拆分,行为保持):玩家索引、
-- 地块初始态、市场限额、初始 turn 与默认字段装配。组合根保留装载时序,
-- 这里只承载纯构造逻辑。
local market_cfg = require("src.config.content.market")
local game_factory = require("src.app.game_factory")
local number_utils = require("src.foundation.number")
local role_id_utils = require("src.foundation.identity")
local intent_dispatcher = require("src.turn.output.intent_dispatcher")
local dirty_tracker = require("src.state.dirty_tracker")

local game_defaults = {}

-- 归一化 player 的 role id 后按 id 收录,id 非法(空/无法归一化)时跳过。
local function _insert_normalized_player(out, p)
  if p and p.id ~= nil then
    local player_id = role_id_utils.normalize(p.id)
    if player_id ~= nil then
      out[player_id] = p
    end
  end
end

function game_defaults.build_player_by_id(players)
  local out = {}
  for _, p in ipairs(players or {}) do
    _insert_normalized_player(out, p)
  end
  return out
end

function game_defaults.init_tile_state(board)
  for _, t in ipairs(board.path) do
    if t.type == "land" then
      t.owner_id = nil
      t.level = 0
    end
  end
end

function game_defaults.build_market_limits()
  local limits = {}
  for _, entry in ipairs(market_cfg) do
    local limit = number_utils.to_integer(entry.limit)
    if limit and limit >= 1 then
      limits[entry.product_id] = limit
    end
  end
  return limits
end

function game_defaults.build_initial_turn()
  return {
    current_player_index = 1,
    turn_count = 0,
    countdown_seconds = 0,
    countdown_active = false,
    phase = "start",
    pending_choice = nil,
    choice_seq = 0,
    move_anim_seq = 0,
    move_anim = nil,
    action_anim_seq = 0,
    action_anim = nil,
    action_anim_queue = {},
    landing_visual_hold_active = false,
    landing_visual_release_pending = false,
    move_followup_pending = false,
    detained_wait_active = false,
    detained_wait_seconds = 0,
    detained_wait_elapsed = 0,
    inter_turn_wait_active = false,
    inter_turn_wait_seconds = 0,
    inter_turn_wait_elapsed = 0,
    no_action_notice_active = false,
    no_action_notice_player_id = nil,
    no_action_notice_text = nil,
    item_phase = {},
    used_effect_groups = {},
    item_phase_active = "",
    market_prompt = nil,
    post_action = nil,
  }
end

function game_defaults.is_class_like(value)
  if type(value) ~= "table" then
    return false
  end
  local meta = getmetatable(value)
  local is_instance = type(meta) == "table" and type(meta.__newindex) == "function"
  if is_instance then
    return false
  end
  return value.__name ~= nil and type(value.new) == "function"
end

function game_defaults.apply_game_defaults(game, opts, board, players, dirty)
  game.board = board
  game.players = players
  game.player_by_id = game_defaults.build_player_by_id(players)
  game.turn = game_defaults.build_initial_turn()
  game.turn.turn_start_prompt_seq = 0
  game.turn.turn_start_prompt_player_id = nil
  game.dirty = dirty
  game.market_limits = game_defaults.build_market_limits()
  game.rng = opts.rng or game_factory.build_rng()
  game.finished = false
  game.winner = nil
  game.last_turn = nil
  game._land_rent_version = 0
  game._land_rent_cache = nil
  game.tile_owner_notifier = game.tile_owner_notifier or {
    notify_owner_changed = function() end,
  }
  game.board_visual_feedback_port = game.board_visual_feedback_port or {
    sync_many = function()
      return false
    end,
  }
  game.intent_output_port = game.intent_output_port or intent_dispatcher.build_port()
  function game:consume_dirty()
    return dirty_tracker.consume(self.dirty)
  end
end

return game_defaults

