-- #199 / #195 User Stories 20–23:礼包码屏接线。经节点点击路由(route spec →
-- 意图派发)与宿主「输入框输入完成」事件驱动,观察宿主侧可见行为:按玩家收到的
-- canvas 显隐事件、按玩家写入输入框的文本、按玩家入队的提示。兑换经礼包码 seam
-- 注入假实现(#204:屏只把 { status, granted } 映射为提示,兑换规则由
-- test/behavior/rules/test_skin_ownership_redeem.lua 覆盖);角色只在 runtime_ports
-- 边界替身;输入事件只在 host_events 端口替身;输入框与入口节点只在 UIManager 查询
-- 边界替身(#224:入口按钮及装饰节点按玩家记录显隐写入)。
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
local gift_code_nodes = require("src.ui.schema.gift_code")
local panel_interrupt = require("src.ui.state.panel_interrupt")
local modal_presenter = require("src.ui.coord.modal")
local runtime_state = require("src.ui.state.runtime")
local gift_codes = require("src.config.content.gift_codes")

local ENTRY = "基础_礼包码"
local INPUT = "礼包码_输入框"
local CONFIRM = "礼包码_确认按钮"
local CANCEL = "礼包码_取消按钮"
local INPUT_NODE_ID = "1519736575|2075094127"
local SHOW_SCREEN = "显示礼包码屏"
local HIDE_SCREEN = "隐藏礼包码屏"

local NAILONG = 5005 -- 奶龙
local CAPYBARA = 5006 -- 水豚嘟嘟
-- 兑换假实现:按输入原文给结果,其余一律 invalid_code;记录每次调用。
local REDEEM_RESULTS = {
  EGG2026 = { status = "granted", granted = { NAILONG } },
  CAPY2026 = { status = "granted", granted = { CAPYBARA } },
  RETRY2026 = { status = "write_failed", granted = {} },
}
-- 入口按钮与装饰节点(「基础_礼包码动效」同名两个)。
local ENTRY_NODES = {
  "基础_礼包码", "基础_礼包码文本", "基础_礼包码图标",
  "基础_礼包码环", "基础_礼包码环_1", "基础_礼包码动效", "基础_礼包码动效",
}

-- 兑换 seam 假实现:redeem 按输入原文给结果,其余一律 invalid_code;
-- owns_all_rewards 按 owners 表(role_id 字符串 → true)回答。
local function _fake_redeem(calls, owners)
  return {
    redeem = function(redeem_state, role_id, input_text)
      calls[#calls + 1] = { state = redeem_state, role_id = role_id, input_text = input_text }
      return REDEEM_RESULTS[input_text] or { status = "invalid_code", granted = {} }
    end,
    owns_all_rewards = function(_, role_id)
      return owners[tostring(role_id)] == true
    end,
  }
end

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

-- 事件流中最后一次出现的下标;0 表示没有出现过。
local function _last_index(list, value)
  local found = 0
  for i, item in ipairs(list) do
    if item == value then
      found = i
    end
  end
  return found
end

-- 宿主世界替身:两名玩家、内存存档(Int + Str)、按 role 记录输入框写入与提示。
local function _install_world()
  local world = {
    roles = { ["1"] = _make_role(1), ["2"] = _make_role(2) },
    store = {},
    input_writes = {},
    entry_writes = {},
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
    -- #226:world.timers 为 nil 时同步执行(宿主无延时接口时的口径);置为表后排队,
    -- 由 _run_timers 模拟到点,用来复现「点击先于输入完成」的宿主事件顺序。
    schedule = function(delay, fn)
      if world.timers == nil then
        fn()
        return
      end
      world.timers[#world.timers + 1] = { delay = delay, fn = fn }
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

-- 入口节点替身:写 visible 时记下 { role_id, name, visible }(role_id 为当前推送的玩家)。
local function _entry_node(world, name)
  return setmetatable({ name = name }, {
    __newindex = function(_, key, value)
      if key == "visible" then
        local role = runtime_ui.get_client_role()
        world.entry_writes[#world.entry_writes + 1] = {
          role_id = role and role.get_roleid() or nil,
          name = name,
          visible = value,
        }
      end
    end,
  })
end

local function _entry_nodes(world)
  local by_name = {}
  for _, name in ipairs(ENTRY_NODES) do
    by_name[name] = by_name[name] or {}
    table.insert(by_name[name], _entry_node(world, name))
  end
  return by_name
end

-- 期望的入口显隐写入:按玩家把入口按钮与每个装饰节点(同名全量)写成 visible。
local function _entry_writes_for(role_id, visible)
  local writes = {}
  for _, name in ipairs(ENTRY_NODES) do
    writes[#writes + 1] = { role_id = role_id, name = name, visible = visible }
  end
  return writes
end

-- 收集 warn;经 with_patches 保证测试体抛错时也装回 logger.warn。
local function _with_warns(fn)
  local warns = {}
  support.with_patches({
    {
      target = logger,
      key = "warn",
      value = function(...)
        warns[#warns + 1] = table.concat({ ... }, " ")
      end,
    },
  }, fn, { skip_runtime_context_refresh = true })
  return warns
end

local function _new_state()
  return { ui = {}, view_command_port = view_command_ports.build() }
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

local function _run_timers(world)
  local timers = world.timers
  world.timers = {}
  for _, timer in ipairs(timers) do
    timer.fn()
  end
end

local function _redeemed_texts(calls)
  local texts = {}
  for _, call in ipairs(calls) do
    texts[#texts + 1] = tostring(call.input_text)
  end
  return texts
end

describe("TestGiftCodeScreen", function()
  local world
  local state
  local original_query
  local redeem_calls
  local owners

  before_each(function()
    -- 本文件验证礼包码屏接线本身,入口开关打开(关闭态另有用例)。
    gift_code_screen.configure_entry_for_tests(true)
    redeem_calls = {}
    owners = {}
    gift_code_port.configure(_fake_redeem(redeem_calls, owners))
    world = _install_world()
    original_query = UIManager.query_nodes_by_name
    local input_node = _input_node(world)
    local entry_nodes = _entry_nodes(world)
    UIManager.query_nodes_by_name = function(name)
      if name == INPUT then
        return { input_node }
      end
      if entry_nodes[name] ~= nil then
        return entry_nodes[name]
      end
      return original_query(name)
    end
    state = _new_state()
    gift_code_screen.bind_input(state)
  end)

  after_each(function()
    gift_code_screen.reset_entry_for_tests()
    UIManager.query_nodes_by_name = original_query
    UIManager.client_role = nil
    gift_code_port.reset_for_tests()
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

  it("test_confirm_after_input_enqueues_the_redeem_message_for_that_player", function()
    _click(state, world, ENTRY, 1)
    _type(world, 1, "EGG2026")
    _click(state, world, CONFIRM, 1)

    luassert.same({ "兑换成功，获得：奶龙" }, _tips_for(world, 1), "redeem message should be tipped to the redeemer")
    luassert.same({}, _tips_for(world, 2), "other players should get no tip")
  end)

  -- #224:兑换成功或奖励已全部拥有时自动收屏(同取消:清草稿、清输入框、切回基础屏),
  -- 并只对这名玩家隐藏入口按钮及装饰节点;提示照常入队。
  it("test_granted_or_all_owned_closes_the_screen_clears_the_draft_and_hides_the_entry_for_that_player", function()
    local cases = {
      { status = "granted", granted = { NAILONG }, text = "兑换成功，获得：奶龙" },
      { status = "all_owned", text = gift_codes.messages.all_owned },
    }
    for _, case in ipairs(cases) do
      gift_code_port.configure({
        redeem = function()
          return { status = case.status, granted = case.granted or {} }
        end,
        owns_all_rewards = function()
          return false
        end,
      })
      world.roles["1"].events = {}
      world.input_writes = {}
      world.entry_writes = {}
      world.tips = {}
      tip_queue.clear()
      _click(state, world, ENTRY, 1)
      _type(world, 1, "EGG2026")
      _click(state, world, CONFIRM, 1)

      luassert.same({ case.text }, _tips_for(world, 1), case.status .. ": the result should still be tipped")
      luassert.is_true(_last_index(world.roles["1"].events, SHOW_SCREEN)
        < _last_index(world.roles["1"].events, HIDE_SCREEN), case.status .. ": the screen should close")
      _assert_eq(_count(world.roles["2"].events, HIDE_SCREEN), 0, case.status .. ": others' screens are untouched")
      luassert.same({ { role_id = 1, text = "" }, { role_id = 1, text = "" } }, world.input_writes,
        case.status .. ": opening and auto-closing should both leave the input blank")
      luassert.same(_entry_writes_for(1, false), world.entry_writes,
        case.status .. ": the entry and its decorations should be hidden for the redeemer only")

      world.input_writes = {}
      gift_code_screen.open(state, 1)
      luassert.same({ { role_id = 1, text = "" } }, world.input_writes,
        case.status .. ": reopening after auto-close should not refill the old draft")
      gift_code_screen.cancel(state, 1)
    end
  end)

  -- #226 真机取证:宿主先派发兑换按钮点击,再派发输入框失焦带出的「输入完成」。
  -- 兑换须等这次点击带出的输入落进草稿,而不是读点击前的缓存。
  it("test_confirm_redeems_the_input_committed_by_the_same_click", function()
    _click(state, world, ENTRY, 1)
    world.timers = {}
    _click(state, world, CONFIRM, 1)
    _type(world, 1, "EGG2026")

    luassert.same({}, _tips_for(world, 1), "nothing should be redeemed before the input settles")
    luassert.is_true(world.timers[1] ~= nil and world.timers[1].delay > 0, "confirm should defer the redeem")
    _run_timers(world)

    luassert.same({ "EGG2026" }, _redeemed_texts(redeem_calls), "the freshly committed input should be redeemed")
    luassert.same({ "兑换成功，获得：奶龙" }, _tips_for(world, 1), "the redeem result should be tipped")
    luassert.is_true(_last_index(world.roles["1"].events, SHOW_SCREEN)
      < _last_index(world.roles["1"].events, HIDE_SCREEN), "a granted redeem should close the screen")
  end)

  it("test_confirm_redeems_the_new_input_rather_than_a_stale_draft", function()
    _click(state, world, ENTRY, 1)
    _type(world, 1, "WRONG2026")
    world.timers = {}
    _click(state, world, CONFIRM, 1)
    _type(world, 1, "EGG2026")
    _run_timers(world)

    luassert.same({ "EGG2026" }, _redeemed_texts(redeem_calls), "the stale draft should not be redeemed")
    luassert.same({ "兑换成功，获得：奶龙" }, _tips_for(world, 1), "only the new code's result should be tipped")
  end)

  it("test_repeated_confirms_while_pending_redeem_once", function()
    _click(state, world, ENTRY, 1)
    world.timers = {}
    _click(state, world, CONFIRM, 1)
    _type(world, 1, "RETRY2026")
    _click(state, world, CONFIRM, 1)
    _run_timers(world)

    luassert.same({ "RETRY2026" }, _redeemed_texts(redeem_calls), "a pending confirm should absorb repeated clicks")

    _click(state, world, CONFIRM, 1)
    _run_timers(world)
    luassert.same({ "RETRY2026", "RETRY2026" }, _redeemed_texts(redeem_calls),
      "once settled, the next confirm should redeem again")
  end)

  it("test_cancel_while_pending_drops_the_redeem", function()
    _click(state, world, ENTRY, 1)
    world.timers = {}
    _click(state, world, CONFIRM, 1)
    _type(world, 1, "EGG2026")
    _click(state, world, CANCEL, 1)
    _run_timers(world)

    luassert.same({}, _redeemed_texts(redeem_calls), "a cancelled confirm should not redeem")
    luassert.same({}, _tips_for(world, 1), "a cancelled confirm should tip nothing")
  end)

  it("test_other_redeem_outcomes_keep_the_screen_the_draft_and_the_entry", function()
    local results = {
      { status = "invalid_code" }, { status = "expired" }, { status = "already_redeemed" },
      { status = "archive_unavailable" }, { status = "write_failed", granted = { NAILONG } },
      false,
    }
    for _, result in ipairs(results) do
      local label = result and result.status or "nil result"
      gift_code_port.configure({
        redeem = function()
          if not result then
            return nil
          end
          return { status = result.status, granted = result.granted or {} }
        end,
      })
      world.roles["1"].events = {}
      world.entry_writes = {}
      _click(state, world, ENTRY, 1)
      _type(world, 1, "EGG2026")
      _click(state, world, CONFIRM, 1)

      _assert_eq(_count(world.roles["1"].events, HIDE_SCREEN), 0, label .. ": the screen should stay open")
      luassert.same({}, world.entry_writes, label .. ": the entry should stay as it is")
      world.input_writes = {}
      _click(state, world, ENTRY, 1)
      luassert.same({ { role_id = 1, text = "EGG2026" } }, world.input_writes,
        label .. ": the draft should be kept for a retry")
    end
  end)

  -- #224:按玩家刷新入口——seam 查询为「已拥有全部在用码奖励」时只对这名玩家
  -- 隐藏入口,否则只对这名玩家显示。
  it("test_refreshing_the_entry_follows_the_player_s_ownership_and_touches_only_that_player", function()
    owners["1"] = true

    gift_code_screen.refresh_entry(state, 1)
    gift_code_screen.refresh_entry(state, 2)

    local expected = _entry_writes_for(1, false)
    for _, write in ipairs(_entry_writes_for(2, true)) do
      expected[#expected + 1] = write
    end
    luassert.same(expected, world.entry_writes, "each player's entry should follow their own ownership")
  end)

  it("test_refreshing_the_entry_does_nothing_when_the_entry_is_switched_off", function()
    gift_code_screen.configure_entry_for_tests(false)
    owners["1"] = true

    gift_code_screen.refresh_entry(state, 1)
    gift_code_screen.refresh_entry(state, 2)

    luassert.same({}, world.entry_writes, "the global switch-off is handled at GAME_INIT, not per player")
  end)

  -- 按玩家写入不得退化为全服写入:解析不出玩家时不写任何入口节点,留 warn。
  it("test_refreshing_the_entry_for_an_unresolved_player_writes_nothing_and_warns", function()
    local warns = _with_warns(function()
      gift_code_screen.refresh_entry(state, 99)
    end)

    luassert.same({}, world.entry_writes, "no player's entry should be touched")
    luassert.truthy(#warns > 0, "skipping should be diagnosable")
  end)

  it("test_refreshing_the_entry_without_an_installed_query_keeps_it_visible_and_warns", function()
    gift_code_port.reset_for_tests()
    local warns = _with_warns(function()
      gift_code_screen.refresh_entry(state, 1)
    end)

    luassert.same(_entry_writes_for(1, true), world.entry_writes, "unknown ownership should keep the entry")
    luassert.truthy(#warns > 0, "a missing seam should be diagnosable")
  end)

  it("test_confirm_passes_the_root_state_role_and_draft_to_redeem", function()
    _click(state, world, ENTRY, 1)
    _type(world, 1, "EGG2026")
    _click(state, world, CONFIRM, 1)

    _assert_eq(redeem_calls[1].state, state, "redeem receives the root state")
    _assert_eq(redeem_calls[1].role_id, 1, "redeem receives the confirming role")
    _assert_eq(redeem_calls[1].input_text, "EGG2026", "redeem receives the cached draft")
  end)

  -- #204:兑换结果只带领域状态,提示模板由本屏按 status 取配置;granted 填入
  -- 发放皮肤名(顿号分隔)。
  it("test_each_redeem_status_is_tipped_with_its_configured_message", function()
    local results = {
      { status = "granted", granted = { NAILONG, CAPYBARA }, text = "兑换成功，获得：奶龙、水豚嘟嘟" },
      { status = "all_owned", text = gift_codes.messages.all_owned },
      { status = "expired", text = gift_codes.messages.expired },
      { status = "already_redeemed", text = gift_codes.messages.already_redeemed },
      { status = "archive_unavailable", text = gift_codes.messages.archive_unavailable },
      { status = "write_failed", granted = { NAILONG }, text = gift_codes.messages.write_failed },
    }
    for role_id, case in ipairs(results) do
      gift_code_port.configure({
        redeem = function()
          return { status = case.status, granted = case.granted or {} }
        end,
      })
      local role = role_id % 2 + 1
      tip_queue.clear()
      world.tips = {}
      _click(state, world, ENTRY, role)
      _click(state, world, CONFIRM, role)
      luassert.same({ case.text }, _tips_for(world, role), case.status .. " tip")
    end
  end)

  it("test_a_missing_redeem_result_or_unknown_status_tips_nothing", function()
    for _, result in ipairs({ false, { status = "mystery", granted = {} } }) do
      gift_code_port.configure({
        redeem = function()
          return result or nil
        end,
      })
      _click(state, world, ENTRY, 1)
      _click(state, world, CONFIRM, 1)
    end
    luassert.same({}, _tips_for(world, 1), "nothing to tip")
  end)

  it("test_confirm_without_input_tips_invalid_code", function()
    _click(state, world, ENTRY, 1)
    _click(state, world, CONFIRM, 1)

    luassert.same({ "兑换码无效" }, _tips_for(world, 1), "empty input should be reported as an invalid code")
  end)

  -- 草稿口径(#201,取代 #195 Story 20):取消 = 明确放弃,是唯一清草稿的路径;
  -- 开屏不再无条件清缓存,而是按玩家回填。
  it("test_cancel_clears_the_draft_so_reopening_forgets_the_previous_input", function()
    _click(state, world, ENTRY, 1)
    _type(world, 1, "EGG2026")
    _click(state, world, CANCEL, 1)
    world.input_writes = {}
    _click(state, world, ENTRY, 1)
    luassert.same({ { role_id = 1, text = "" } }, world.input_writes,
      "reopening after cancel should refill an empty input")
    _click(state, world, CONFIRM, 1)

    luassert.same({ "兑换码无效" }, _tips_for(world, 1), "input typed before cancel should not be submitted")
  end)

  it("test_reopening_without_cancel_refills_the_draft_and_it_still_redeems", function()
    _click(state, world, ENTRY, 1)
    _type(world, 1, "EGG2026")
    world.input_writes = {}
    _click(state, world, ENTRY, 1)

    luassert.same({ { role_id = 1, text = "EGG2026" } }, world.input_writes,
      "reopening without cancel should refill the player's draft")
    _click(state, world, CONFIRM, 1)
    luassert.same({ "兑换成功，获得：奶龙" }, _tips_for(world, 1), "the refilled draft should still redeem")
  end)

  it("test_drafts_are_refilled_per_player_on_reopen", function()
    _click(state, world, ENTRY, 1)
    _type(world, 1, "EGG2026")
    _click(state, world, ENTRY, 2)
    world.input_writes = {}
    _click(state, world, ENTRY, 1)
    _click(state, world, ENTRY, 2)

    luassert.same({ { role_id = 1, text = "EGG2026" }, { role_id = 2, text = "" } }, world.input_writes,
      "each player should be refilled with their own draft only")
  end)

  -- #195 Story 23(#224 起只覆盖不收屏的结果):兑换失败屏不关,草稿保留到点取消为止。
  it("test_a_failed_redeem_keeps_the_draft_until_cancel", function()
    _click(state, world, ENTRY, 1)
    _type(world, 1, "RETRY2026")
    _click(state, world, CONFIRM, 1)
    world.input_writes = {}
    _click(state, world, ENTRY, 1)
    luassert.same({ { role_id = 1, text = "RETRY2026" } }, world.input_writes,
      "a failed redeem should not clear the draft")

    _click(state, world, CANCEL, 1)
    luassert.same({ { role_id = 1, text = "RETRY2026" }, { role_id = 1, text = "" } }, world.input_writes,
      "cancel should blank the input field as well as the draft")

    world.input_writes = {}
    _click(state, world, ENTRY, 1)
    luassert.same({ { role_id = 1, text = "" } }, world.input_writes,
      "after cancel the draft should be gone")
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

  -- #202:选择屏 / 黑市收屏统一到 per-role 面板回屏:开着礼包码屏的角色收到
  -- 「显示礼包码屏」,没开面板的角色收到「显示基础屏」。
  it("test_choice_close_returns_each_role_to_its_own_canvas", function()
    _click(state, world, ENTRY, 1)
    local shows_before = _count(world.roles["1"].events, SHOW_SCREEN)

    modal_presenter.close_choice_modal(state)

    luassert.is_true(_count(world.roles["1"].events, SHOW_SCREEN) > shows_before,
      "the role with the gift code screen open should be shown the gift code screen again")
    _assert_eq(_count(world.roles["2"].events, SHOW_SCREEN), 0,
      "a role without the gift code screen open should not be switched to it")
    luassert.is_true(_count(world.roles["2"].events, "显示基础屏") >= 1,
      "a role without any open panel should be returned to the base canvas")
  end)

  -- #202 review:base_inline 的内联选项住在基础屏。走到这条开屏路径时若已有选择屏
  -- 要收,收屏的 per-role 面板回屏会把开着礼包码屏的操作者留在面板 canvas,随后
  -- 开出的内联选项被面板盖住——开屏路径必须显式把角色切回基础屏。
  -- 判据用事件顺序:最后一次「显示基础屏」必须晚于最后一次「显示礼包码屏」。
  it("test_base_inline_open_returns_the_operator_to_the_base_canvas", function()
    _click(state, world, ENTRY, 1)
    state.ui.choice_active = true
    state.ui.active_choice_screen_key = "target_pick"
    runtime_state.set_ui_model(state, {
      current_player_id = 1,
      item_slots_by_player_id = { [1] = {} },
    })
    local events = world.roles["1"].events

    modal_presenter.open_choice_modal(state, { id = 7, route_key = "base_inline" })

    luassert.is_true(_last_index(events, SHOW_SCREEN) < _last_index(events, "显示基础屏"),
      "opening a base_inline choice must leave the operator on the base canvas")
    _assert_eq(canvas_coordinator.resolve_role_panel_canvas(state.ui, 1), gift_code_nodes.canvas,
      "sanity: the gift code panel itself stays open, only the canvas must move")
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

  it("test_disabled_entry_has_no_click_route", function()
    gift_code_screen.configure_entry_for_tests(false)

    luassert.has_error(function()
      _click(state, world, ENTRY, 1)
    end, nil, "disabled gift code entry must not route clicks")
    _assert_eq(_count(world.roles["1"].events, SHOW_SCREEN), 0, "the screen should stay closed")
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
