local auto_play_port = require("src.rules.ports.auto_play")
local effects = require("src.rules.items.post_effects")
local item_ids = require("src.config.gameplay.item_ids")
local availability = require("src.rules.items.availability")
local demolish = require("src.rules.items.demolish")
local facing_policy = require("src.rules.board.facing_policy")
local use_flow = require("src.rules.items.use_flow")

local strategy = {}
function strategy.target_candidates(game, player, item_id)
  local registries = assert(game.registries, "missing game.registries")
  local registry = assert(registries.items, "missing item registry")
  return registry:target_candidates(game, player, item_id)
end

local function _has_obstacle(board, idx)
  return board:has_roadblock(idx) or board:has_mine(idx)
end

function strategy.has_obstacles_ahead(game, player, distance)
  local board = game.board
  distance = distance or 12
  local parity = distance
  local current = player.position
  local facing = facing_policy.resolve_initial_facing("fresh_forward", player)
  local entered_inner = false

  for _ = 1, distance do
    local next_index, _, next_facing, step_entered_inner = board:step_forward_by_facing(current, facing, {
      parity = parity,
      entered_inner = entered_inner,
    })
    current = next_index
    facing = next_facing
    if step_entered_inner then
      entered_inner = true
    end
    if _has_obstacle(board, current) then
      return true
    end
  end
  return false
end

function strategy.can_offer_in_phase(game, player, item_id, phase)
  local ok = availability.can_offer_in_phase(game, player, item_id, phase)
  return ok == true
end

local function _ai_can_use_item(item_id, phase)
  return availability.can_auto_consider_item(item_id, phase)
end

local function _resolve_try_use_item_args(game, phase_or_cond, cond_or_auto_play, auto_play)
  if type(phase_or_cond) == "string" then
    return phase_or_cond, cond_or_auto_play, auto_play
  end
  local phase = game and game.turn and game.turn.phase or nil
  return phase, phase_or_cond, cond_or_auto_play
end

local function _successful_flow_result(res)
  if type(res) ~= "table" or res.ok ~= true then
    return nil
  end
  return res
end

local function _ai_actor_id(player)
  return player and player.id or nil
end

local function _try_use_item(game, player, item_id, phase, cond, auto_play)
  phase, cond, auto_play = _resolve_try_use_item_args(game, phase, cond, auto_play)
  if cond and cond() == false then return nil end
  if not _ai_can_use_item(item_id, phase) then
    return nil
  end
  local res = use_flow.begin_item_use(game, _ai_actor_id(player), item_id, {
    phase = phase,
    is_computer_controlled = true,
    auto_play = auto_play,
  })
  return _successful_flow_result(res)
end

local function _has_target_player(game, player, item_id)
  return auto_play_port.pick_target_player(game, player, item_id, strategy.target_candidates(game, player, item_id)) and true or false
end

local function _has_demolish_target(game, player)
  return demolish.find_target(game, player, 3) and true or false
end

local function _try_clear_obstacles(game, player, phase, auto_play)
  return _try_use_item(game, player, item_ids.clear_obstacles, phase, function()
    return strategy.has_obstacles_ahead(game, player, 12)
  end, auto_play)
end

local function _try_remote_dice(game, player, phase, auto_play)
  return _try_use_item(game, player, item_ids.remote_dice, phase, function()
    local dice_count = game:player_dice_count(player)
    return auto_play_port.pick_remote_dice_value(game, player, dice_count) and true or false
  end, auto_play)
end

local function _try_roadblock(game, player, phase, auto_play)
  return _try_use_item(game, player, item_ids.roadblock, phase, function()
    return auto_play_port.pick_roadblock_target(game, player) and true or false
  end, auto_play)
end

local function _try_target_items(game, player, phase, auto_play)
  for _, id in ipairs(effects.target_item_ids()) do
    local res = _try_use_item(game, player, id, phase, function() return _has_target_player(game, player, id) end, auto_play)
    if res then return res end
  end
  return nil
end

local function _try_deity_items(game, player, phase, auto_play)
  local rich_result = _try_use_item(game, player, item_ids.rich, phase, nil, auto_play)
  if rich_result then return rich_result end
  return _try_use_item(game, player, item_ids.angel, phase, nil, auto_play)
end

local function _try_monster(game, player, phase, auto_play)
  return _try_use_item(game, player, item_ids.monster, phase, function()
    return _has_demolish_target(game, player)
  end, auto_play)
end

local function _try_mine(game, player, phase, auto_play)
  return _try_use_item(game, player, item_ids.mine, phase, nil, auto_play)
end

local function _try_dice_multiplier(game, player, phase, auto_play)
  return _try_use_item(game, player, item_ids.dice_multiplier, phase, nil, auto_play)
end

-- AI auto-play probes, attempted in priority order; first success short-circuits.
local _AUTO_PRE_ACTION_PROBES = {
  _try_clear_obstacles,
  _try_remote_dice,
  _try_mine,
  _try_dice_multiplier,
  _try_roadblock,
  _try_monster,
  _try_target_items,
  _try_deity_items,
}

local function _run_auto_pre_action_probes(game, player, phase, auto_play)
  for _, probe in ipairs(_AUTO_PRE_ACTION_PROBES) do
    local res = probe(game, player, phase, auto_play)
    if res then
      return res
    end
  end
  return nil
end

function strategy.auto_pre_action(game, player, phase)
  if not auto_play_port.is_computer_controlled(game, player) then
    return nil
  end
  return _run_auto_pre_action_probes(game, player, phase, nil)
end

-- Export helpers for testability
strategy._ai_can_use_item = _ai_can_use_item
strategy._try_use_item = _try_use_item
strategy._has_target_player = _has_target_player
strategy._has_demolish_target = _has_demolish_target
strategy._try_clear_obstacles = _try_clear_obstacles
strategy._try_remote_dice = _try_remote_dice
strategy._try_roadblock = _try_roadblock
strategy._try_target_items = _try_target_items
strategy._try_deity_items = _try_deity_items

return strategy

