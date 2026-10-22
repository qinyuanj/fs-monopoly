require("test.bootstrap").install_package_paths()
local luassert = require("luassert")
-- 弹层行为规约:popup_presenter 生命周期与卡牌展示广播。
-- 共享 _make_state / 角色扇出 / reveal fixture。
local support = require("test.support.shared_support")
local popup = require("src.ui.coord.popup")
local popup_presenter = require("src.ui.coord.popup_presenter")
local canvas = require("src.ui.coord.canvas_coordinator")
local runtime_port = require("src.ui.render.support.runtime_ui")
local role_ctx = require("src.ui.view.role_context")
local ui_view = require("src.ui.coord.ui_runtime")
local item_atlas = require("src.ui.screens.item_atlas")
local item_atlas_nodes = require("src.ui.schema.item_atlas")
local skin_nodes = require("src.ui.schema.skin")
local gift_code_nodes = require("src.ui.schema.gift_code")
local view_command_ports = require("src.ui.ports.view_command")
local route_popup = require("src.ui.input.route_popup")
local event_actor_policy = require("src.ui.coord.event_actor_policy")

local function _assert_eq(a, b, msg) luassert.is.equal(b, a, msg) end
local _with_patches = support.with_patches

local function _make_state()
  return {
    ui = ui_view.build_ui_state(),
    ui_model = { current_player_id = 1, item_slots_by_player_id = { [1] = true, [2] = true } },
    game = { turn = { phase = "wait_choice" } },
  }
end

local function _make_roles(role_count)
  local roles = {}
  for i = 1, role_count do
    roles[i] = {
      id = i,
      get_roleid = function() return i end,
    }
  end
  return roles
end

-- 单角色（全局）渲染补丁：lifecycle 测试用。
local function _render_patches()
  return {
    { target = runtime_port, key = "for_each_role_or_global", value = function(fn) fn(nil) end },
    { target = runtime_port, key = "set_client_role", value = function() end },
    { target = canvas, key = "switch_for_role", value = function() end },
    { target = canvas, key = "switch", value = function() end },
    { target = role_ctx, key = "resolve", value = function()
      return { can_operate = true, role_id = 1 }
    end },
    { target = popup, key = "hide", value = function() end },
  }
end

-- 多角色扇出补丁：广播测试用。fn 内产生的 canvas 切换全部记录并返回。
-- 默认 role 1 可操作、ctx 带 role_id;可用 opts.resolve_ctx 覆盖。
local function _run_with_role_fanout(roles, opts, fn)
  local switches = {}
  local resolve = (opts and opts.resolve_ctx) or function(role)
    return { can_operate = role.id == 1, role_id = role.id }
  end
  _with_patches({
    { target = runtime_port, key = "for_each_role_or_global", value = function(cb)
      for _, role in ipairs(roles) do
        runtime_port.with_client_role(role, cb, role)
      end
    end },
    { target = runtime_port, key = "set_client_role", value = function() end },
    { target = runtime_port, key = "with_client_role", value = runtime_port.with_client_role },
    { target = canvas, key = "switch_for_role", value = function(_, target, role)
      switches[#switches + 1] = { target = target, role_id = role and role.id or nil }
    end },
    { target = canvas, key = "switch", value = function(_, target)
      switches[#switches + 1] = { target = target, role_id = "all" }
    end },
    { target = role_ctx, key = "resolve", value = resolve },
    { target = popup, key = "hide", value = function() end },
  }, fn)
  return switches
end

local function _last_switch_target(switches, role_id)
  local target = nil
  for _, s in ipairs(switches) do
    if s.role_id == role_id then
      target = s.target
    end
  end
  return target
end

local function _push_broadcast_chance(state)
  popup_presenter.push_popup(state, { title = "机会卡", kind = "chance_card", broadcast = true })
end
describe("TestPopupPresenter", function()
it("test_push_and_close_roundtrip_resets_popup_state", function()
  local state = _make_state()

  _with_patches(_render_patches(), function()
    local pushed = popup_presenter.push_popup(state, { title = "机会卡", kind = "chance_card", broadcast = true })
    _assert_eq(pushed, true, "push_popup should report success")
    _assert_eq(state.ui.popup_active, true, "popup should be active after push")
    _assert_eq(state.ui.popup_broadcast, true, "broadcast flag should follow payload")

    popup_presenter.close_popup(state)
  end)

  _assert_eq(state.ui.popup_active, false, "popup should be inactive after close")
  _assert_eq(state.ui.popup_broadcast, false, "broadcast flag should reset after close")
end)

-- 回归:弹窗开/关必须标 ui_dirty。修复前 close_popup 只清旗标不触发重绘,
-- 回合结束阶段用卡时(弹窗关闭后再无其他 dirty 源)道具槽保持「弹窗期间渲染的
-- 不可点状态」直到窗口超时——玩家只能干等倒计时到回合结束。
it("test_popup_open_and_close_both_mark_ui_dirty_for_rerender", function()
  local state = _make_state()
  local runtime_state = require("src.ui.state.runtime")

  _with_patches(_render_patches(), function()
    runtime_state.set_ui_dirty(state, false)
    popup_presenter.push_popup(state, { title = "道具卡", kind = "item_card" })
    _assert_eq(runtime_state.is_ui_dirty(state), true,
      "open_popup should mark ui dirty so base/slots re-render as blocked")

    runtime_state.set_ui_dirty(state, false)
    popup_presenter.close_popup(state)
  end)

  _assert_eq(runtime_state.is_ui_dirty(state), true,
    "close_popup must mark ui dirty: without it item slots stay untouchable until choice timeout")
end)

it("test_close_without_active_popup_is_a_noop", function()
  local state = _make_state()
  local hide_calls = 0

  _with_patches({
    { target = popup, key = "hide", value = function()
      hide_calls = hide_calls + 1
    end },
  }, function()
    popup_presenter.close_popup(state)
  end)

  _assert_eq(hide_calls, 0, "close without active popup must not hide anything")
  _assert_eq(state.ui.popup_active, false, "popup stays inactive")
end)

it("test_push_requires_payload_and_close_warns_when_inactive_262", function()
  -- kills assert 消息 "missing popup payload" -> nil 与
  -- logger.warn 消息 "close_popup ignored: popup not active" -> nil。
  luassert.has_error(function()
    popup_presenter.push_popup(_make_state(), nil)
  end, "missing popup payload")

  local warns = {}
  _with_patches({
    { target = require("src.foundation.log"), key = "warn", value = function(message)
      warns[#warns + 1] = message
    end },
  }, function()
    popup_presenter.close_popup(_make_state())
  end)
  _assert_eq(warns[1], "close_popup ignored: popup not active",
    "close without an active popup must warn with the exact label")
end)

it("test_deferred_popups_replay_in_order", function()
  local state = _make_state()

  _with_patches(_render_patches(), function()
    popup_presenter.push_popup(state, { title = "A", kind = "card" })
    local deferred_b = popup_presenter.push_popup(state, { title = "B", kind = "card" }, { policy = "defer" })
    local deferred_c = popup_presenter.push_popup(state, { title = "C", kind = "card" }, { policy = "defer" })
    _assert_eq(deferred_b, true, "deferring B should report success")
    _assert_eq(deferred_c, true, "deferring C should report success")
    _assert_eq(state.ui.popup_payload.title, "A", "A should be showing first")

    popup_presenter.close_popup(state)
    _assert_eq(state.ui.popup_payload.title, "B", "B should replay after A closes")

    popup_presenter.close_popup(state)
    _assert_eq(state.ui.popup_payload.title, "C", "C should replay after B closes")

    popup_presenter.close_popup(state)
  end)

  _assert_eq(state.ui.popup_active, false, "queue drained popup should be inactive")
end)

it("test_close_ignores_stale_roll_anim_outside_wait_phase", function()
  -- 只有「wait_action_anim 相位 + roll 动画」才保持骰子屏;残留的 roll 动画
  -- 载荷在其它相位不该劫持关屏后的回屏目标。
  local state = _make_state()
  state.game.turn = { phase = "wait_choice", action_anim = { kind = "roll" } }
  local closed_to = nil

  _with_patches(_render_patches(), function()
    popup_presenter.push_popup(state, { title = "机会卡", kind = "chance_card" })
  end)
  _with_patches({
    { target = popup, key = "hide", value = function() end },
    { target = popup, key = "switch_popup_canvas", value = function(_, _, next_canvas)
      closed_to = next_canvas
    end },
  }, function()
    popup_presenter.close_popup(state)
  end)

  _assert_eq(closed_to, canvas.CANVAS_BASE, "stale roll anim outside wait phase should not keep dice canvas")
end)

it("test_closing_bankruptcy_popup_keeps_spectator_on_market_return_canvas", function()
  -- 关屏 kind 取自 ui.popup_kind:破产弹窗关屏时旁观 role 也跟到回屏目标
  -- (黑市),而不是被当成普通卡牌弹窗打回 fallback。
  local state = _make_state()
  state.ui.market_active = true
  local roles = { { id = 2, get_roleid = function() return 2 end } }

  local switches = _run_with_role_fanout(roles, {
    resolve_ctx = function(role)
      return { can_operate = false, role_id = role.id }
    end,
  }, function()
    popup_presenter.push_popup(state, { kind = "bankruptcy", text = "破产测试" })
    popup_presenter.close_popup(state)
  end)

  _assert_eq(_last_switch_target(switches, 2), canvas.CANVAS_MARKET,
    "spectator should follow bankruptcy close to the market return canvas")
end)

it("test_popup_render_and_hide_survive_missing_screen_tables", function()
  -- 渲染/隐藏对 screen 表缺失(或 root 缺失)按守卫跳过,不摸空节点。
  local nil_node_touches = 0
  local ui = {
    set_visible = function(_, name)
      if name == nil then
        nil_node_touches = nil_node_touches + 1
      end
    end,
    set_label = function() end,
    set_touch_enabled = function() end,
    query_node = function(_, name) return name end,
  }
  local state = { ui = ui, runtime_asset_context = { refs = { images = { ["Empty"] = "EMPTY" } } } }

  _with_patches({
    { target = runtime_port, key = "for_each_role_or_global", value = function(fn) fn(nil) end },
    { target = runtime_port, key = "set_client_role", value = function() end },
    { target = canvas, key = "switch", value = function() end },
    { target = canvas, key = "switch_for_role", value = function() end },
    { target = role_ctx, key = "resolve", value = function()
      return { can_operate = true, role_id = 1 }
    end },
  }, function()
    -- 破产屏表整个缺失:渲染与隐藏都不该报错
    popup.show_popup(state, { kind = "bankruptcy", text = "破产测试" })
    popup.hide(state)

    -- 卡牌屏 root 缺失:标题照写,root 的显隐跳过
    ui.popup_kind = nil
    state.ui.popup_screen = { title = "标题节点", root = nil }
    popup.show_popup(state, { title = "机会卡", kind = "chance_card" })
    state.ui.popup_screen = nil
    popup.hide(state)
  end)

  _assert_eq(nil_node_touches, 0, "render must never touch a nil node name")
end)

it("test_dismiss_popup_allows_non_broadcast_without_actor_check", function()
  -- Regression for --mutate and→or at L68:
  -- `ui and ui.popup_broadcast` → `or`. With a non-broadcast popup
  -- (popup_broadcast is nil), the original skips the actor check and
  -- allows any dismisser; the mutant enters the check and may reject.
  local state = _make_state()
  _with_patches(_render_patches(), function()
    popup_presenter.push_popup(state, { title = "非广播", kind = "card" })
    -- Non-broadcast popup should let any role dismiss without rejection.
    _assert_eq(popup_presenter.dismiss_popup(state, 2), true,
      "non-broadcast popup should allow bystander dismiss without actor check")
  end)
  _assert_eq(state.ui.popup_active, false, "popup should close after dismiss")
end)

it("test_close_popup_defaults_kind_to_card_when_popup_kind_nil", function()
  -- Regression for --mutate "card"→nil at L49:
  -- `local kind = ui.popup_kind or "card"` — when ui.popup_kind is nil,
  -- the default "card" is used. Mutating to nil would pass nil as kind
  -- to switch_popup_canvas. Nil out popup_kind AFTER push (which sets it)
  -- to exercise the fallback default.
  local state = _make_state()
  local switch_calls = {}
  _with_patches(_render_patches(), function()
    popup_presenter.push_popup(state, { title = "默认", kind = "card" })
  end)
  -- Force nil to exercise the "or card" default.
  state.ui.popup_kind = nil
  _with_patches({
    { target = popup, key = "hide", value = function() end },
    { target = popup, key = "switch_popup_canvas", value = function(_, kind)
      switch_calls[#switch_calls + 1] = kind
    end },
  }, function()
    popup_presenter.close_popup(state)
  end)
  _assert_eq(switch_calls[1], "card",
    "close_popup should default kind to 'card' when ui.popup_kind is nil")
end)

it("test_dismiss_popup_reports_close_permission", function()
  local state = _make_state()
  state.ui.current_action_role_id = 1

  _with_patches(_render_patches(), function()
    popup_presenter.push_popup(state, { title = "机会卡", kind = "chance_card", broadcast = true })

    _assert_eq(popup_presenter.dismiss_popup(state, 2), false,
      "bystander dismiss should be rejected for broadcast popup")
    _assert_eq(state.ui.popup_active, true, "popup should stay active after bystander dismiss")

    _assert_eq(popup_presenter.dismiss_popup(state, 1), true,
      "operator dismiss should close broadcast popup")
  end)

  _assert_eq(state.ui.popup_active, false, "popup should close after operator dismiss")
end)

it("test_broadcast_popup_excludes_excluded_role_from_canvas_switch", function()
  -- 2026-08-25 买家免展示口径:载荷带 exclude_role_id 的广播弹窗,被排除角色
  -- 开屏不切去弹窗、收屏也不回切(其 canvas 全程未离开,黑市屏不动);
  -- 其余角色照常切去弹窗、收屏回自己面板。排除只属本条弹窗:收屏后再推
  -- 一条不带排除的广播弹窗,买家必须照常切去弹窗屏(旗标回收的行为面)。
  local state = _make_state()
  state.ui.current_action_role_id = 1
  state.ui.market_active = true
  item_atlas.open(state, 2)

  local function _has_switch(switches, role_id, target)
    for _, s in ipairs(switches) do
      if s.role_id == role_id and s.target == target then
        return true
      end
    end
    return false
  end

  local switches = _run_with_role_fanout(_make_roles(2), nil, function()
    popup_presenter.push_popup(state, {
      title = "道具卡", kind = "item_card", broadcast = true, exclude_role_id = 1,
    })
    popup_presenter.close_popup(state)
  end)

  _assert_eq(_has_switch(switches, 1, canvas.CANVAS_POPUP), false,
    "excluded buyer should not be switched to popup canvas on open")
  _assert_eq(_has_switch(switches, 1, canvas.CANVAS_MARKET), false,
    "excluded buyer should not be canvas-switched on close either (never left market)")
  _assert_eq(_has_switch(switches, 2, canvas.CANVAS_POPUP), true,
    "bystander should still be switched to popup canvas on open")
  _assert_eq(_last_switch_target(switches, 2), item_atlas_nodes.canvas,
    "bystander should return to own panel after close")

  local next_switches = _run_with_role_fanout(_make_roles(2), nil, function()
    popup_presenter.push_popup(state, { title = "机会卡", kind = "chance_card", broadcast = true })
  end)
  _assert_eq(_has_switch(next_switches, 1, canvas.CANVAS_POPUP), true,
    "buyer should see the next non-excluding broadcast popup (exclusion must not leak across popups)")
end)

it("test_excluded_buyer_cannot_dismiss_broadcast_popup", function()
  -- 2026-08-25 买家免展示口径:被排除的买家看不到展示也无关闭权——dismiss
  -- 一律拒绝(含程序化 popup_confirm),收屏只走超时自动关闭;旁观者点击
  -- 依旧无效。超时装订的 close_popup 端口路径照常收屏。
  local state = _make_state()
  state.ui.current_action_role_id = 1

  _with_patches(_render_patches(), function()
    popup_presenter.push_popup(state, {
      title = "道具卡", kind = "item_card", broadcast = true, exclude_role_id = 1,
    })

    _assert_eq(popup_presenter.dismiss_popup(state, 1), false,
      "excluded buyer dismiss should be rejected even though they are the operator")
    _assert_eq(popup_presenter.dismiss_popup(state, 2), false,
      "bystander dismiss should still be rejected")
    _assert_eq(state.ui.popup_active, true, "popup should stay active after rejected dismisses")

    popup_presenter.close_popup(state)
  end)

  _assert_eq(state.ui.popup_active, false, "timeout close path should still close the popup")
end)

it("test_broadcast_flag_gates_bystander_popup_canvas", function()
  -- broadcast 弹窗把旁观者切到弹窗屏;非 broadcast 不动旁观者。
  local roles = _make_roles(2)

  local broadcast_switches = _run_with_role_fanout(roles, nil, function()
    _push_broadcast_chance(_make_state())
  end)
  local plain_switches = _run_with_role_fanout(roles, nil, function()
    popup_presenter.push_popup(_make_state(), { title = "普通弹窗", kind = "card" })
  end)

  local function _bystander_on_popup(switches)
    for _, s in ipairs(switches) do
      if s.role_id == 2 and s.target == canvas.CANVAS_POPUP then
        return true
      end
    end
    return false
  end
  _assert_eq(_bystander_on_popup(broadcast_switches), true,
    "bystander should see popup canvas for broadcast chance popup")
  _assert_eq(_bystander_on_popup(plain_switches), false,
    "non-broadcast popup should not switch bystander to popup canvas")
end)

it("test_closing_broadcast_popup_restores_bystander_to_previous_panel", function()
  -- 旁观者被打断前开着的面板(道具图鉴/皮肤面板)在关屏时按面板态回屏。
  local atlas_state = _make_state()
  item_atlas.open(atlas_state, 2)
  local atlas_switches = _run_with_role_fanout(_make_roles(2), nil, function()
    _push_broadcast_chance(atlas_state)
    popup_presenter.close_popup(atlas_state)
  end)
  _assert_eq(_last_switch_target(atlas_switches, 2), item_atlas_nodes.canvas,
    "closing broadcast popup should restore bystander to item atlas canvas")

  local skin_state = _make_state()
  skin_state.ui.skin_panel = { open = true, role_id = 2 }
  local skin_switches = _run_with_role_fanout(_make_roles(2), nil, function()
    _push_broadcast_chance(skin_state)
    popup_presenter.close_popup(skin_state)
  end)
  _assert_eq(_last_switch_target(skin_switches, 2), skin_nodes.canvas,
    "closing broadcast popup should restore bystander to skin panel canvas")

  -- 礼包码屏(#195 review):同属「开着就回」的面板,收屏不能把人拽回基础屏。
  local gift_code_state = _make_state()
  gift_code_state.ui.gift_code = { open = true, role_id = 2 }
  local gift_code_switches = _run_with_role_fanout(_make_roles(2), nil, function()
    _push_broadcast_chance(gift_code_state)
    popup_presenter.close_popup(gift_code_state)
  end)
  _assert_eq(_last_switch_target(gift_code_switches, 2), gift_code_nodes.canvas,
    "closing broadcast popup should restore bystander to the gift code screen canvas")
end)

it("test_bystander_return_canvas_reresolves_at_close_time", function()
  -- 回屏按关闭时刻的面板态重解析:展示期间面板被其它流程关掉时回基础屏,
  -- 不回开屏时快照的过期画面。
  local state = _make_state()
  item_atlas.open(state, 2)

  local switches = _run_with_role_fanout(_make_roles(2), nil, function()
    _push_broadcast_chance(state)
    -- 展示期间图鉴被其它流程关闭
    state.ui.item_atlas.open = false
    popup_presenter.close_popup(state)
  end)

  _assert_eq(_last_switch_target(switches, 2), canvas.CANVAS_BASE,
    "bystander should return to base canvas when the interrupted panel was closed mid-broadcast")
end)

-- #583:旁观者图鉴停留在「选中放大」态时,广播弹窗收屏回图鉴必须清掉陈旧放大卡
-- (selected_item_id + 覆盖层 per-role 显隐)——否则放大覆盖层住图鉴 canvas,
-- 随回屏复活/滞留。观测可见行为:ui.set_visible 捕获三节点终态,不钉内部调用。
it("test_bystander_return_to_atlas_clears_stale_enlarged_card", function()
  local state = _make_state()
  state.ui.current_action_role_id = 1
  local vis = {}
  state.ui.set_visible = function(_, name, v) vis[name] = v == true end
  state.ui.set_touch_enabled = function() end
  item_atlas.open(state, 2)
  state.ui.item_atlas.selected_item_id = "item_stale"
  -- 模拟宿主侧放大覆盖层对角色2正可见(住图鉴 canvas,随图鉴屏显隐)。
  vis[item_atlas_nodes.enlarged_card] = true
  vis[item_atlas_nodes.close_hint_label] = true
  vis[item_atlas_nodes.close_blank] = true

  local switches = _run_with_role_fanout(_make_roles(2), nil, function()
    _push_broadcast_chance(state)
    popup_presenter.close_popup(state)
  end)

  _assert_eq(_last_switch_target(switches, 2), item_atlas_nodes.canvas,
    "bystander should still return to item atlas canvas")
  _assert_eq(state.ui.item_atlas.selected_item_id, nil,
    "stale atlas selection must be cleared on bystander return")
  for _, node in ipairs({ item_atlas_nodes.enlarged_card, item_atlas_nodes.close_hint_label, item_atlas_nodes.close_blank }) do
    luassert.truthy(vis[node] == false, node .. " should be hidden on bystander return")
  end
end)

it("test_closing_broadcast_popup_routes_operator_to_market_and_bystander_back", function()
  -- Story10/11:黑市在展示期间打开,关屏 per-role 分道 —— 行动者进黑市,
  -- 旁观者回自己的面板态,黑市屏不广播。
  local state = _make_state()
  state.ui.current_action_role_id = 1
  item_atlas.open(state, 2)

  local switches = _run_with_role_fanout(_make_roles(2), nil, function()
    _push_broadcast_chance(state)
    -- 机会卡把行动者传送进黑市:黑市屏在弹窗存活期间打开
    state.ui.market_active = true
    popup_presenter.close_popup(state)
  end)

  _assert_eq(_last_switch_target(switches, 1), canvas.CANVAS_MARKET,
    "operator should land on market canvas after closing broadcast popup")
  _assert_eq(_last_switch_target(switches, 2), item_atlas_nodes.canvas,
    "bystander should return to own panel, not follow operator into market")
end)

it("test_bystander_restore_falls_back_to_runtime_role_id_when_ctx_lacks_it", function()
  -- role_context 解析不出 role_id 时(如映射失败的观战 role),回屏分道
  -- 回退用 runtime 侧的 role id,旁观者仍能回到被打断前的面板。
  local state = _make_state()
  state.ui.current_action_role_id = 1
  item_atlas.open(state, 2)

  local switches = _run_with_role_fanout(_make_roles(2), {
    resolve_ctx = function(role)
      return { can_operate = role.id == 1 }
    end,
  }, function()
    _push_broadcast_chance(state)
    popup_presenter.close_popup(state)
  end)

  _assert_eq(_last_switch_target(switches, 2), item_atlas_nodes.canvas,
    "bystander restore should fall back to runtime-resolved role id")
end)

it("test_bystander_popup_confirm_is_ignored_for_broadcast_popup", function()
  local state = _make_state()
  state.ui.current_action_role_id = 1
  local closed = false
  local ports = view_command_ports.build()

  _with_patches({
    { target = popup_presenter, key = "close_popup", value = function()
      closed = true
    end },
  }, function()
    _push_broadcast_chance(state)
    ports.dispatch(state, { type = "popup_confirm", actor_role_id = 2 })
    _assert_eq(closed, false, "bystander should not be able to close broadcast popup")

    ports.dispatch(state, { type = "popup_confirm", actor_role_id = 1 })
    _assert_eq(closed, true, "operator should be able to close broadcast popup")
  end)
end)

it("test_real_intent_path_attaches_click_actor_for_popup_confirm", function()
  -- #143 回归:真机 intent 由 route_popup 构造(不带 actor),actor 只能靠
  -- 命令定义的 requires_event_actor 从点击事件附加;此前定义缺标志,
  -- 行动者本人也关不掉广播弹窗。
  local state = _make_state()
  state.ui.current_action_role_id = 1
  local roles = _make_roles(2)
  local closed = false
  local ports = view_command_ports.build()

  _with_patches({
    { target = popup_presenter, key = "close_popup", value = function()
      closed = true
    end },
  }, function()
    _push_broadcast_chance(state)

    local function _dispatch_click_from(role)
      local specs = route_popup.build(state)
      luassert.truthy(#specs > 0, "popup route should expose dismiss nodes")
      local intent = specs[1].build_intent()
      luassert.truthy(intent ~= nil, "active popup should build popup_confirm intent")
      _assert_eq(intent.actor_role_id, nil, "route_popup intent must not carry a hand-fed actor")
      local ok = event_actor_policy.attach_event_actor(state, intent, { role = role })
      _assert_eq(ok, true, "attach_event_actor should accept popup_confirm intent")
      ports.dispatch(state, intent)
    end

    _dispatch_click_from(roles[2])
    _assert_eq(closed, false, "bystander click via real intent path should not close broadcast popup")

    _dispatch_click_from(roles[1])
    _assert_eq(closed, true, "operator click via real intent path should close broadcast popup")
  end)
end)

it("test_item_tile_landing_reveals_to_bystander_through_real_queue", function()
  -- 2026-08-18 换皮(CONTEXT「卡牌展示广播」 修订)+ 2026-08-22 #543 口径反转:
  -- 道具获得展示全来源统一走「卡牌展示屏」弹窗全员广播。
  -- 全链路拼接:effect_transit 执行器 → 真实 game 队列 + 真实 intent 派发链,
  -- 校验 broadcast 标志经真实 payload 存活到 popup 出口与纯等待动画。
  local effect_transit = require("src.rules.land.effect_transit")
  local captured = {}
  local g = support.new_game({ ui_port = { push_popup = function(_, payload)
    captured.payload = payload
    return true
  end } })
  g.anim_gate_port = { wait_action_anim = true }
  local player = g:current_player()

  effect_transit.executors.item_draw_and_give.apply({
    game = g,
    player = player,
    tile = { type = "item" },
    on_landing = true,
  })

  local anim = g.turn.action_anim
  luassert.truthy(anim ~= nil, "item tile landing should queue an action anim")
  _assert_eq(anim.kind, "item_gain_popup", "queued anim kind mismatch")
  _assert_eq(anim.broadcast, true, "item tile reveal should broadcast through real queue")

  local payload = captured.payload
  luassert.truthy(payload ~= nil, "item tile landing should push card reveal popup through real chain")
  _assert_eq(payload.kind, "item_card", "gain popup kind mismatch")
  _assert_eq(payload.title, "道具卡", "gain popup title mismatch")
  _assert_eq(payload.broadcast, true, "gain popup should broadcast to all roles")
  _assert_eq(payload.image_ref, anim.item_id, "gain popup image should match the drawn item")
end)

it("test_route_popup_falls_back_to_static_dismiss_nodes_without_ui", function()
  -- kills _dismiss_nodes 的 `state.ui and state.ui.popup_screen` and->or 与
  -- _popup_confirm_intent 的 `state.ui and state.ui.popup_active` and->or:
  -- state 无 ui 时 route 必须静默回落静态节点表,or 变异体会在 nil 上索引报错。
  local state = {}
  local specs = route_popup.build(state)
  luassert.truthy(type(specs) == "table" and #specs > 0,
    "without ui the popup route should fall back to static dismiss nodes")
  local intent = specs[1].build_intent()
  luassert.truthy(intent == nil, "without ui there is no active popup, so no confirm intent")
end)

it("test_route_popup_uses_screen_dismiss_nodes_when_present", function()
  -- kills _dismiss_nodes 的两个 or->and/and->or 链:弹窗屏提供自定义
  -- dismiss_nodes 时必须用它而不是静态回落表。
  local state = {
    ui = {
      popup_screen = {
        dismiss_nodes = { "custom_dismiss_1", "custom_dismiss_2" },
      },
    },
  }
  local specs = route_popup.build(state)
  luassert.truthy(type(specs) == "table" and #specs == 2, "specs should mirror the screen dismiss nodes")
  _assert_eq(specs[1].name, "custom_dismiss_1", "first spec should use the screen dismiss node")
  _assert_eq(specs[2].name, "custom_dismiss_2", "second spec should use the screen dismiss node")
end)

it("test_route_popup_falls_back_to_static_nodes_when_screen_absent", function()
  -- kills L1 require 换 nil:弹窗屏缺失(ui 在但无 popup_screen)时回落
  -- 静态节点表,require 被删会让 nodes.dismiss_nodes 索引 nil 报错。
  local state = { ui = {} }
  local specs = route_popup.build(state)
  luassert.truthy(type(specs) == "table" and #specs > 0,
    "without popup_screen the route should fall back to the static dismiss nodes")
end)

it("test_choice_close_returns_excluded_buyer_to_base_canvas", function()
  -- #604 黑市收屏滞留回归:买家在广播弹窗存活期关闭黑市,收屏走弹窗分支,
  -- 排除口径若整体跳过买家,「隐藏黑市屏」事件永远不发,客户端屏滞留到
  -- 无关 canvas 切换(真机实测 3.1s/7.3s)。此时黑市已随 choice 关闭,
  -- switch_popup_canvas 带 excluded_return 时必须把买家切回返回 canvas(基础屏),
  -- 但仍不得切去弹窗屏;旁观者行为不变。
  local state = _make_state()
  state.ui.current_action_role_id = 1
  state.ui.market_active = false
  state.ui.popup_active = true
  state.ui.popup_broadcast = true
  state.ui.popup_exclude_role_id = 1

  local function _has_switch(switches, role_id, target)
    for _, s in ipairs(switches) do
      if s.role_id == role_id and s.target == target then
        return true
      end
    end
    return false
  end

  local switches = _run_with_role_fanout(_make_roles(2), nil, function()
    popup.switch_popup_canvas(state, "card", canvas.CANVAS_POPUP, canvas.CANVAS_BASE, { excluded_return = true })
  end)

  _assert_eq(_has_switch(switches, 1, canvas.CANVAS_BASE), true,
    "excluded buyer whose market just closed must be switched back to the base canvas")
  _assert_eq(_has_switch(switches, 1, canvas.CANVAS_POPUP), false,
    "excluded buyer must still not be switched to the popup canvas")
  _assert_eq(_has_switch(switches, 2, canvas.CANVAS_POPUP), true,
    "bystanders still follow the broadcast popup canvas")
end)


end)
