-- 签到奖励 UI 刷新接线(自 host_install.lua 拆分,>100 mutation sites 行为保持):
-- 宿主 RewardDay1..7 事件→金币发放→奖励 UI 脏刷新。game/app state 只存在
-- bootstrap 之后,由装配侧注入惰性访问器,事件触发时解析。
local sign_in = require("src.app.host_integrations.sign_in")
local host_runtime = require("src.host.init")
-- #332:身份解析走契约接缝(实现由装配侧 host_install 配置)。
local resolver_seam = require("src.ui.seams.local_actor_resolver")

local sign_in_rewards = {}

local function _loop_ports(state)
  return state and (state._resolved_gameplay_loop_ports or state.gameplay_loop_ports) or nil
end

local function _ui_sync_of(ports)
  return type(ports) == "table" and ports.ui_sync or nil
end

local function _refreshable(ui_sync)
  return type(ui_sync) == "table" and type(ui_sync.refresh_from_dirty) == "function"
end

local function _resolve_ui_sync_ports(state)
  local ui_sync = _ui_sync_of(_loop_ports(state))
  if not _refreshable(ui_sync) then
    return nil
  end
  return ui_sync
end

local function _refresh_sign_in_reward_ui(game, state)
  if game == nil or state == nil or type(game.consume_dirty) ~= "function" then
    return false
  end
  local ui_sync = _resolve_ui_sync_ports(state)
  if ui_sync == nil then
    return false
  end
  local dirty = game:consume_dirty()
  return ui_sync.refresh_from_dirty(game, state, dirty)
end

-- Subscribe the host's RewardDay1..7 sign-in events to coin grants. The game and
-- app state only exist after bootstrap, so app/init injects lazy accessors that
-- resolve at event-fire time; without them (e.g. context-only test installs) the
-- wiring is skipped. The claiming player is resolved from the event payload via
-- the shared local-actor resolver (payload.role, then client/local fallback).
function sign_in_rewards.install(opts)
  local get_current_game = opts.get_current_game
  local get_app_state = opts.get_app_state
  if type(get_current_game) ~= "function" or type(get_app_state) ~= "function" then
    return
  end
  sign_in.install({
    register_event = host_runtime.register_custom_event,
    get_game = get_current_game,
    resolve_role_id = function(data)
      return resolver_seam.resolve_from_event(get_app_state(), data)
    end,
    after_grant = function(game)
      return _refresh_sign_in_reward_ui(game, get_app_state())
    end,
  })
end

return sign_in_rewards

