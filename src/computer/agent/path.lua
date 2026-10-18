local tile = require("src.rules.board.tile")
local pricing = require("src.rules.land.pricing")
local movement = require("src.rules.movement")
local path_planner = {}

local tile_state = tile.get_state


local function _current_rent(tile_ref, level)
  return pricing.rent_for_level(tile_ref, level or 0)
end

local remote_step_rank_by_type = {
  item = 1,
  chance = 2,
  start = 5,
  market = 6,
  mountain = 7,
  tax = 8,
  hospital = 9,
}

local remote_land_priority_rules = {
  unowned = function(_, _, _, steps)
    return 3, steps
  end,
  self_owned = function(_, _, _, steps)
    return 4, steps
  end,
  enemy_owned = function(_, _, tile_ref)
    return 10, -_current_rent(tile_ref, tile_ref.level)
  end,
}

local remote_priority_rules = {
  land = function(game, player, tile_ref, steps)
    local st = tile_state(game, tile_ref)
    local land_rule_key = "enemy_owned"
    if not st or not st.owner_id then
      land_rule_key = "unowned"
    elseif st.owner_id == player.id then
      land_rule_key = "self_owned"
    end
    return remote_land_priority_rules[land_rule_key](game, player, tile_ref, steps)
  end,
}

for tile_type, rank in pairs(remote_step_rank_by_type) do
  local current_rank = rank
  remote_priority_rules[tile_type] = function(_, _, _, steps)
    return current_rank, steps
  end
end

-- #102:预测不再自带一份走步规则,直接复用真实移动的纯计算（movement.predict_landing）,
-- 黑市恢复、自雷宽限、内圈朝向与入口跳过因此与真实落点天然一致。
local function _simulate_landing(game, player, steps)
  local index = movement.predict_landing(game, player, steps)
  return { idx = index, tile = game.board:get_tile(index), steps = steps }
end

-- 行为测试公共接缝：test_predict_real_move 比较电脑预测与真实移动的黑市恢复、
-- 自雷宽限和朝向落点；生产遥控骰预测共用 movement.predict_landing。
function path_planner.predict_landing(game, player, steps)
  return movement.predict_landing(game, player, steps)
end

local function _remote_priority_for_tile_type(tile_type, steps)
  local rule = remote_priority_rules[tile_type]
  if not rule then
    return nil
  end
  return rule(nil, nil, nil, steps)
end

local function _remote_priority(game, player, sim)
  local tile_ref = sim.tile
  if not tile_ref then
    return nil
  end
  if tile_ref.type == "land" then
    return remote_priority_rules.land(game, player, tile_ref, sim.steps)
  end
  return _remote_priority_for_tile_type(tile_ref.type, sim.steps)
end

local function _best_score(best)
  return best and best.score or -2147483647
end

local function _is_better_remote_choice(best, rank, score_value)
  local best_score = _best_score(best)
  return best == nil
    or rank < best.rank
    or (rank == best.rank and score_value > best_score)
end

-- Keeps the incumbent `best` when this candidate is unranked, or ranks no better.
local function _merge_remote_candidate(best, rank, score, value, sim)
  if not rank then
    return best
  end
  local score_value = score or 0
  if not _is_better_remote_choice(best, rank, score_value) then
    return best
  end
  return { rank = rank, score = score_value, value = value, tile = sim.tile }
end

function path_planner.pick_remote_dice_value(game, player, dice_count)
  dice_count = dice_count or 1
  local best
  for value = 1, 6 do
    local sim = _simulate_landing(game, player, value * dice_count)
    local rank, score = _remote_priority(game, player, sim)
    best = _merge_remote_candidate(best, rank, score, value, sim)
  end
  if not best then
    return nil, nil
  end
  return best.value, best.tile
end

return path_planner

