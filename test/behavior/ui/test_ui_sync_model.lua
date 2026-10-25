-- luacheck: ignore 143
require("test.bootstrap").install_package_paths()
local luassert = assert
local model_sync = require("src.ui.ports.ui_sync")._model
local runtime_state = require("src.ui.state.runtime")
local turn_ui_sync_shared = require("src.state.ui_sync_shared")
local landing_visual_hold = require("src.ui.visual_hold")
local main_view = require("src.ui.coord.ui_runtime")
local view_model = require("src.ui.view")
local modal = require("src.ui.coord.modal")
local choice_ui_state = require("src.ui.ports.ui_sync")._choice_state
local support = require("test.support.shared_support")
local _with_shared_patches = support.with_patches
local _build_choice_modal_state = support.build_choice_modal_state
local input_lock_phases = require("test.support.input_lock_phases")

local function _with_patches(patches, fn)
  local old = {}
  for i, patch in ipairs(patches) do
    old[i] = patch[1][patch[2]]
    patch[1][patch[2]] = patch[3]
  end
  local ok, err = pcall(fn)
  for i = #patches, 1, -1 do
    patches[i][1][patches[i][2]] = old[i]
  end
  if not ok then
    error(err)
  end
end

local function _game(phase)
  return {
    turn = { phase = phase or "wait_choice", current_player_index = 1 },
    players = { { id = 1, name = "P1", cash = 100 } },
  }
end

local function _common()
  return {
    log_once = function() end,
    build_log_prefix = function() return "test" end,
  }
end

local function _seed_choice_selection(state, option_id)
  state.ui_runtime.choice_visible_option_ids = { option_id }
  state.ui_runtime.pending_choice_selected_option_id = option_id
end

describe("TestUiSyncModel", function()

it("test_refresh_feeds_the_seeded_model_to_view_update", function()
  -- L32 `runtime_state.get_ui_model(state)` 换 nil:已播种的模型必须原样
  -- 交给 view_model.update,变异体传 nil 走 build 全新建模。
  local state = { ui = {} }
  local game = _game()
  runtime_state.set_ui_dirty(state, true)
  -- update 被桩:prev 只做恒等比对,种子模型无需完备。
  local seeded = { seeded_marker = true }
  runtime_state.set_ui_model(state, seeded)
  local captured_prev = "unset"
  local dirty = { any = true, ui = false }

  _with_patches({
    { landing_visual_hold, "sync_state_from_game", function() end },
    { landing_visual_hold, "should_defer", function() return false end },
    { turn_ui_sync_shared, "build_ui_env", function()
      return {}
    end },
    { turn_ui_sync_shared, "is_only_turn_countdown", function()
      return false
    end },
    { view_model, "update", function(prev, _, update_env, update_dirty)
      captured_prev = prev
      return { panel = {} }
    end },
    { main_view, "render", function() end },
    { modal, "open_choice_modal", function() end },
    { modal, "close_choice_modal", function() end },
  }, function()
    local result = model_sync.refresh_from_dirty(game, state, dirty, _common())
    luassert.is.same( true,result, "dirty refresh should render")
    luassert.is.same( seeded,captured_prev, "view update must receive the seeded model as prev")
  end)
end)

it("test_turn_label_falls_back_to_empty_string", function()
  -- L45 `panel and panel.turn_label or ""` 的 `""` 换 nil:无 turn_label 时
  -- 刷新标签必须传空串,不能传 nil。
  local state = { ui = {} }
  local game = _game()
  runtime_state.set_ui_dirty(state, true)
  local captured_label = "unset"
  local dirty = { any = true, ui = false }

  _with_patches({
    { landing_visual_hold, "sync_state_from_game", function() end },
    { landing_visual_hold, "should_defer", function() return false end },
    { turn_ui_sync_shared, "build_ui_env", function()
      return {}
    end },
    { turn_ui_sync_shared, "is_only_turn_countdown", function()
      return true
    end },
    { view_model, "update", function()
      return { panel = { countdown_visible = false } }
    end },
    { main_view, "refresh_turn_label", function(_, label, countdown_visible)
      captured_label = label
      luassert.is.same( false,countdown_visible, "countdown visibility should pass through")
    end },
  }, function()
    local result = model_sync.refresh_from_dirty(game, state, dirty, _common())
    luassert.is.same( false,result, "only-countdown refresh should not render full UI")
    luassert.is.same( "",captured_label, "missing turn label must fall back to empty string")
  end)
end)


it("test_refreshes_when_runtime_ui_dirty_marks_the_dirty_bucket", function()
  local state = { ui = {} }
  local dirty = { any = false, ui = false }
  local env = { source = "test-env" }
  local rendered_model = nil
  runtime_state.set_ui_dirty(state, true)

  _with_patches({
    { landing_visual_hold, "sync_state_from_game", function() end },
    { landing_visual_hold, "should_defer", function() return false end },
    { turn_ui_sync_shared, "build_ui_env", function()
      return env
    end },
    { turn_ui_sync_shared, "is_only_turn_countdown", function()
      return false
    end },
    { view_model, "update", function(_, _, update_env, update_dirty)
      luassert.is.same( env,update_env, "refresh should pass the built env to view model")
      luassert.is.same( true,update_dirty.ui, "runtime UI dirty should mark dirty.ui")
      return { panel = { turn_label = "P1", countdown_visible = true } }
    end },
    { main_view, "render", function(_, next_model)
      rendered_model = next_model
    end },
    { modal, "open_choice_modal", function()
      error("no choice should not open a modal")
    end },
    { modal, "close_choice_modal", function()
      error("no active choice should not close a modal")
    end },
  }, function()
    local result = model_sync.refresh_from_dirty(_game(), state, dirty, _common())

    luassert.is.same( true,result, "dirty UI refresh should render full UI")
    luassert.is.same( true,dirty.ui, "dirty bucket should retain the UI mark for this refresh")
    luassert.is.same( false,runtime_state.is_ui_dirty(state), "runtime UI dirty flag should be cleared")
    luassert.is_not_nil(rendered_model, "refresh should render the new model")
  end)
end)

it("test_defers_refresh_while_landing_visual_hold_is_active", function()
  local state = { ui = {} }
  local dirty = { any = true, ui = false, turn = true }
  local frozen = false
  local deferred_dirty = nil

  _with_patches({
    { landing_visual_hold, "sync_state_from_game", function() end },
    { landing_visual_hold, "should_defer", function()
      return true
    end },
    { landing_visual_hold, "freeze_active_ui", function()
      frozen = true
    end },
    { landing_visual_hold, "defer_dirty", function(_, next_dirty)
      deferred_dirty = next_dirty
    end },
    { view_model, "update", function()
      error("deferred refresh should not update the UI model")
    end },
    { main_view, "render", function()
      error("deferred refresh should not render")
    end },
  }, function()
    local result = model_sync.refresh_from_dirty(_game(), state, dirty, _common())

    luassert.is.same( false,result, "deferred refresh should report no render")
    luassert.is.same( true,frozen, "active UI should be frozen")
    luassert.is.same( dirty,deferred_dirty, "dirty bucket should be deferred")
  end)
end)

it("test_opens_inline_choices_only_outside_input_blocked_phases", function()
  local state, _, query_nodes = _build_choice_modal_state()

  _with_shared_patches({
    { target = landing_visual_hold, key = "sync_state_from_game", value = function() end },
    { target = landing_visual_hold, key = "should_defer", value = function() return false end },
    { target = turn_ui_sync_shared, key = "is_only_turn_countdown", value = function() return false end },
    { target = view_model, key = "update", value = function()
      return {
        panel = {},
        choice = { id = "inline", route_key = "base_inline" },
      }
    end },
    { target = main_view, key = "render", value = function() end },
    { key = "UIManager", value = { query_nodes_by_name = query_nodes } },
    { key = "all_roles", value = nil },
  }, function()
    _seed_choice_selection(state, "allowed-inline")
    luassert.is.same(true, model_sync.refresh_from_dirty(_game("wait_choice"), state, { any = true }, _common()))
    luassert.is_nil(state.ui_runtime.choice_visible_option_ids,
      "allowed inline choice should reset stale public option ids")
    luassert.is_nil(state.ui_runtime.pending_choice_selected_option_id,
      "allowed inline choice should reset the stale public selection")
    luassert.is.same(false, state.ui.choice_active, "inline choice should stay on the base screen")
    luassert.is_nil(state.ui.active_choice_screen_key, "inline choice should not activate a modal screen")

    _seed_choice_selection(state, "blocked-inline")
    luassert.is.same(true, model_sync.refresh_from_dirty(_game("wait_move_anim"), state, { any = true }, _common()))
    luassert.is.same({ "blocked-inline" }, state.ui_runtime.choice_visible_option_ids,
      "input-blocked phase should leave public option ids untouched")
    luassert.is.same("blocked-inline", state.ui_runtime.pending_choice_selected_option_id,
      "input-blocked phase should leave the public selection untouched")
    luassert.is.same(false, state.ui.choice_active, "input-blocked phase should not activate a choice screen")
    luassert.is_nil(state.ui.active_choice_screen_key, "input-blocked phase should not activate a modal route")
  end)
end)

-- #211:开屏门控逐相位覆盖锁输入集合——锁定相位不接管内联选择,放行相位接管。
it("test_inline_choice_open_follows_every_input_lock_phase", function()
  local state, _, query_nodes = _build_choice_modal_state()

  _with_shared_patches({
    { target = landing_visual_hold, key = "sync_state_from_game", value = function() end },
    { target = landing_visual_hold, key = "should_defer", value = function() return false end },
    { target = turn_ui_sync_shared, key = "is_only_turn_countdown", value = function() return false end },
    { target = view_model, key = "update", value = function()
      return { panel = {}, choice = { id = "inline", route_key = "base_inline" } }
    end },
    { target = main_view, key = "render", value = function() end },
    { key = "UIManager", value = { query_nodes_by_name = query_nodes } },
    { key = "all_roles", value = nil },
  }, function()
    for _, phase in ipairs(input_lock_phases.locked) do
      _seed_choice_selection(state, "stale")
      model_sync.refresh_from_dirty(_game(phase), state, { any = true }, _common())
      luassert.is.same("stale", state.ui_runtime.pending_choice_selected_option_id,
        phase .. " should lock input and leave the inline choice closed")
    end
    for _, phase in ipairs(input_lock_phases.unlocked) do
      _seed_choice_selection(state, "stale")
      model_sync.refresh_from_dirty(_game(phase), state, { any = true }, _common())
      luassert.is_nil(state.ui_runtime.pending_choice_selected_option_id,
        phase .. " should allow input and open the inline choice")
    end
  end)
end)

it("test_opens_passive_item_choices_as_inline_choices", function()
  local state, nodes, query_nodes = _build_choice_modal_state()
  state.ui.market_active = true
  nodes["黑市屏"].visible = true
  _seed_choice_selection(state, "stale-market")

  _with_shared_patches({
    { target = landing_visual_hold, key = "sync_state_from_game", value = function() end },
    { target = landing_visual_hold, key = "should_defer", value = function() return false end },
    { target = turn_ui_sync_shared, key = "is_only_turn_countdown", value = function() return false end },
    { target = view_model, key = "update", value = function()
      return {
        panel = {},
        choice = { id = "passive", route_key = "item_phase_passive" },
      }
    end },
    { target = main_view, key = "render", value = function() end },
    { key = "UIManager", value = { query_nodes_by_name = query_nodes } },
    { key = "all_roles", value = nil },
  }, function()
    local result = model_sync.refresh_from_dirty(_game("wait_choice"), state, { any = true }, _common())

    luassert.is.same(true, result, "passive choice refresh should render")
    luassert.is.same(false, state.ui.market_active,
      "item_phase_passive should take over from the market through its inline handler")
    luassert.is.same(false, nodes["黑市屏"].visible,
      "item_phase_passive should hide the previous market canvas")
    luassert.is_nil(state.ui_runtime.choice_visible_option_ids,
      "item_phase_passive takeover should clear stale market option ids")
    luassert.is_nil(state.ui_runtime.pending_choice_selected_option_id,
      "item_phase_passive takeover should clear the stale market selection")
    luassert.is.same(false, state.ui.choice_active, "passive item choice should not open a modal choice screen")
    luassert.is_nil(state.ui.active_choice_screen_key, "passive item choice should stay on the base screen")
  end)
end)

it("test_does_not_open_market_choice_without_market_payload", function()
  local state = { ui = {} }

  _with_patches({
    { landing_visual_hold, "sync_state_from_game", function() end },
    { landing_visual_hold, "should_defer", function() return false end },
    { turn_ui_sync_shared, "is_only_turn_countdown", function() return false end },
    { view_model, "update", function()
      return {
        panel = {},
        choice = { id = "market", route_key = "market" },
        market = nil,
      }
    end },
    { main_view, "render", function() end },
    { modal, "open_choice_modal", function()
      error("market choice without market payload should not open")
    end },
  }, function()
    luassert.is.same( true,model_sync.refresh_from_dirty(_game("wait_choice"), state, { any = true, market = true }, _common()))
  end)
end)

it("test_opens_non_inline_choices_when_reconcile_requires_it", function()
  local state, nodes, query_nodes = _build_choice_modal_state()
  _seed_choice_selection(state, "stale-target")

  _with_shared_patches({
    { target = landing_visual_hold, key = "sync_state_from_game", value = function() end },
    { target = landing_visual_hold, key = "should_defer", value = function() return false end },
    { target = turn_ui_sync_shared, key = "is_only_turn_countdown", value = function() return false end },
    { target = view_model, key = "update", value = function()
      return {
        panel = {},
        choice = {
          id = "target",
          route_key = "target",
          options = { { id = "target-option", label = "目标" } },
        },
      }
    end },
    { target = choice_ui_state, key = "should_reconcile", value = function()
      return true
    end },
    { target = main_view, key = "render", value = function() end },
    { key = "UIManager", value = { query_nodes_by_name = query_nodes } },
    { key = "all_roles", value = nil },
  }, function()
    local result = model_sync.refresh_from_dirty(_game("wait_choice"), state, { any = true }, _common())

    luassert.is.same(true, result, "target choice refresh should render")
    luassert.is.same(true, state.ui.choice_active, "reconciled target choice should activate its public screen state")
    luassert.is.same("target", state.ui.active_choice_screen_key,
      "reconciled target choice should publish the target route")
    luassert.is.same(true, nodes["位置选择屏"].visible, "reconciled target choice should show the target canvas")
    luassert.is.same("target", state.ui_runtime.pending_choice_id,
      "reconciled target choice should publish its pending choice id")
    luassert.is.same({ "target-option" }, state.ui_runtime.choice_visible_option_ids,
      "reconciled target choice should replace stale public option ids")
    luassert.is.same("target-option", state.ui_runtime.pending_choice_selected_option_id,
      "reconciled target choice should publish its default selection")
    luassert.is.same(false, state.ui.market_active, "target choice should not activate the market")
  end)
end)

it("test_build_model_forwards_the_ui_env_to_view_model_build", function()
  local state = { ui = {} }
  local game = _game()
  local env = { source = "build-env" }
  local built_model = { panel = {} }

  _with_patches({
    { turn_ui_sync_shared, "build_ui_env", function(build_state, build_game)
      luassert.is.same( state,build_state, "build_model should pass state to env builder")
      luassert.is.same( game,build_game, "build_model should pass game to env builder")
      return env
    end },
    { view_model, "build", function(build_game, build_env)
      luassert.is.same( game,build_game, "build_model should pass game to view model")
      luassert.is.same( env,build_env, "build_model should pass env to view model")
      return built_model
    end },
  }, function()
    luassert.is.same( built_model,model_sync.build_model(state, game))
  end)
end)

it("test_closes_stale_choice_modal_when_the_refreshed_model_has_no_choice", function()
  local state, nodes, query_nodes = _build_choice_modal_state()
  state.ui.choice_active = true
  state.ui.active_choice_screen_key = "target"
  nodes["位置选择屏"].visible = true
  _seed_choice_selection(state, "stale-choice")

  _with_shared_patches({
    { target = landing_visual_hold, key = "sync_state_from_game", value = function() end },
    { target = landing_visual_hold, key = "should_defer", value = function() return false end },
    { target = turn_ui_sync_shared, key = "is_only_turn_countdown", value = function() return false end },
    { target = view_model, key = "update", value = function()
      return { panel = {} }
    end },
    { target = main_view, key = "render", value = function() end },
    { key = "UIManager", value = { query_nodes_by_name = query_nodes } },
    { key = "all_roles", value = nil },
  }, function()
    local result = model_sync.refresh_from_dirty(_game(), state, { any = true }, _common())

    luassert.is.same(true, result, "full refresh should still report a render")
    luassert.is.same(false, state.ui.choice_active, "stale active choice should be deactivated")
    luassert.is_nil(state.ui.active_choice_screen_key, "stale active choice route should be cleared")
    luassert.is.same(false, nodes["位置选择屏"].visible, "stale active choice canvas should be hidden")
    luassert.is_nil(state.ui_runtime.choice_visible_option_ids,
      "stale active choice should clear public option ids")
    luassert.is_nil(state.ui_runtime.pending_choice_selected_option_id,
      "stale active choice should clear the public selection")
  end)
end)

it("test_reopens_a_pending_choice_from_the_cached_model_without_rebuilding", function()
  local state, nodes, query_nodes = _build_choice_modal_state()
  local pending = {
    id = "pending",
    route_key = "target",
    options = { { id = "pending-option", label = "待选目标" } },
  }
  local cached_model = { choice = pending, market = { id = "market" } }
  runtime_state.set_ui_model(state, cached_model)

  _with_shared_patches({
    { target = choice_ui_state, key = "should_reconcile", value = function()
      return true
    end },
    { target = view_model, key = "build", value = function()
      error("matching cached pending choice should not rebuild")
    end },
    { key = "UIManager", value = { query_nodes_by_name = query_nodes } },
    { key = "all_roles", value = nil },
  }, function()
    local result = model_sync.reopen_choice_modal_if_needed(_game(), state, pending)

    luassert.is.same(true, result, "reconciled pending choice should reopen")
    luassert.is.equal(cached_model, runtime_state.get_ui_model(state),
      "reopen should retain the cached model instead of replacing it")
    luassert.is.same(true, state.ui.choice_active, "cached pending choice should activate its public screen state")
    luassert.is.same("target", state.ui.active_choice_screen_key,
      "cached pending choice should reopen the target route")
    luassert.is.same(true, nodes["位置选择屏"].visible, "cached pending choice should show the target canvas")
    luassert.is.same("pending", state.ui_runtime.pending_choice_id,
      "cached pending choice should publish its pending id")
    luassert.is.same({ "pending-option" }, state.ui_runtime.choice_visible_option_ids,
      "cached pending choice should publish its cached options")
    luassert.is.same("pending-option", state.ui_runtime.pending_choice_selected_option_id,
      "cached pending choice should publish its default selection")
    luassert.is.same(false, state.ui.market_active, "cached target choice should not be rerouted to the market")
  end)
end)

it("test_does_not_reopen_when_reconcile_says_the_ui_is_already_current", function()
  local state = { ui = {} }

  _with_patches({
    { choice_ui_state, "should_reconcile", function()
      return false
    end },
    { modal, "open_choice_modal", function()
      error("already-current UI should not reopen")
    end },
  }, function()
    luassert.is.same( false,model_sync.reopen_choice_modal_if_needed(_game(), state, { id = "pending" }))
  end)
end)

it("test_does_not_reopen_when_rebuilt_model_has_no_choice", function()
  local state = { ui = {} }

  _with_patches({
    { choice_ui_state, "should_reconcile", function()
      return true
    end },
    { view_model, "build", function()
      return { market = { id = "market" } }
    end },
    { modal, "open_choice_modal", function()
      error("model without choice should not reopen")
    end },
  }, function()
    luassert.is.same( false,model_sync.reopen_choice_modal_if_needed(_game(), state, { id = "pending" }))
  end)
end)

it("test_release_frame_opens_choice_modal_before_render", function()
  -- #525 时序 pin:阻塞期创建的窗口在放行帧首开。若 render 先跑,读到陈旧
  -- choice_active=false,post-action 可选窗口会把基础「结束」按钮点得与弹窗
  -- 同屏亮。开屏必须先于 main_view.render,让渲染读到开屏后的门控。
  local state = { ui = { choice_active = false } }
  local order = {}

  _with_patches({
    { landing_visual_hold, "sync_state_from_game", function() end },
    { landing_visual_hold, "should_defer", function() return false end },
    { turn_ui_sync_shared, "is_only_turn_countdown", function() return false end },
    { view_model, "update", function()
      return {
        panel = {},
        choice = { id = "landing", route_key = "secondary_confirm" },
      }
    end },
    { choice_ui_state, "should_reconcile", function()
      return true
    end },
    { modal, "open_choice_modal", function()
      state.ui.choice_active = true -- 真实开屏会置门控为 true
      table.insert(order, "open")
    end },
    { main_view, "render", function()
      table.insert(order, "render")
      luassert.is.same( true,state.ui.choice_active,
        "render must observe choice_active after the modal opened")
    end },
  }, function()
    local result = model_sync.refresh_from_dirty(_game("wait_choice"), state, { any = true }, _common())

    luassert.is.same( true,result, "release frame refresh should render")
    luassert.is.same( { "open", "render" },order, "modal open must precede render")
  end)
end)

it("test_release_frame_closes_choice_modal_before_render", function()
  -- #525 时序 pin(收屏侧):窗口 resolve 后模型无 choice,收屏必须先于
  -- main_view.render,否则渲染读到陈旧 choice_active=true,基础按钮整门
  -- 持续落下,答完弹窗后行动/结束按钮不回。
  local state = { ui = { choice_active = true, active_choice_screen_key = "secondary_confirm" } }
  local order = {}

  _with_patches({
    { landing_visual_hold, "sync_state_from_game", function() end },
    { landing_visual_hold, "should_defer", function() return false end },
    { turn_ui_sync_shared, "is_only_turn_countdown", function() return false end },
    { view_model, "update", function()
      return { panel = {} }
    end },
    { modal, "close_choice_modal", function()
      state.ui.choice_active = false -- 真实收屏会置门控为 false
      table.insert(order, "close")
    end },
    { main_view, "render", function()
      table.insert(order, "render")
      luassert.is.same( false,state.ui.choice_active,
        "render must observe choice_active after the modal closed")
    end },
  }, function()
    local result = model_sync.refresh_from_dirty(_game("wait_choice"), state, { any = true }, _common())

    luassert.is.same( true,result, "release frame refresh should render")
    luassert.is.same( { "close", "render" },order, "modal close must precede render")
  end)
end)

it("test_does_not_close_a_choice_modal_when_ui_state_is_absent", function()
  local state = {}

  _with_patches({
    { landing_visual_hold, "sync_state_from_game", function() end },
    { landing_visual_hold, "should_defer", function() return false end },
    { turn_ui_sync_shared, "build_ui_env", function()
      return { source = "no-ui" }
    end },
    { turn_ui_sync_shared, "is_only_turn_countdown", function() return false end },
    { view_model, "update", function()
      return { panel = {} }
    end },
    { main_view, "render", function() end },
    { modal, "close_choice_modal", function()
      error("absent ui state should not close a choice modal")
    end },
    { modal, "open_choice_modal", function()
      error("model without choice should not open a modal")
    end },
  }, function()
    luassert.is.same( true,model_sync.refresh_from_dirty(_game(), state, { any = true }, _common()))
  end)
end)


end)
