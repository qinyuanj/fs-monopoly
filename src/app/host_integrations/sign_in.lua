local number_utils = require("src.foundation.number")
local rewards = require("src.config.content.sign_in_rewards")

-- The host sign-in panel fires custom events RewardDay1..RewardDay7 when a
-- player claims a day's reward; the Lua side only grants the configured coins.
-- The calendar gating (first login of day, claimable state, streak) stays in
-- the host panel.
local EVENT_PREFIX = "RewardDay"

local sign_in = {
  rewards = rewards,
  event_prefix = EVENT_PREFIX,
}

-- 行为测试公共查询：test_sign_in 按宿主签到日观察已配置的奖励金额。
function sign_in.amount_for_day(day)
  return rewards[day]
end

-- "RewardDay3" -> 3; any name that is not RewardDay<positive-int> -> nil.
function sign_in.day_from_event(event_name)
  if type(event_name) ~= "string" then
    return nil
  end
  local digits = event_name:match("^" .. EVENT_PREFIX .. "(%d+)$")
  if digits == nil then
    return nil
  end
  return number_utils.to_integer(digits)
end

-- 取 `day` 的配置奖励:day 无配置(未登记的键或 nil)时返回 nil。
local function _grant_amount(day)
  return day ~= nil and rewards[day] or nil
end

-- Grant the configured reward for `day` to `player`. No-op (returns false) when
-- the day has no configured reward or arguments are missing.
function sign_in.grant(game, player, day)
  local amount = _grant_amount(day)
  if amount == nil or game == nil or player == nil then
    return false
  end
  game:add_player_cash(player, amount)
  return true
end

-- Boundary adapter: map a host reward event to a coin grant for the claiming
-- player. Unconfigured events grant nothing.
function sign_in.claim(game, event_name, player)
  local day = sign_in.day_from_event(event_name)
  if day == nil then
    return false
  end
  return sign_in.grant(game, player, day)
end

-- Subscribe RewardDay1..7 to the host custom-event port and credit the claiming
-- player when a day is claimed. Dependencies are injected so this stays testable;
-- the only untestable thin slice is `register_event` (the host LuaAPI call):
--   register_event(name, handler)  -- handler is invoked by the host as (_, _, data)
--   get_game()                     -- the live game, or nil before one exists
--   resolve_role_id(data)          -- the claiming player's role id from the payload
local function _find_player_by_role_id(game, role_id)
  if role_id ~= nil and type(game.find_player_by_id) == "function" then
    return game:find_player_by_id(role_id) or nil
  end
  return nil
end

local function _day_claimed_handler(get_game, resolve_role_id, after_grant, day)
  return function(_, _, data)
    local game = get_game()
    if game == nil then
      return
    end
    local role_id = resolve_role_id(data)
    local player = _find_player_by_role_id(game, role_id)
    if sign_in.grant(game, player, day) and type(after_grant) == "function" then
      after_grant(game, player, day)
    end
  end
end

function sign_in.install(deps)
  assert(type(deps) == "table", "missing sign_in install deps")
  local register_event = assert(deps.register_event, "missing register_event")
  local get_game = assert(deps.get_game, "missing get_game")
  local resolve_role_id = assert(deps.resolve_role_id, "missing resolve_role_id")
  local after_grant = deps.after_grant
  for day = 1, #rewards do
    register_event(EVENT_PREFIX .. day, _day_claimed_handler(get_game, resolve_role_id, after_grant, day))
  end
end

return sign_in

