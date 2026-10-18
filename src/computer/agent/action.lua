local roadblock = require("src.rules.items.roadblock")
local demolish = require("src.rules.items.demolish")
local item_ids = require("src.config.gameplay.item_ids")

local action_selector = {}

local function _other_alive(p, player)
  return not p.eliminated and p.id ~= player.id
end

local function _allowed(allow_ids, player_id)
  return allow_ids == nil or allow_ids[player_id]
end

local function _richer(cash, best_cash)
  return best_cash == nil or cash > best_cash
end

local function _richest_other(game, player, allow_ids)
  local best, best_cash = nil, nil
  for _, p in ipairs(game.players) do
    if _other_alive(p, player) then
      if _allowed(allow_ids, p.id) then
        local cash = game:player_cash(p)
        if _richer(cash, best_cash) then
          best = p
          best_cash = cash
        end
      end
    end
  end
  return best
end

local function _is_richest(game, player)
  local player_cash = game:player_cash(player)
  for _, p in ipairs(game.players) do
    if not p.eliminated and p.id ~= player.id and game:player_cash(p) > player_cash then
      return false
    end
  end
  return true
end

local function _allow_from_options(options)
  if not options then
    return nil
  end
  local allowed = {}
  for _, opt in ipairs(options) do
    allowed[opt.id] = true
  end
  return allowed
end

local function _pick_share_wealth_target(game, player, allowed)
  if _is_richest(game, player) then
    return nil
  end
  return _richest_other(game, player, allowed)
end

local function _targetable(p, player, allowed)
  return p.id ~= player.id and not p.eliminated and (not allowed or allowed[p.id])
end

local function _rich_candidate(game, p, best)
  return game:player_has_deity(p, "rich") and best == nil
end

local function _pick_deity_target(game, player, allowed)
  local best = nil
  for _, p in ipairs(game.players) do
    if _targetable(p, player, allowed) then
      if game:player_has_deity(p, "angel") then
        return p
      end
      if _rich_candidate(game, p, best) then
        best = p
      end
    end
  end
  return best
end

local function _has_inventory(p)
  return p.inventory ~= nil and p.inventory:count() > 0
end

-- #101：合法目标中经共享 game.rng 均匀随机，名单顺序不再决定集火对象。
local function _random_from(candidates, game)
  if #candidates == 0 then
    return nil
  end
  local rng = assert(game and game.rng, "missing game.rng for random target pick")
  assert(type(rng.next_int) == "function", "missing game.rng.next_int for random target pick")
  return candidates[rng:next_int(1, #candidates)]
end

local function _pick_random_target(game, player, allowed, keep)
  local candidates = {}
  for _, p in ipairs(game.players) do
    if _targetable(p, player, allowed) then
      if not keep or keep(p) then
        candidates[#candidates + 1] = p
      end
    end
  end
  return _random_from(candidates, game)
end

local function _pick_steal_target(game, player, allowed)
  return _pick_random_target(game, player, allowed, _has_inventory)
end

local function _pick_missile_target(game, player, allowed)
  return _pick_random_target(game, player, allowed, nil)
end

local function _pick_send_poor_target(game, player, allowed)
  if not game:player_has_deity(player, "poor") then return nil end
  return _richest_other(game, player, allowed)
end

local _target_pickers = {
  [item_ids.share_wealth] = _pick_share_wealth_target,
  [item_ids.exile] = _richest_other,
  [item_ids.tax] = _richest_other,
  [item_ids.poor] = _richest_other,
  [item_ids.steal] = _pick_steal_target,
  [item_ids.missile] = _pick_missile_target,
  [item_ids.invite_deity] = _pick_deity_target,
  [item_ids.send_poor] = _pick_send_poor_target,
}

function action_selector.pick_target_player(game, player, item_id, options)
  local allowed = _allow_from_options(options)
  local picker = _target_pickers[item_id]
  if picker then return picker(game, player, allowed) end
  return nil
end

function action_selector.pick_roadblock_target(game, player)
  local candidates = roadblock.auto_candidates(game, player, 3)
  if not candidates or #candidates == 0 then
    return nil
  end
  local best = roadblock.pick_best(candidates)
  if not best then
    return nil
  end
  return best.idx
end

action_selector.pick_demolish_target = demolish.find_target

return action_selector

