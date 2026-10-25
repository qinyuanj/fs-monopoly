-- Shared helpers for regression suites.
local M = {}
require("test.bootstrap").install_package_paths()
local luassert = require("packages.test_runner.cache_loader").verified_module("luassert")
  or assert(require("test.support.luassert_loader").load())

require("test.bootstrap")

local composition_root = require("src.app.compose_game")
local land_settlement = require("src.rules.land.settlement")
local choice_resolver = require("src.rules.choice.resolver")
local choice_contract = require("src.config.choice.contract")
local map_cfg = require("src.config.content.default_map")
local tiles_cfg = require("src.config.content.tiles")
local tile = require("src.rules.board.tile")
local test_env = require("test.support.env")
local presentation_runtime_deps = require("src.ui.coord.deps")
local presentation_ports = require("src.ui.ports")
local logger = require("src.foundation.log")
local tip_queue = require("src.foundation.tips")
local runtime_context = require("src.host.context")
local runtime_ports = require("src.foundation.ports.runtime_ports")
local runtime_default_ports = require("src.host.default_ports")
local paid_purchase_port = require("src.rules.ports.paid_purchase")
local achievement_progress_port = require("src.rules.ports.achievement_progress")
local share_panel_port = require("src.foundation.ports.share_panel")
local host_share_panel = require("src.host.share_panel")
local screen_openers_port = require("src.ui.seams.screen_openers")
local resolver_seam = require("src.ui.seams.local_actor_resolver")
local host_runtime_impl = require("src.host")

-- ui 宿主能力 port 基线（#250）：镜像 app/host_install.lua 装配，
-- impl 是 src.host 表本身且槽位按名调用时查表，spec 对 src.host 字段的 patch
-- 因此保持可截获。清单单一真源见 host_ports（#251）。
local ui_host_port_slots = require("src.ui.seams.host_ports")
local default_ports = require("src.turn.output.default_ports")
local runtime_state_seam = require("src.ui.state.runtime")
local landing_visual_hold_seam = require("src.ui.visual_hold")
local event_feed_adapter = require("src.turn.output.event_feed_adapter")
local ui_view = require("src.ui.coord.ui_runtime")
local function assert_eq(a, b, msg)
  luassert.is.equal(b, a, msg)
end

local function assert_player_move_dir(player, expected, msg)
  local status = player and player.status or nil
  assert_eq(status and status.move_dir or nil, expected, msg or "move_dir mismatch")
end

local function assert_tile_id_sequence(entries, expected_ids, msg)
  assert_eq(#entries, #expected_ids, (msg or "tile id sequence length mismatch"))
  for index, expected_id in ipairs(expected_ids) do
    local entry = entries[index]
    local actual_id = entry
    if type(entry) == "table" then
      if entry.tile and entry.tile.id ~= nil then
        actual_id = entry.tile.id
      else
        actual_id = entry.id
      end
    end
    assert_eq(actual_id, expected_id, (msg or "tile id sequence mismatch") .. " at slot " .. tostring(index))
  end
end

-- 与开局装配（src/app/gameplay_start.lua）同口径：view_command 端口复用回合端口包的
-- debug.sync_event_log。测试注入的端口包可能没有 debug 组，此时不传同步函数。
local function build_view_command_port(turn_ports)
  local debug = turn_ports and turn_ports.debug or nil
  return presentation_ports.build_view_command(debug and debug.sync_event_log or nil)
end

-- 一次装好回合端口包与 view_command 端口，返回 turn_ports, view_command_port。
local function build_presentation_ports()
  local turn_ports = presentation_ports.build()
  return turn_ports, build_view_command_port(turn_ports)
end

local function ensure_ui_runtime_for_test(state)
  luassert.truthy(type(state) == "table", "missing state")
  local ui_runtime = state.ui_runtime
  if type(ui_runtime) ~= "table" then
    ui_runtime = {}
    state.ui_runtime = ui_runtime
  end
  if type(state.presentation_runtime) ~= "table" then
    state.presentation_runtime = presentation_runtime_deps.build()
  end
  if type(state.gameplay_loop_ports) ~= "table" then
    state.gameplay_loop_ports = presentation_ports.build()
  end
  if type(state.view_command_port) ~= "table" then
    state.view_command_port = build_view_command_port(state.gameplay_loop_ports)
  end
  if type(state.board_scene) ~= "table" then
    state.board_scene = {
      tiles = {},
    }
  end
  if type(state.board_scene) == "table" and type(state.board_scene.presentation_runtime) ~= "table" then
    state.board_scene.presentation_runtime = state.presentation_runtime
  end
  return state
end

local _UI_RUNTIME_BIND_FIELDS = {
  "ui_model",
  "pending_choice",
  "pending_choice_id",
  "pending_choice_elapsed",
  "ui_modal_elapsed",
  "ui_modal_ref",
  "choice_visible_option_ids",
  "pending_choice_selected_option_id",
}

-- 按 game.board.path 铺一份完整板面场景桩（tiles/buildings/txt/overlay/ground），
-- 供驱动 ui_model_sync.refresh_from_dirty 全模型构建的套件共享（ui_sync 场景族）。
local function prepare_board_scene(state, game)
  local scene = {
    tiles = {},
    buildings = {},
    building_unit_groups = {},
    building_txt = {},
    overlay_units = {
      roadblocks = {},
      mines = {},
    },
    ground = {
      get_position = function()
        return math.Vector3(0, 0, 0)
      end,
    },
  }
  for index, _tile in ipairs(game.board.path) do
    local pos = math.Vector3(index, 0, 0)
    scene.tiles[index] = {
      get_position = function()
        return pos
      end,
    }
    scene.buildings[index] = {
      get_position = function()
        return math.Vector3(index, 1, 0)
      end,
    }
    scene.building_txt[index] = {
      set_billboard_text = function() end,
    }
  end
  state.board_scene = scene
  state.tile_units = scene.tiles
  state.tile_positions = nil
end

local function bind_ui_runtime(state)
  ensure_ui_runtime_for_test(state)
  local ui_runtime = state.ui_runtime
  for _, field in ipairs(_UI_RUNTIME_BIND_FIELDS) do
    if state[field] ~= nil and ui_runtime[field] == nil then
      ui_runtime[field] = state[field]
    end
  end
  -- ui_dirty deviates: coerce truthy → boolean true (other fields pass through).
  if state.ui_dirty ~= nil and ui_runtime.ui_dirty == nil then
    ui_runtime.ui_dirty = state.ui_dirty == true
  end
  return state
end

local function _refresh_runtime_context_for_tests()
  return test_env.refresh_runtime_context_for_tests({
    GameAPI = GameAPI,
    LuaAPI = LuaAPI,
    GlobalAPI = GlobalAPI,
    SetTimeOut = SetTimeOut,
    RegisterCustomEvent = RegisterCustomEvent,
    TriggerCustomEvent = TriggerCustomEvent,
    all_roles = all_roles,
    ALLROLES = ALLROLES,
    camera_helper = camera_helper,
  })
end

local _RUNTIME_CONTEXT_KEYS = {
  GameAPI = true,
  LuaAPI = true,
  SetTimeOut = true,
  RegisterCustomEvent = true,
  RegisterTriggerEvent = true,
  UnregisterTriggerEvent = true,
  TriggerCustomEvent = true,
  camera_helper = true,
  all_roles = true,
  ALLROLES = true,
}

local function _patches_need_context_refresh(patches)
  for _, patch in ipairs(patches) do
    local target = patch.target
    if (target == nil or target == _G) and _RUNTIME_CONTEXT_KEYS[patch.key] then
      return true
    end
  end
  return false
end

local function _refresh_runtime_services_for_tests()
  local ctx = runtime_context.current()
  if ctx == nil or ctx.env == nil then
    return _refresh_runtime_context_for_tests()
  end

  runtime_ports.reset_for_tests()
  runtime_ports.configure(runtime_default_ports.build(runtime_context))
  paid_purchase_port.reset_for_tests()
  paid_purchase_port.configure(require("src.host.paid_purchase_gateway"))
  achievement_progress_port.reset_for_tests()
  -- #463:share_panel 纯契约 port 的实现基线,镜像 host_install 装配(闭包在
  -- 调用时读模块字段,spec 对实现模块字段的 patch 保持可截获)。
  share_panel_port.reset_for_tests()
  share_panel_port.configure({
    try_show = function(...) return host_share_panel.try_show(...) end,
  })
  -- #332:local_actor_resolver 接缝基线,镜像 host_install 装配(闭包调用时
  -- 读实现模块字段,spec 对实现模块字段的 patch 保持可截获)。
  resolver_seam.reset_for_tests()
  resolver_seam.configure(require("src.ui.render.support.local_actor_resolver"))
  -- #332:screen_openers 接缝基线,镜像 host_install 装配。thunk 惰性 require
  -- 屏模块(自注册深模块,基线不提前装载)并在调用时读字段(patch 可截获)。
  screen_openers_port.reset_for_tests()
  screen_openers_port.configure({
    open_secondary_confirm = function(...)
      return require("src.ui.screens.secondary_confirm").open(...)
    end,
    open_pre_confirm = function(...)
      return require("src.ui.screens.secondary_confirm").open_pre_confirm(...)
    end,
    open_item_phase_pre_confirm = function(...)
      return require("src.ui.screens.secondary_confirm").open_item_phase_pre_confirm(...)
    end,
    refresh_secondary_confirm_copy = function(...)
      return require("src.ui.screens.secondary_confirm").refresh_copy(...)
    end,
    open_market = function(...)
      return require("src.ui.screens.market").open(...)
    end,
    close_market = function(...)
      return require("src.ui.screens.market").close(...)
    end,
  })
  for _, port in ipairs(ui_host_port_slots) do
    port.reset_for_tests()
    port.configure(host_runtime_impl)
  end
  tip_queue.configure_runtime({
    presenter = function(text, duration)
      if GlobalAPI and type(GlobalAPI.show_tips) == "function" then
        return GlobalAPI.show_tips(text, duration)
      end
      return false
    end,
    scheduler = function(delay, fn)
      if type(SetTimeOut) == "function" then
        return SetTimeOut(delay, fn)
      end
      if fn then
        fn()
        return true
      end
      return false
    end,
    test_mode = logger.is_test_mode(),
  })
  if GameAPI ~= nil
      and type(GameAPI.get_timestamp) == "function"
      and type(GameAPI.get_hour) == "function"
      and type(GameAPI.get_minute) == "function"
      and type(GameAPI.get_second) == "function" then
    logger.configure_game_time(GameAPI)
  else
    logger.reset_time_runtime()
  end
  return ctx
end

local function with_patches(patches, fn, opts)
  local patch_opts = opts or {}
  local originals = {}
  for i, patch in ipairs(patches) do
    local target = patch.target or _G
    originals[i] = { target = target, key = patch.key, value = target[patch.key] }
    target[patch.key] = patch.value
  end
  local need_refresh = not patch_opts.skip_runtime_context_refresh
      and _patches_need_context_refresh(patches)
  if need_refresh then
    _refresh_runtime_context_for_tests()
  elseif not patch_opts.skip_runtime_context_refresh then
    _refresh_runtime_services_for_tests()
  end
  local handler = debug and debug.traceback or function(err) return err end
  local ok, err = xpcall(fn, handler)
  for i = #originals, 1, -1 do
    local patch = originals[i]
    patch.target[patch.key] = patch.value
  end
  if need_refresh then
    _refresh_runtime_context_for_tests()
  elseif not patch_opts.skip_runtime_context_refresh then
    _refresh_runtime_services_for_tests()
  end
  if not ok then
    error(err)
  end
end

test_env.install_defaults()
_refresh_runtime_context_for_tests()

local function build_ui_port(overrides)
  local ui_state = ui_view.build_ui_state()
  local refs = {
    images = {
      ["Empty"] = "EMPTY",
    },
  }
  local port = {
    ui = ui_state,
    runtime_asset_context = { refs = refs },
    ui_model = nil,
    set_label = ui_state.set_label,
    set_visible = ui_state.set_visible,
    set_touch_enabled = ui_state.set_touch_enabled,
    query_node = ui_state.query_node,
    wait_move_anim = false,
    wait_action_anim = false,
    push_popup = function(_, _, _) end,
    show_tip = function(_, intent)
      if type(intent) ~= "table" then
        return false
      end
      if GlobalAPI and type(GlobalAPI.show_tips) == "function" then
        return GlobalAPI.show_tips(intent.text, intent.duration) == true
      end
      return false
    end,
    on_tile_owner_changed = function() end,
    on_tile_upgraded = function() end,
    build_model = function(state, game)
      return ui_view.build_model(state, game)
    end,
    refresh_from_dirty = function(game, state, dirty)
      return ui_view.refresh_from_dirty(game, state, dirty)
    end,
  }
  if overrides then
    for key, value in pairs(overrides) do
      port[key] = value
    end
  end
  return port
end

local function visited_tile_ids(board, visited)
  local list = {}
  for _, idx in ipairs(visited or {}) do
    local tile_ref = board:get_tile(idx)
    table.insert(list, tile_ref and tile_ref.id or idx)
  end
  return list
end

local function list_contains(list, value)
  for _, v in ipairs(list) do
    if v == value then
      return true
    end
  end
  return false
end

local function next_choice_id(game)
  local seq = game.turn.choice_seq or 0
  seq = seq + 1
  game.turn.choice_seq = seq
  return seq
end

local function open_choice(game, payload)
  luassert.truthy(game and game.turn, "Choice.open requires game.turn")
  payload = payload or {}
  local id = next_choice_id(game)
  local entry = {
    id = id,
    kind = payload.kind,
    title = payload.title or "请选择",
    body_lines = payload.body_lines or {},
    options = payload.options or {},
    allow_cancel = payload.allow_cancel ~= false,
    cancel_label = payload.cancel_label or "取消",
    meta = payload.meta,
  }
  choice_contract.copy_explicit_fields(payload, entry)
  game.turn.pending_choice = entry
  game.dirty.turn = true
  game.dirty.any = true
  return entry
end

local function get_choice(game)
  if not (game and game.turn) then
    return nil
  end
  return game.turn.pending_choice
end

local function resolve_choice_first(game, pending)
  if pending.options and #pending.options > 0 then
    local first = pending.options[1]
    choice_resolver.resolve(game, pending, { option_id = first.id or first })
    return true
  end
  if pending.allow_cancel then
    choice_resolver.resolve(game, pending, { type = "choice_cancel", choice_id = pending.id })
    return true
  end
  return false
end

local function resolve_landing(game, player, tile_ref, move_result, depth)
  local res = land_settlement.begin_landing_settlement(game, player and player.id or nil, {
    tile = tile_ref,
    move_result = move_result,
    depth = depth or 0,
  })
  if res and res.settled == true then
    return nil
  end
  return res
end

local function resolve_landing_with_choices(game, player, tile_ref, move_result, max_iterations)
  local res = resolve_landing(game, player, tile_ref, move_result, 0)
  local iteration = 0
  local limit = max_iterations or 10
  while res and res.waiting and iteration < limit do
    iteration = iteration + 1
    local pending = get_choice(game)
    if not pending then
      break
    end
    if not resolve_choice_first(game, pending) then
      break
    end
    if iteration < limit then
      local current_tile = game.board:get_tile(player.position)
      res = resolve_landing(game, player, current_tile, move_result, iteration)
    end
  end
  return res
end

local function new_game(opts)
  opts = opts or {}
  local game = composition_root.new_game(default_ports.resolve_game_opts({
    players = opts.players or { "P1", "P2" },
    ai = opts.ai or { [2] = true },
    auto_all = opts.auto_all == true,
    map = opts.map or map_cfg,
    tiles = opts.tiles or tiles_cfg,
  }))
  if opts.install_ui_port ~= false then
    game.ui_port = build_ui_port(opts.ui_port)
  end
  game.popup_port = {
    push_popup = function(_, payload, popup_opts)
      local ui_port = game.ui_port
      if ui_port and type(ui_port.push_popup) == "function" then
        return ui_port:push_popup(payload, popup_opts)
      end
      return false
    end,
  }
  game.tip_output_port = {
    enqueue = function(_, maybe_game, maybe_intent)
      local intent = maybe_intent
      if intent == nil and type(maybe_game) == "table" and maybe_game.text ~= nil then
        intent = maybe_game
      end
      local ui_port = game.ui_port
      if ui_port and type(ui_port.show_tip) == "function" then
        return ui_port:show_tip(intent) == true
      end
      if GlobalAPI and type(GlobalAPI.show_tips) == "function" and type(intent) == "table" then
        return GlobalAPI.show_tips(intent.text, intent.duration) == true
      end
      return false
    end,
  }
  game.anim_gate_port = {
    wait_move_anim = false,
    wait_action_anim = false,
  }
  game.tile_feedback_port = {
    on_tile_upgraded = function()
      return false
    end,
  }
  game.bankruptcy_feedback_port = {
    on_tiles_cleared = function()
      return false
    end,
  }
  game.event_feed_port = event_feed_adapter.new(game)
  return game
end

local function first_land_tile(board)
  for idx, tile_ref in ipairs(board.path) do
    if tile_ref.type == "land" then
      return idx, tile_ref
    end
  end
  error("no land tile found")
end

local function first_tile_by_type(board, t)
  for idx, tile_ref in ipairs(board.path) do
    if tile_ref.type == t then
      return idx, tile_ref
    end
  end
  error("no tile found for type=" .. tostring(t))
end

local function first_adjacent_land_pair(board)
  for idx = 1, #board.path - 1 do
    local a = board.path[idx]
    local b = board.path[idx + 1]
    if a.type == "land" and b.type == "land" then
      return idx, a, idx + 1, b
    end
  end
  error("no adjacent land tiles")
end

local function tile_state(game, tile_ref)
  local state = tile.get_state(game, tile_ref)
  return state or { owner_id = nil, level = 0 }
end

M.assert_eq = assert_eq
M.assert_player_move_dir = assert_player_move_dir
M.assert_tile_id_sequence = assert_tile_id_sequence
M.bind_ui_runtime = bind_ui_runtime
M.prepare_board_scene = prepare_board_scene
M.with_patches = with_patches
M.build_ui_port = build_ui_port
M.build_presentation_ports = build_presentation_ports
M.visited_tile_ids = visited_tile_ids
M.list_contains = list_contains
M.open_choice = open_choice
M.get_choice = get_choice
M.resolve_choice_first = resolve_choice_first
M.resolve_landing = resolve_landing
M.resolve_landing_with_choices = resolve_landing_with_choices
M.new_game = new_game
M.first_land_tile = first_land_tile
M.first_tile_by_type = first_tile_by_type
M.first_adjacent_land_pair = first_adjacent_land_pair
M.tile_state = tile_state
M.runtime_state = runtime_state_seam
M.landing_visual_hold = landing_visual_hold_seam
-- 把共享测试基线(runtime ports / 付费网关 / 成就端口 / tips runtime)装回本模块加载时
-- 建立的状态。谁把这些进程级端口拆到未配置态,谁负责在 teardown 里调本函数装回去——
-- 否则同进程后续 suite 会撞空端口,而全量车道靠 suite 顺序把它掩盖成偶发。
M.restore_runtime_services = _refresh_runtime_services_for_tests

local function _build_asset_context(image_refs)
  return {
    refs = {
      images = image_refs or {},
    },
  }
end

M.build_asset_context = _build_asset_context

function M.build_popup_view_state(refs, card_node)
  local function new_node(seed)
    local node = seed or {}
    if not node.listen then
      function node:listen(_, cb)
        self._listener_cb = cb
        return {
          destroy = function()
            self._listener_cb = nil
          end,
        }
      end
    end
    return node
  end
  local state = {
    ui = ui_view.build_ui_state(),
    runtime_asset_context = _build_asset_context(refs or { ["Empty"] = "EMPTY" }),
  }
  state.ui.choice_active = false
  state.ui.market_active = false
  local nodes = {
    ["卡牌展示屏"] = new_node(),
    ["卡牌展示_标题"] = new_node(),
    ["卡牌展示_图片"] = new_node(card_node or {}),
  }
  local function query_nodes_by_name(name)
    local node = nodes[name]
    if not node then
      node = new_node()
      nodes[name] = node
    end
    return { node }
  end
  return state, nodes, query_nodes_by_name
end

function M.build_role_with_events(role_id, events)
  return {
    get_roleid = function() return role_id end,
    send_ui_custom_event = function(event_name)
      events[#events + 1] = event_name
    end,
  }
end

function M.has_event(list, name)
  for _, value in ipairs(list or {}) do
    if value == name then
      return true
    end
  end
  return false
end

function M.build_choice_modal_state()
  local function new_node()
    local node = {}
    function node:listen(_, cb)
      self._listener_cb = cb
      return {
        destroy = function()
          self._listener_cb = nil
        end,
      }
    end
    return node
  end
  local state = {
    pending_choice_id = nil,
    pending_choice_elapsed = 0,
    pending_choice_selected_option_id = nil,
    ui = ui_view.build_ui_state(),
    runtime_asset_context = _build_asset_context({ ["Empty"] = "EMPTY" }),
  }
  bind_ui_runtime(state)
  local names = {
    "玩家选择屏", "玩家选择_标题",
    "玩家选择_槽位1", "玩家选择_槽位2", "玩家选择_槽位3", "玩家选择_槽位4",
    "位置选择屏", "位置_副标题", "位置_放置文本",
    "位置-槽位1按钮", "位置-槽位2按钮", "位置-槽位3按钮", "位置-槽位4按钮", "位置-槽位5按钮", "位置-槽位6按钮", "位置-槽位7按钮",
    "位置-槽位1文本", "位置-槽位2文本", "位置-槽位3文本", "位置-槽位4文本", "位置-槽位5文本", "位置-槽位6文本", "位置-槽位7文本",
    "位置-槽位1投影", "位置-槽位2投影", "位置-槽位3投影", "位置-槽位4投影", "位置-槽位5投影", "位置-槽位6投影", "位置-槽位7投影",
    "遥控骰子屏", "遥控骰子_标题", "遥控骰子_正文",
    "遥控骰子_选项_01", "遥控骰子_选项_02", "遥控骰子_选项_03",
    "遥控骰子_选项_04", "遥控骰子_选项_05", "遥控骰子_选项_06",
    "通用二次确认屏", "通用二次确认_标题", "通用二次确认_文本", "通用二次确认_确定按钮", "通用二次确认_取消",
    "卡牌展示屏", "卡牌展示_标题", "卡牌展示_图片",
    "黑市屏", "黑市_购买按钮", "黑市_关闭", "黑市_售价", "黑市_选中卡牌",
  }
  local nodes = {}
  for _, name in ipairs(names) do
    nodes[name] = new_node()
  end
  local function query_nodes_by_name(name)
    local node = nodes[name]
    if not node then
      node = new_node()
      nodes[name] = node
    end
    return { node }
  end
  return state, nodes, query_nodes_by_name
end

function M.ui_runtime(state)
  return runtime_state_seam.ensure_ui_runtime(state)
end

-- 背包占用计数(CONTEXT「道具槽位」 稳定槽位):跳过 false 空洞,空洞守卫口径只此一处,
-- 各 spec 不得再手搓 _count_item 同形 helper。
function M.count_item(player, item_id)
  local count = 0
  for _, item in ipairs(player.inventory.items or {}) do
    if item ~= false and item.id == item_id then
      count = count + 1
    end
  end
  return count
end

return M
