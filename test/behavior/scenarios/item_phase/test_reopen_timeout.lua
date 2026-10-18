-- 回归:道具窗口倒计时不得跨「用卡续开」累计(修复前 2 查税 + 1 财神后
-- 累计超过 action_timeout_seconds,最后一张查税的窗口被立即超时关闭)。
-- 语义:成功用卡后续开刷新倒计时;followup 取消(返回)路径仍保留累计防挂机。
require("test.bootstrap").install_package_paths()
-- busted injects luassert fields on assert.
-- luacheck: ignore 143
local luassert = assert
local function _assert_equal(actual, expected, message)
  luassert.is.equal(expected, actual, message)
end
local support = require("test.support.shared_support")
local item_phase = require("src.rules.items.phase")
local item_ids = require("src.config.gameplay.item_ids")
local choice_resolver = require("src.rules.choice.resolver")
local runtime_state = require("src.state.runtime")
local ChoiceTimeout = require("src.turn.waits.choice_timeout")

local map_cfg = require("src.config.content.default_map")
local tiles_cfg = require("src.config.content.tiles")

local function _new_game()
  return support.new_game({
    players = { "P1", "P2", "P3" },
    ai = {},
    map = map_cfg,
    tiles = tiles_cfg,
  })
end

local function _choice_has_option(choice, option_id)
  for _, option in ipairs(choice and choice.options or {}) do
    if option.id == option_id then
      return true
    end
  end
  return false
end

-- 复刻 app/event_bridge 的 need_choice 播种(spec 不装完整 UI 桥):
-- open_choice 的 opts.elapsed_seconds 落进 runtime state 的窗口计时。
local function _install_choice_seed_bridge(game, state)
  local port = assert(game.intent_output_port, "missing intent_output_port")
  local real_open = port.open_choice
  port.open_choice = function(self, spec, opts)
    local entry = real_open(self, spec, opts)
    runtime_state.set_pending_choice(state, entry, {
      choice_id = entry.id,
      elapsed_seconds = opts and opts.elapsed_seconds or 0,
    })
    return entry
  end
end

describe("TestGameplayItemPhaseReopenTimeout", function()
  it("test_window_reopened_by_active_card_use_gets_fresh_countdown", function()
  local g = _new_game()
  local player = g:current_player()
  player.inventory:add({ id = item_ids.tax })
  player.inventory:add({ id = item_ids.tax })
  player.inventory:add({ id = item_ids.tax })
  player.inventory:add({ id = item_ids.rich })

  local state = require("test.support.gameplay_fixtures").build_loop_state()
  runtime_state.ensure_all(state)
  _install_choice_seed_bridge(g, state)
  local session = { wait_state = "wait_choice", game = g, choice_elapsed_seconds = 0 }

  local function _tick(dt)
    session.choice_elapsed_seconds = session.choice_elapsed_seconds + dt
    g.turn.choice_elapsed_seconds = session.choice_elapsed_seconds
    ChoiceTimeout.step_default(g, state, dt)
  end

  item_phase.run({ game = g }, "pre_action", {
    player = player,
    next_state = "roll",
    next_args = { player = player },
  })
  runtime_state.set_pending_choice(state, g.turn.pending_choice, {
    choice_id = g.turn.pending_choice.id, elapsed_seconds = 0,
  })

  local function _use_tax(think_card, think_target)
    _tick(think_card)
    local pending = assert(g.turn.pending_choice, "passive window should be open")
    _assert_equal(pending.kind, "item_phase_passive",
      "expected passive window, got " .. tostring(pending.kind))
    luassert.truthy(_choice_has_option(pending, item_ids.tax), "tax should be selectable")
    choice_resolver.resolve(g, pending, { option_id = item_ids.tax })
    local followup = assert(g.turn.pending_choice, "tax should open target choice")
    _tick(think_target)
    choice_resolver.resolve(g, followup, { option_id = followup.options[1].id })
  end

  -- 玩家正常操作节奏:单个窗口都远未到 15s 超时,但全程累计会超
  _use_tax(4.0, 3.0)
  _use_tax(3.0, 2.0)
  _tick(0.5)
  local pending = assert(g.turn.pending_choice, "passive should reopen after two tax uses")
  _assert_equal(pending.kind, "item_phase_passive", "expected passive window after two tax uses")
  choice_resolver.resolve(g, pending, { option_id = item_ids.rich })

  local reopened = assert(g.turn.pending_choice, "passive should reopen after rich use")
  _assert_equal(reopened.kind, "item_phase_passive", "reopened window should be passive")
  luassert.truthy(_choice_has_option(reopened, item_ids.tax), "last tax should be listed")
  local reopened_id = reopened.id

  -- 该窗口自身只显示了 3s,不得被跨窗口累计的计时超时关闭
  _tick(3.0)
  local still_open = g.turn.pending_choice
  luassert.truthy(still_open ~= nil and still_open.id == reopened_id,
    "reopened item window must not time out from cross-window accumulated elapsed; " ..
    "last tax card would be locked out until end of turn")
  luassert.truthy(_choice_has_option(still_open, item_ids.tax), "last tax should remain selectable")
  end)
end)
