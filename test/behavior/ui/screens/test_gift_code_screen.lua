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
local host_events = require("src.ui.seams.host_events")
local gift_code_port = require("src.ui.seams.gift_code")
local gift_code_screen = require("src.ui.screens.gift_code")
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
local CODES = {
  { id = 3, code = "EGG2026", rewards = { NAILONG } },
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
