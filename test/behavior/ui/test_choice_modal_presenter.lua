require("test.bootstrap").install_package_paths()
local luassert = require("luassert")
local support = require("test.support.shared_support")
local function _assert_eq(a, b, msg) luassert.is.equal(b, a, msg) end
local _with_patches = support.with_patches

local modal_presenter = require("src.ui.coord.modal")
local modal_state = require("src.ui.state.modal")
local pending_confirmation = require("src.ui.state.pending_confirmation")
local choice_openers = require("src.ui.coord.choice_openers")
local secondary_confirm_screen = require("src.ui.screens.secondary_confirm")
local choice_common = require("src.ui.coord.choice_helpers")
local popup = require("src.ui.coord.popup")
local market_presenter = require("src.ui.screens.market")
local canvas = require("src.ui.coord.canvas_coordinator")
local runtime_state = require("src.ui.state.runtime")
local runtime_ui = require("src.ui.render.support.runtime_ui")
local screen_openers = require("src.ui.seams.screen_openers")
local gift_code_nodes = require("src.ui.schema.gift_code")
local logger = require("src.foundation.log")
describe("TestChoiceModalPresenter", function()
it("test_同一个非 market choice 的屏已开着时,重复 open 被整体跳过", function()
  local dirty_calls = 0
  local opener_calls = 0
  local market_close_calls = 0
  local state = {
    ui = { choice_active = true, active_choice_screen_key = "target_pick", market_active = false },
  }
  runtime_state.set_pending_choice_id(state, 42)

  _with_patches({
    { target = choice_common, key = "resolve_screen_key", value = function() return "target_pick" end },
    { target = runtime_state, key = "set_ui_dirty", value = function() dirty_calls = dirty_calls + 1 end },
    { target = choice_openers, key = "open_choice_modal", value = function() opener_calls = opener_calls + 1 end },
    { target = market_presenter, key = "close", value = function() market_close_calls = market_close_calls + 1 end },
  }, function()
    modal_presenter.open_choice_modal(state, { id = 42 })
  end)

  _assert_eq(dirty_calls, 0, "a skipped reopen must not dirty the ui")
  _assert_eq(opener_calls, 0, "a skipped reopen must not re-run the generic choice opener")
  _assert_eq(market_close_calls, 0, "a skipped reopen must not touch the market screen")
end)

it("test_market choice 即使已是当前屏也照常重开(不享受 skip 豁免)", function()
  local market_open = nil
  local state = {
    ui = { choice_active = true, active_choice_screen_key = "market", market_active = true },
  }
  runtime_state.set_pending_choice_id(state, 42)
  local choice = { id = 42 }
  local market_snapshot = { stub = true }

  _with_patches({
    { target = choice_common, key = "resolve_screen_key", value = function() return "market" end },
    { target = runtime_state, key = "set_ui_dirty", value = function() end },
    { target = market_presenter, key = "open", value = function(s, c, choice_id, m)
      market_open = { state = s, choice = c, choice_id = choice_id, market = m }
    end },
  }, function()
    modal_presenter.open_choice_modal(state, choice, market_snapshot)
  end)

  luassert.truthy(market_open ~= nil, "an already-active market choice must still reopen the market screen")
  _assert_eq(market_open.choice_id, 42, "market open must carry the choice id")
  _assert_eq(market_open.market, market_snapshot, "market open must carry the market snapshot")
end)

it("test_缺 choice / 缺 choice.id 时告警拒绝,不开任何屏也不弄脏 ui", function()
  local warns = {}
  local opener_calls = 0
  local dirty_calls = 0
  local market_open_calls = 0
  local state = { ui = { choice_active = false } }

  _with_patches({
    { target = logger, key = "warn", value = function(...)
      warns[#warns + 1] = table.concat({ ... }, " ")
    end },
    { target = choice_openers, key = "open_choice_modal", value = function() opener_calls = opener_calls + 1 end },
    { target = runtime_state, key = "set_ui_dirty", value = function() dirty_calls = dirty_calls + 1 end },
    { target = market_presenter, key = "open", value = function() market_open_calls = market_open_calls + 1 end },
  }, function()
    modal_presenter.open_choice_modal(state, nil)
    modal_presenter.open_choice_modal(state, {})
  end)

  _assert_eq(#warns, 2, "both rejects must warn exactly once each")
  luassert.truthy(warns[1]:find("missing choice", 1, true), "nil choice must warn 'missing choice'")
  luassert.truthy(warns[2]:find("missing choice id", 1, true), "id-less choice must warn 'missing choice id'")
  _assert_eq(opener_calls, 0, "a rejected open must not reach the generic choice opener")
  _assert_eq(market_open_calls, 0, "a rejected open must not reach the market screen")
  _assert_eq(dirty_calls, 0, "a rejected open must not dirty the ui")
end)

it("test_不需要二次确认的 base_inline choice 走关屏路径", function()
  local pre_confirm_calls = 0
  local close_calls = 0
  local reset_calls = 0
  local opener_calls = 0
  local canvas_targets = {}
  local state = { ui = { choice_active = false, market_active = false } }

  _with_patches({
    { target = choice_common, key = "resolve_screen_key", value = function() return "base_inline" end },
    { target = choice_common, key = "requires_item_slot_pre_confirm", value = function() return false end },
    { target = choice_common, key = "uses_item_slots", value = function() return false end },
    { target = choice_common, key = "switch_modal_canvas", value = function(_, target)
      canvas_targets[#canvas_targets + 1] = target
    end },
    { target = pending_confirmation, key = "is_item_phase_confirmed", value = function() return false end },
    { target = pending_confirmation, key = "reset_item_phase_confirmed", value = function() reset_calls = reset_calls + 1 end },
    { target = secondary_confirm_screen, key = "open_item_phase_pre_confirm", value = function() pre_confirm_calls = pre_confirm_calls + 1 end },
    { target = modal_state, key = "close_choice", value = function() close_calls = close_calls + 1 end },
    { target = runtime_state, key = "set_ui_dirty", value = function() end },
    { target = choice_openers, key = "open_choice_modal", value = function() opener_calls = opener_calls + 1 end },
  }, function()
    modal_presenter.open_choice_modal(state, { id = 7 })
  end)

  _assert_eq(pre_confirm_calls, 0,
    "a choice that does not require pre-confirm must never open the pre-confirm screen")
  _assert_eq(reset_calls, 1, "the inline close path must reset the item-phase confirmation")
  _assert_eq(close_calls, 1, "with no active choice screen the inline path closes the choice state")
  _assert_eq(canvas_targets[1], canvas.CANVAS_BASE, "the inline close path must return to the base canvas")
  _assert_eq(opener_calls, 0, "a special-screen choice must not fall through to the generic opener")
end)

it("test_已确认过道具阶段的 choice 不再弹二次确认", function()
  local pre_confirm_calls = 0
  local close_calls = 0
  local state = { ui = { choice_active = false, market_active = false } }

  _with_patches({
    { target = choice_common, key = "resolve_screen_key", value = function() return "base_inline" end },
    { target = choice_common, key = "requires_item_slot_pre_confirm", value = function() return true end },
    { target = choice_common, key = "uses_item_slots", value = function() return true end },
    { target = choice_common, key = "switch_modal_canvas", value = function() end },
    { target = pending_confirmation, key = "is_item_phase_confirmed", value = function() return true end },
    { target = pending_confirmation, key = "reset_item_phase_confirmed", value = function() end },
    { target = secondary_confirm_screen, key = "open_item_phase_pre_confirm", value = function() pre_confirm_calls = pre_confirm_calls + 1 end },
    { target = modal_state, key = "close_choice", value = function() close_calls = close_calls + 1 end },
    { target = runtime_state, key = "set_ui_dirty", value = function() end },
  }, function()
    modal_presenter.open_choice_modal(state, { id = 8 })
  end)

  _assert_eq(pre_confirm_calls, 0,
    "an already-confirmed item phase must go to the close path, not another pre-confirm")
  _assert_eq(close_calls, 1, "the confirmed choice must close the inline choice state")
end)

it("test_接管清掉道具阶段询问,不走通用开屏", function()
  local cleared_sources = {}
  local opener_calls = 0
  local canvas_targets = {}
  local state = { ui = { choice_active = false } }

  _with_patches({
    { target = choice_common, key = "resolve_screen_key", value = function() return "item_phase_passive" end },
    { target = choice_common, key = "switch_modal_canvas", value = function(_, target)
      canvas_targets[#canvas_targets + 1] = target
    end },
    { target = pending_confirmation, key = "clear", value = function(_, source)
      cleared_sources[#cleared_sources + 1] = source
    end },
    { target = runtime_state, key = "set_ui_dirty", value = function() end },
    { target = choice_openers, key = "open_choice_modal", value = function() opener_calls = opener_calls + 1 end },
  }, function()
    modal_presenter.open_choice_modal(state, { id = 9 })
  end)

  _assert_eq(cleared_sources[1], pending_confirmation.SOURCE_ITEM_PHASE_ASK,
    "the takeover must clear the item-phase ask confirmation")
  _assert_eq(canvas_targets[1], canvas.CANVAS_BASE, "the takeover must land on the base canvas")
  _assert_eq(opener_calls, 0, "the passive window must not fall through to the generic opener")
end)

it("test_popup 在场时关 choice 回 popup 画布,不走普通 modal 画布切换", function()
  local popup_switch = nil
  local modal_canvas_calls = 0
  local state = {
    ui = { choice_active = false, market_active = false, popup_active = true, popup_kind = nil },
  }

  _with_patches({
    { target = popup, key = "switch_popup_canvas", value = function(s, kind, target, fallback)
      popup_switch = { state = s, kind = kind, target = target, fallback = fallback }
    end },
    { target = choice_common, key = "switch_modal_canvas", value = function() modal_canvas_calls = modal_canvas_calls + 1 end },
    { target = modal_state, key = "close_choice", value = function() end },
    { target = runtime_state, key = "set_ui_dirty", value = function() end },
  }, function()
    modal_presenter.close_choice_modal(state)
  end)

  luassert.truthy(popup_switch ~= nil, "closing with an active popup must switch back to the popup canvas")
  _assert_eq(popup_switch.kind, "card", "a nil popup_kind must default to the card popup")
  _assert_eq(popup_switch.target, canvas.CANVAS_POPUP, "the popup switch target must be the popup canvas")
  _assert_eq(popup_switch.fallback, canvas.CANVAS_BASE, "the popup switch fallback must be the base canvas")
  _assert_eq(modal_canvas_calls, 0, "an active popup must bypass the plain modal canvas switch")
end)

it("test_open 与 close 都以 true 弄脏 ui", function()
  -- kills open_choice_modal 与 close_choice_modal 里
  -- set_ui_dirty(state, true) 的两个 true->false。
  local dirty_flags = {}
  local state = { ui = { choice_active = false } }
  local close_state = {
    ui = { choice_active = false, market_active = false, popup_active = true, popup_kind = nil },
  }

  _with_patches({
    { target = choice_common, key = "resolve_screen_key", value = function() return "item_phase_passive" end },
    { target = choice_common, key = "switch_modal_canvas", value = function() end },
    { target = pending_confirmation, key = "clear", value = function() end },
    { target = choice_openers, key = "open_choice_modal", value = function() end },
    { target = popup, key = "switch_popup_canvas", value = function() end },
    { target = modal_state, key = "close_choice", value = function() end },
    { target = runtime_state, key = "set_ui_dirty", value = function(_, flag)
      dirty_flags[#dirty_flags + 1] = flag
    end },
  }, function()
    modal_presenter.open_choice_modal(state, { id = 9 })
    modal_presenter.close_choice_modal(close_state)
  end)

  _assert_eq(#dirty_flags, 2, "open and close must each dirty the ui once")
  _assert_eq(dirty_flags[1], true, "open must dirty the ui with true")
  _assert_eq(dirty_flags[2], true, "close must dirty the ui with true")
end)

it("test_popup 在场关 choice 时,弹窗切换带排除角色回切标记", function()
  -- #604:choice 收屏的弹窗分支必须把「黑市已关」的事实传给 popup 分发,
  -- 让排除角色(买家)回切基础屏;缺标记时买家被整体跳过,屏滞留。
  local popup_switch = nil
  local state = {
    ui = { choice_active = false, market_active = false, popup_active = true, popup_kind = nil },
  }

  _with_patches({
    { target = popup, key = "switch_popup_canvas", value = function(s, kind, target, fallback, opts)
      popup_switch = { opts = opts }
    end },
    { target = choice_common, key = "switch_modal_canvas", value = function() end },
    { target = modal_state, key = "close_choice", value = function() end },
    { target = runtime_state, key = "set_ui_dirty", value = function() end },
  }, function()
    modal_presenter.close_choice_modal(state)
  end)

  luassert.truthy(popup_switch ~= nil, "closing with an active popup must go through the popup canvas switch")
  _assert_eq(popup_switch.opts and popup_switch.opts.excluded_return, true,
    "choice close with live popup must mark excluded_return so the buyer returns to base canvas")
end)

-- #202:选择屏收屏统一到 #583 的 per-role 面板回屏口径——每个角色回到自己
-- 开着的面板 canvas,没开面板才回基础屏;不再把所有人一并送回基础屏。
local function _fanout_patches(roles, switches)
  return {
    { target = runtime_ui, key = "for_each_role_or_global", value = function(fn)
      for _, role in ipairs(roles) do fn(role) end
    end },
    { target = runtime_ui, key = "resolve_role_id", value = function(role)
      return role and role.id or nil
    end },
    { target = runtime_ui, key = "set_client_role", value = function() end },
    { target = canvas, key = "switch_for_role", value = function(_, target, role)
      switches[role.id] = target
    end },
    { target = canvas, key = "switch", value = function(_, target)
      switches.global = target
    end },
    { target = modal_state, key = "close_choice", value = function() end },
    { target = runtime_state, key = "set_ui_dirty", value = function() end },
  }
end

it("test_选择屏收屏后每个角色回到自己开着的面板,没面板回基础屏", function()
  local switches = {}
  local state = {
    ui = {
      choice_active = false,
      market_active = false,
      gift_code = { open = true, role_id = 1 },
    },
  }

  _with_patches(_fanout_patches({ { id = 1 }, { id = 2 } }, switches), function()
    modal_presenter.close_choice_modal(state)
  end)

  _assert_eq(switches[1], gift_code_nodes.canvas,
    "the role with the gift code screen open must return to the gift code canvas")
  _assert_eq(switches[2], canvas.CANVAS_BASE,
    "a role without any open panel must fall back to the base canvas")
end)

it("test_黑市收屏后操作者回到自己的礼包码屏", function()
  local switches = {}
  local market_close_calls = 0
  local state = {
    ui = {
      choice_active = false,
      market_active = true,
      gift_code = { open = true, role_id = 1 },
    },
  }
  local patches = _fanout_patches({ { id = 1 }, { id = 2 } }, switches)
  patches[#patches + 1] = { target = screen_openers, key = "close_market", value = function()
    market_close_calls = market_close_calls + 1
  end }

  _with_patches(patches, function()
    modal_presenter.close_choice_modal(state)
  end)

  _assert_eq(market_close_calls, 1, "closing an active market must close the market screen")
  _assert_eq(switches[1], gift_code_nodes.canvas,
    "the operator must return to the gift code screen opened before the market")
  _assert_eq(switches[2], canvas.CANVAS_BASE,
    "the panelless bystander must fall back to the base canvas")
end)


end)
