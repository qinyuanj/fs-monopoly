-- #199 / #195 User Stories 20–23:礼包码屏接线。经节点点击路由(route spec →
-- 意图派发)与宿主「输入框输入完成」事件驱动,观察宿主侧可见行为:按玩家收到的
-- canvas 显隐事件、按玩家写入输入框的文本、按玩家入队的提示。兑换走真实门面,
-- 宿主存档/墙钟/角色只在 runtime_ports 边界替身;输入事件只在 host_events
-- 端口替身;输入框节点只在 UIManager 查询边界替身。
require("test.bootstrap").install_package_paths()
-- busted injects luassert fields on assert.
-- luacheck: ignore 143
local luassert = assert
local support = require("test.support.shared_support")
local routes = require("src.ui.input.routes")
local intent_dispatcher = require("src.ui.input.intent_dispatcher")
local event_actor_policy = require("src.ui.coord.event_actor_policy")
local view_command_ports = require("src.ui.ports.view_command")
local runtime_ports = require("src.foundation.ports.runtime_ports")
local runtime_ui = require("src.ui.render.support.runtime_ui")
local tip_queue = require("src.foundation.tips")
local logger = require("src.foundation.log")
local host_events = require("src.ui.seams.host_events")
local gift_code_port = require("src.ui.seams.gift_code")
local gift_code_screen = require("src.ui.screens.gift_code")
local canvas_coordinator = require("src.ui.coord.canvas_coordinator")
local panel_interrupt = require("src.ui.state.panel_interrupt")
local redeem = require("src.app.gift_code.redeem")
local transaction = require("src.app.cosmetics.transaction")
local skin_archive = require("src.app.cosmetics.skin_archive")

local ENTRY = "基础_礼包码"
local INPUT = "礼包码_输入框"
local CONFIRM = "礼包码_确认按钮"
local CANCEL = "礼包码_取消按钮"
local INPUT_NODE_ID = "1519736575|2075094127"
local SHOW_SCREEN = "显示礼包码屏"
local HIDE_SCREEN = "隐藏礼包码屏"

local NAILONG = 5005 -- 奶龙
local CAPYBARA = 5006 -- 水豚嘟嘟
local CODES = {
  { id = 3, code = "EGG2026", rewards = { NAILONG } },
  { id = 4, code = "CAPY2026", rewards = { CAPYBARA } },
}

local function _assert_eq(actual, expected, message)
  luassert.is.equal(expected, actual, message)
end

local function _make_role(role_id)
  local role = { events = {} }
  role.get_roleid = function()
    return role_id
  end
  role.send_ui_custom_event = function(event_name)
    role.events[#role.events + 1] = event_name
  end
  return role
end

local function _count(list, value)
  local n = 0
  for _, item in ipairs(list) do
    if item == value then
      n = n + 1
    end
  end
  return n
end

-- 宿主世界替身:两名玩家、内存存档(Int + Str)、按 role 记录输入框写入与提示。
local function _install_world()
  local world = {
    roles = { ["1"] = _make_role(1), ["2"] = _make_role(2) },
    store = {},
    input_writes = {},
    tips = {},
    input_handler = nil,
  }
  local function _key(role_id, key)
    return tostring(role_id) .. "|" .. tostring(key)
  end
  runtime_ports.configure({
    resolve_role = function(role_id)
      return world.roles[tostring(role_id)]
    end,
    resolve_roles = function()
      return { world.roles["1"], world.roles["2"] }
    end,
    archives_enabled = function()
      return true
    end,
    get_archive_int = function(role_id, key)
      return world.store[_key(role_id, key)] or 0
    end,
    set_archive_int = function(role_id, key, value)
      world.store[_key(role_id, key)] = value
      return true
    end,
    get_archive_str = function(role_id, key)
      return world.store[_key(role_id, key)] or ""
    end,
    set_archive_str = function(role_id, key, value)
      world.store[_key(role_id, key)] = value
      return true
    end,
    wall_now_seconds = function()
      return 0
    end,
  })
  host_events.configure({
    register_input_text_end = function(node_id, handler)
      if node_id == INPUT_NODE_ID then
        world.input_handler = handler
      end
      return true, "input-trigger"
    end,
  })
  tip_queue.clear()
  tip_queue.configure_runtime({
    presenter = function(text, _, tip)
      world.tips[#world.tips + 1] = { text = text, role_id = tip.role_id }
    end,
    scheduler = function(_, release)
      release()
      return true
    end,
  })
  return world
end

-- 输入框节点替身:写 text 时记下当前推送的目标玩家(client role)。
local function _input_node(world)
  return setmetatable({ id = INPUT_NODE_ID, name = INPUT }, {
    __newindex = function(_, key, value)
      if key == "text" then
        local role = runtime_ui.get_client_role()
        world.input_writes[#world.input_writes + 1] = {
          role_id = role and role.get_roleid() or nil,
          text = value,
        }
      end
    end,
  })
end

local function _new_state()
  return { ui = {}, gameplay_loop_ports = { view_command = view_command_ports.build() } }
end

local function _click(state, world, node_name, role_id)
  local data = { role = world.roles[tostring(role_id)] }
  for _, spec in ipairs(routes.build_route_specs(state)) do
    if spec.name == node_name then
      local intent = spec.build_intent(data)
      luassert.is_table(intent, "click on " .. node_name .. " should build an intent")
      luassert.is_true(event_actor_policy.attach_event_actor(state, intent, data),
        "click on " .. node_name .. " should attach the clicking player")
      intent_dispatcher.dispatch(state, nil, intent, {})
      return
    end
  end
  error("no click route for node: " .. node_name)
end

local function _type(world, role_id, text)
  luassert.is_function(world.input_handler, "input-text-end listener should be registered on the input field")
  world.input_handler("UI_INPUT_TEXT_END_EVENT", nil, { role = world.roles[tostring(role_id)], content = text })
end

local function _tips_for(world, role_id)
  local texts = {}
  for _, tip in ipairs(world.tips) do
    if tip.role_id == role_id then
      texts[#texts + 1] = tip.text
    end
  end
  return texts
end

describe("TestGiftCodeScreen", function()
  local world
  local state
  local original_query

  before_each(function()
    transaction.reset_for_tests()
    transaction.configure_archive(skin_archive)
    redeem.configure_codes_for_tests(CODES)
    gift_code_port.configure({ redeem = redeem.redeem })
    world = _install_world()
    original_query = UIManager.query_nodes_by_name
    local input_node = _input_node(world)
    UIManager.query_nodes_by_name = function(name)
      if name == INPUT then
        return { input_node }
      end
      return original_query(name)
    end
    state = _new_state()
    gift_code_screen.bind_input(state)
  end)

  after_each(function()
    UIManager.query_nodes_by_name = original_query
    UIManager.client_role = nil
    gift_code_port.reset_for_tests()
    transaction.reset_for_tests()
    redeem.reset_for_tests()
    tip_queue.clear()
    support.restore_runtime_services()
  end)

  it("test_clicking_entry_shows_the_screen_and_clears_the_input_for_that_player", function()
    _click(state, world, ENTRY, 1)

    _assert_eq(_count(world.roles["1"].events, SHOW_SCREEN), 1, "entry click should show the gift code screen to the clicker")
    _assert_eq(_count(world.roles["2"].events, SHOW_SCREEN), 0, "other players should not see the screen open")
    luassert.same({ { role_id = 1, text = "" } }, world.input_writes,
      "opening should blank the input field for the clicker only")
  end)

  it("test_confirm_after_input_enqueues_the_redeem_message_for_that_player_and_keeps_screen_open", function()
    _click(state, world, ENTRY, 1)
    _type(world, 1, "EGG2026")
    _click(state, world, CONFIRM, 1)

    luassert.same({ "兑换成功，获得：奶龙" }, _tips_for(world, 1), "redeem message should be tipped to the redeemer")
    luassert.same({}, _tips_for(world, 2), "other players should get no tip")
    _assert_eq(_count(world.roles["1"].events, HIDE_SCREEN), 0, "screen should stay open after redeeming")
  end)

  it("test_confirm_without_input_tips_invalid_code", function()
    _click(state, world, ENTRY, 1)
    _click(state, world, CONFIRM, 1)

    luassert.same({ "兑换码无效" }, _tips_for(world, 1), "empty input should be reported as an invalid code")
  end)

  it("test_reopening_the_screen_forgets_the_previous_input", function()
    _click(state, world, ENTRY, 1)
    _type(world, 1, "EGG2026")
    _click(state, world, CANCEL, 1)
    _click(state, world, ENTRY, 1)
    _click(state, world, CONFIRM, 1)

    luassert.same({ "兑换码无效" }, _tips_for(world, 1), "input typed before reopening should not be submitted")
  end)

  it("test_cancel_hides_the_screen_for_that_player", function()
    _click(state, world, ENTRY, 1)
    _click(state, world, CANCEL, 1)

    _assert_eq(_count(world.roles["1"].events, HIDE_SCREEN) >= 1, true, "cancel should hide the gift code screen")
    luassert.same({}, world.tips, "cancel should not tip anything")
  end)

  it("test_two_players_inputs_do_not_mix", function()
    _click(state, world, ENTRY, 1)
    _click(state, world, ENTRY, 2)
    _type(world, 1, "EGG2026")
    _type(world, 2, "WRONG")

    _click(state, world, CONFIRM, 2)
    _click(state, world, CONFIRM, 1)

    luassert.same({ "兑换码无效" }, _tips_for(world, 2), "player 2 should redeem their own input")
    luassert.same({ "兑换成功，获得：奶龙" }, _tips_for(world, 1), "player 1 should redeem their own input")
  end)

  -- 去重粒度是「同一玩家同一条提示」,不是「同一玩家同一状态」:连续兑换
  -- 两个不同码,第二条成功提示文本不同,必须排队展示而不是被吞(#195 review)。
  it("test_a_second_distinct_redeem_tip_is_not_swallowed_by_dedupe", function()
    local releases = {}
    tip_queue.configure_runtime({
      presenter = function(text, _, tip)
        world.tips[#world.tips + 1] = { text = text, role_id = tip.role_id }
      end,
      scheduler = function(_, release)
        releases[#releases + 1] = release
        return true
      end,
      test_mode = false,
    })
    _click(state, world, ENTRY, 1)
    _type(world, 1, "EGG2026")
    _click(state, world, CONFIRM, 1)
    luassert.same({ "兑换成功，获得：奶龙" }, _tips_for(world, 1), "first grant tip should be presented")

    _type(world, 1, "CAPY2026")
    _click(state, world, CONFIRM, 1)
    luassert.same({ "兑换成功，获得：奶龙" }, _tips_for(world, 1),
      "a distinct second tip must wait behind the active one, not be dropped")

    luassert.is_function(releases[1], "the active tip should hold a scheduled release")
    releases[1]()
    luassert.same({ "兑换成功，获得：奶龙", "兑换成功，获得：水豚嘟嘟" }, _tips_for(world, 1),
      "after the first tip releases, the second grant tip must be presented")
  end)

  -- 对照钉:同一条提示(同玩家同文本)重复触发仍去重,不刷屏。
  it("test_repeating_the_identical_tip_is_still_deduped", function()
    local releases = {}
    tip_queue.configure_runtime({
      presenter = function(text, _, tip)
        world.tips[#world.tips + 1] = { text = text, role_id = tip.role_id }
      end,
      scheduler = function(_, release)
        releases[#releases + 1] = release
        return true
      end,
      test_mode = false,
    })
    _click(state, world, ENTRY, 1)
    _click(state, world, CONFIRM, 1)
    _click(state, world, CONFIRM, 1)
    luassert.same({ "兑换码无效" }, _tips_for(world, 1), "identical repeat should be deduped")

    luassert.is_function(releases[1], "the active tip should hold a scheduled release")
    releases[1]()
    luassert.same({ "兑换码无效" }, _tips_for(world, 1), "no second copy should surface after release")
  end)

  -- 弹窗收屏/黑市开屏的 per-role 回屏按 canvas_coordinator 的面板态重解析
  -- (#583 分道):礼包码屏开着时必须解析为「开着的人的礼包码 canvas」,
  -- 否则广播弹窗收起后玩家被错误拽回基础屏(#195 review)。
  it("test_the_open_screen_resolves_as_the_role_s_panel_canvas_until_cancel", function()
    _click(state, world, ENTRY, 1)

    _assert_eq(canvas_coordinator.resolve_role_panel_canvas(state.ui, 1), "礼包码屏",
      "an open gift code screen should resolve as the clicker's panel canvas")
    luassert.is_nil(canvas_coordinator.resolve_role_panel_canvas(state.ui, 2),
      "a player without the screen open should have no panel canvas")

    _click(state, world, CANCEL, 1)
    luassert.is_nil(canvas_coordinator.resolve_role_panel_canvas(state.ui, 1),
      "after cancel the role should no longer resolve to the gift code canvas")
  end)

  -- #202:黑市开屏清场不再收礼包码屏。屏保持开着,也就不发「隐藏礼包码屏」
  -- 事件;操作者收屏后按面板态回到自己的礼包码 canvas。
  it("test_market_open_keeps_the_screen_and_emits_no_hide_event", function()
    _click(state, world, ENTRY, 1)
    state.ui.market_active = true
    state.ui.current_action_role_id = 1

    panel_interrupt.interrupt(state)

    luassert.is_true(state.ui.gift_code.open, "market open must not close the gift code screen")
    _assert_eq(_count(world.roles["1"].events, HIDE_SCREEN), 0,
      "an open gift code screen must not be hidden when the market opens")
  end)

  -- 键口径钉(#195 review):输入事件(data.role)与确认点击(intent 行动者)
  -- 对同一玩家的两种 id 表示(字符串 "1" / 数值 1)必须落同一条缓存键——
  -- 入缓存的玩家和确认的玩家是同一个键。
  it("test_cached_input_and_confirm_use_the_same_player_key_across_id_representations", function()
    local string_id_role = _make_role("1")
    _click(state, world, ENTRY, 1)
    luassert.is_function(world.input_handler, "input listener should be registered")
    world.input_handler("UI_INPUT_TEXT_END_EVENT", nil, { role = string_id_role, content = "EGG2026" })
    _click(state, world, CONFIRM, 1)

    luassert.same({ "兑换成功，获得：奶龙" }, _tips_for(world, 1),
      "the confirming player must read the cache written for the same player")
  end)

  -- 「宿主调用」节:宿主查询异常必须带 err 留 warn,不静默吞掉(#195 review)。
  it("test_a_host_error_while_querying_the_input_node_is_warned_with_the_error", function()
    UIManager.query_nodes_by_name = function(name)
      if name == INPUT then
        error("host boom: query denied")
      end
      return original_query(name)
    end
    local warns = {}
    local original_warn = logger.warn
    logger.warn = function(...)
      local parts = { ... }
      for i, part in ipairs(parts) do
        parts[i] = tostring(part)
      end
      warns[#warns + 1] = table.concat(parts, " ")
    end
    local bound = gift_code_screen.bind_input(state)
    logger.warn = original_warn

    luassert.is_false(bound, "binding should be skipped when the host query fails")
    luassert.truthy(#warns > 0, "a host query failure must leave a warn, not be swallowed")
    local found = false
    for _, line in ipairs(warns) do
      found = found or line:find("host boom", 1, true) ~= nil
    end
    luassert.truthy(found,
      "the warn should carry the host error for diagnosis, got: " .. table.concat(warns, " | "))
  end)

  it("test_decoration_nodes_have_no_click_routes", function()
    local decorations = {
      ["基础_礼包码文本"] = true,
      ["基础_礼包码图标"] = true,
      ["基础_礼包码环"] = true,
      ["基础_礼包码环_1"] = true,
      ["基础_礼包码动效"] = true,
    }
    local routed = {}
    for _, spec in ipairs(routes.build_route_specs(state)) do
      if decorations[spec.name] then
        routed[#routed + 1] = spec.name
      end
    end
    luassert.same({}, routed, "decoration nodes should carry no logic")
  end)
end)
