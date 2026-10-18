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

--[[ mutate4lua-manifest
version=4
projectHash=d38ab9b1615d7ce9
scope.0.id=chunk:src/computer/agent/path.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=148
scope.0.semanticHash=26bd42fcbb71ed5d
scope.1.id=function:_current_rent
scope.1.kind=function
scope.1.startLine=9
scope.1.endLine=11
scope.1.semanticHash=07635c8d26c67905
scope.2.id=function:<anonymous>
scope.2.kind=function
scope.2.startLine=24
scope.2.endLine=26
scope.2.semanticHash=346f85e6116f09a8
scope.3.id=function:<anonymous>#2
scope.3.kind=function
scope.3.startLine=27
scope.3.endLine=29
scope.3.semanticHash=346f85e6116f09a8
scope.4.id=function:<anonymous>#3
scope.4.kind=function
scope.4.startLine=30
scope.4.endLine=32
scope.4.semanticHash=5d82763122c11a5c
scope.5.id=function:<anonymous>#4
scope.5.kind=function
scope.5.startLine=36
scope.5.endLine=45
scope.5.semanticHash=6af07ee7fa882ae1
scope.6.id=function:remote_priority_rules.tile_type
scope.6.kind=function
scope.6.startLine=50
scope.6.endLine=52
scope.6.semanticHash=a679b7e604ea4e33
scope.7.id=function:_stops_walk
scope.7.kind=function
scope.7.startLine=57
scope.7.endLine=66
scope.7.semanticHash=6df264cac2c2cf2e
scope.8.id=function:_simulate_landing
scope.8.kind=function
scope.8.startLine=68
scope.8.endLine=89
scope.8.semanticHash=226562ad7b3d41e3
scope.9.id=function:_remote_priority_for_tile_type
scope.9.kind=function
scope.9.startLine=91
scope.9.endLine=97
scope.9.semanticHash=6f8c2cd1dad9136d
scope.10.id=function:_remote_priority
scope.10.kind=function
scope.10.startLine=99
scope.10.endLine=108
scope.10.semanticHash=938ec33d9c8fb24c
scope.11.id=function:_best_score
scope.11.kind=function
scope.11.startLine=110
scope.11.endLine=112
scope.11.semanticHash=45ff3108e60ca5f4
scope.12.id=function:_is_better_remote_choice
scope.12.kind=function
scope.12.startLine=114
scope.12.endLine=119
scope.12.semanticHash=677ba9e0b2f6c177
scope.13.id=function:_merge_remote_candidate
scope.13.kind=function
scope.13.startLine=122
scope.13.endLine=131
scope.13.semanticHash=dc5ec70ae32c40b8
scope.14.id=function:path_planner.pick_remote_dice_value
scope.14.kind=function
scope.14.startLine=133
scope.14.endLine=145
scope.14.semanticHash=21db2f533be7ccfa
]]
