require("test.bootstrap").install_package_paths()
-- busted injects luassert fields on assert.
-- luacheck: ignore 143
local luassert = assert
local function _assert_identity(actual, expected, message)
  luassert.is.equal(expected, actual, message)
end
local support = require("test.support.shared_support")
local fixtures = require("test.support.gameplay_fixtures")
local _config_reset = require("test.support.config_reset")

local function _run_market_modal_race_case(game_opts, expect_open, case_name)
  local game = support.new_game(game_opts)
  local state = fixtures.build_loop_state()
  support.prepare_board_scene(state, game)
  support.bind_ui_runtime(state)

  support.open_choice(game, {
    kind = "market_buy",
    route_key = "market",
    title = "黑市",
    options = { { id = 1, label = "购买" } },
  })

  local modal = require("src.ui.coord.modal")
  local called = false

  support.with_patches({
    {
      target = require("src.ui.coord.ui_runtime"),
      key = "render",
      value = function()
      end,
    },
    {
      target = modal,
      key = "open_choice_modal",
      value = function(...)
        called = true
      end,
    },
    -- 本地身份经 client_role 表达(#341);「上一次点击者缓存」已随 #601 整体退役。
    {
      target = require("src.ui.render.support.runtime_ui"),
      key = "get_client_role",
      value = function()
        return { get_roleid = function() return game.players[1].id end }
      end,
    },
    -- owner 落在房间席位名册内,门控才放行(#444)。单字段 patch 而非
    -- runtime_ports.configure:后者整表替换,会清空同表其他端口。
    {
      target = require("src.foundation.ports.runtime_ports"),
      key = "resolve_roles",
      value = function()
        return { { get_roleid = function() return game.players[1].id end } }
      end,
    },
  }, function()
    local ui_model_sync = require("src.ui.ports.ui_sync")._model
    local common = {
      log_once = {},
      build_log_prefix = function()
        return ""
      end,
    }
    ui_model_sync.refresh_from_dirty(game, state, { any = true, ui = true }, common)
  end)

  if expect_open then
    luassert.is_true(called, case_name)
  else
    luassert.is_false(called, case_name)
  end
end

describe("TestAutoPlayerMarketModalRace", function()
  before_each(function()
    _config_reset.reset_all()
  end)

-- 无 tearDown:席位名册经 with_patches 单字段 patch 铺设,出入两侧自动还原。

local function _test_auto_player_does_not_open_market_modal()
  _run_market_modal_race_case({ players = { "P1", "P2" }, auto_all = true }, false, "modal must NOT open for auto player")
end

local function _test_ai_player_does_not_open_market_modal()
  _run_market_modal_race_case({ players = { "P1", "P2" }, ai = { [1] = true } }, false, "modal must NOT open for AI player")
end

local function _test_local_human_player_does_open_market_modal()
  _run_market_modal_race_case({ players = { "P1", "P2" } }, true, "modal MUST open for local human player")
end

local function _test_market_navigation_dirty_forces_modal_refresh()
  local game = support.new_game({ players = { "P1", "P2" } })
  local state = fixtures.build_loop_state()
  support.prepare_board_scene(state, game)
  support.bind_ui_runtime(state)

  support.open_choice(game, {
    kind = "market_buy",
    route_key = "market",
    title = "黑市",
    options = { { id = 1, label = "购买" } },
  })
  state.ui.market_active = true

  local modal = require("src.ui.coord.modal")
  local call_count = 0

  support.with_patches({
    {
      target = require("src.ui.coord.ui_runtime"),
      key = "render",
      value = function() end,
    },
    {
      target = modal,
      key = "open_choice_modal",
      value = function() call_count = call_count + 1 end,
    },
  }, function()
    local ui_model_sync = require("src.ui.ports.ui_sync")._model
    local common = {
      log_once = {},
      build_log_prefix = function() return "" end,
    }
    -- 不带 dirty.market：market 已开 + should_reconcile 短路 → 不应再开
    ui_model_sync.refresh_from_dirty(game, state, { any = true, ui = true }, common)
    _assert_identity(call_count, 0,
      "should NOT reopen market modal when market_active=true and dirty.market is unset")
    -- 带 dirty.market：navigation 改写了 options，必须强制 reconcile
    ui_model_sync.refresh_from_dirty(game, state, { any = true, ui = true, market = true }, common)
    _assert_identity(call_count, 1,
      "MUST reopen market modal when dirty.market=true even if market_active=true")
  end)
end

-- #583 复跑器:指定黑市/弹窗态下喂 dirty.market,返回 open_choice_modal 调用数。
local function _run_dirty_market_reopen(popup_active, market_active, popup_exclude_role_id)
  local game = support.new_game({ players = { "P1", "P2" } })
  local state = fixtures.build_loop_state()
  support.prepare_board_scene(state, game)
  support.bind_ui_runtime(state)

  support.open_choice(game, {
    kind = "market_buy",
    route_key = "market",
    title = "黑市",
    options = { { id = 1, label = "购买" } },
  })
  state.ui.market_active = market_active
  state.ui.popup_active = popup_active
  state.ui.popup_exclude_role_id = popup_exclude_role_id

  local modal = require("src.ui.coord.modal")
  local call_count = 0

  support.with_patches({
    {
      target = require("src.ui.coord.ui_runtime"),
      key = "render",
      value = function() end,
    },
    {
      target = modal,
      key = "open_choice_modal",
      value = function() call_count = call_count + 1 end,
    },
  }, function()
    local ui_model_sync = require("src.ui.ports.ui_sync")._model
    local common = {
      log_once = {},
      build_log_prefix = function() return "" end,
    }
    ui_model_sync.refresh_from_dirty(game, state, { any = true, ui = true, market = true }, common)
  end)
  return call_count
end

-- #583:黑市购买后「卡牌展示屏」广播弹窗与 dirty.market 重建竞争——弹窗存活期
-- 跳过重建;收屏回屏按关闭时刻 market_active 把买家带回黑市屏,无需补发。
local function _test_market_dirty_reopen_skipped_while_popup_active()
  _assert_identity(_run_dirty_market_reopen(true, true), 0,
    "dirty.market rebuild must be skipped while a popup is alive (popup close returns buyer to market)")
end

-- 弹窗门只拦「重建」:无弹窗时 dirty.market 仍强制重开(与上例同路径的对照钉)。
local function _test_market_dirty_reopen_runs_without_popup()
  _assert_identity(_run_dirty_market_reopen(false, true), 1,
    "dirty.market rebuild must still run when no popup is alive")
end

-- 弹窗门只拦「已开黑市的重建」:黑市未开(market_active=false,机会卡传送流)
-- 时弹窗存活不挡首开——否则收屏回屏解析不到 market_active,黑市永不补开。
local function _test_market_dirty_first_open_not_blocked_by_popup()
  _assert_identity(_run_dirty_market_reopen(true, false), 1,
    "dirty.market first open during popup must proceed when market is not active yet")
end

-- 2026-08-25 买家免展示口径:存活弹窗排除买家本人时(黑市购买展示不占买家屏),
-- dirty.market 重建照常放行——买家即时看到成交后的刷新,不必等收屏。
local function _test_market_dirty_reopen_runs_when_popup_excludes_operator()
  _assert_identity(_run_dirty_market_reopen(true, true, 1), 1,
    "dirty.market rebuild must run when the alive popup excludes the market operator")
end


it("test_auto_player_does_not_open_market_modal", _test_auto_player_does_not_open_market_modal)
it("test_ai_player_does_not_open_market_modal", _test_ai_player_does_not_open_market_modal)
it("test_local_human_player_does_open_market_modal", _test_local_human_player_does_open_market_modal)
it("test_market_navigation_dirty_forces_modal_refresh", _test_market_navigation_dirty_forces_modal_refresh)
it("test_market_dirty_reopen_skipped_while_popup_active", _test_market_dirty_reopen_skipped_while_popup_active)
it("test_market_dirty_reopen_runs_without_popup", _test_market_dirty_reopen_runs_without_popup)
it("test_market_dirty_first_open_not_blocked_by_popup", _test_market_dirty_first_open_not_blocked_by_popup)
it("test_market_dirty_reopen_runs_when_popup_excludes_operator", _test_market_dirty_reopen_runs_when_popup_excludes_operator)
end)
