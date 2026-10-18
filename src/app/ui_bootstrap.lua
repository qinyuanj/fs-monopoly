local board_scene = require("src.ui.render.board.scene")
local ui_view = require("src.ui.coord.ui_runtime")
local canvas_event_router = require("src.ui.coord.canvas_event_router")
local canvas_coordinator = require("src.ui.coord.canvas_coordinator")
local base_nodes = require("src.ui.schema.base")
local bootstrap_nodes = require("src.app.ui_bootstrap_nodes")
local market_ui = require("src.ui.schema.market_layout")
local item_atlas_view = require("src.ui.render.widgets.item_atlas")
local ui_events = require("src.ui.coord.ui_events")
local timing = require("src.config.gameplay.timing")
local runtime_ports = require("src.foundation.ports.runtime_ports")
local role_globals = require("src.state.ui_role_globals")
local runtime_context = require("src.host.context")
local like_collect_subscribe = require("src.host.like_collect_subscribe")

local M = {}

local function _synthetic_registry()
  local runtime_ctx = runtime_context.current()
  return runtime_ctx and runtime_ctx.synthetic_actor_registry or nil
end

local function _registry_ready(registry)
  return registry ~= nil and type(registry.register_specs) == "function" and type(registry.spawn_pending) == "function"
end

local function _startup_specs(current_game)
  return current_game and current_game.startup_synthetic_players or nil
end

local function _board_map(current_game)
  return current_game and current_game.board and current_game.board.map or nil
end

function M.spawn_startup_synthetic_actors(current_game)
  local registry = _synthetic_registry()
  if not _registry_ready(registry) then
    return
  end
  registry.register_specs(_startup_specs(current_game))
  registry.spawn_pending(_board_map(current_game))
end

local function _install_role_globals()
  role_globals.install(runtime_ports.resolve_roles())
end

local function _node_label(id, entry)
  local name = type(entry) == "table" and entry[1] or nil
  if type(name) == "string" and name ~= "" then
    return name .. "(" .. tostring(id) .. ")"
  end
  return tostring(id)
end

-- Records every child of `id` that is not itself a configured node. `seen` keeps
-- each missing child reported once across the whole sweep.
local function _missing_child(child_id, ui_manager_nodes, seen)
  return child_id ~= nil and ui_manager_nodes[child_id] == nil and not seen[child_id]
end

local function _assert_children_read(ok, children, id, entry)
  if not ok then
    error("UI 节点子节点读取失败: " .. _node_label(id, entry) .. ": " .. tostring(children))
  end
end

local function _collect_missing_children(ui_manager_nodes, id, entry, missing, seen)
  local ok, children = pcall(GameAPI.get_eui_children, id)
  _assert_children_read(ok, children, id, entry)
  if type(children) ~= "table" then
    return
  end
  for _, child_id in ipairs(children) do
    if _missing_child(child_id, ui_manager_nodes, seen) then
      missing[#missing + 1] = _node_label(id, entry) .. " -> " .. tostring(child_id)
      seen[child_id] = true
    end
  end
end

-- 宿主未装载 GameAPI 或未提供子节点查询时,校验整体跳过(返回空)。
local function _has_children_lookup()
  return GameAPI and type(GameAPI.get_eui_children) == "function"
end

local function _validate_configured_child_nodes(ui_manager_nodes)
  if not _has_children_lookup() then
    return {}
  end

  local missing = {}
  local seen = {}
  for id, entry in pairs(ui_manager_nodes or {}) do
    if type(entry) == "table" then
      _collect_missing_children(ui_manager_nodes, id, entry, missing, seen)
    end
  end
  return missing
end

local function _build_ui_manager_nodes()
  require("src.ui.manager.utils")
  local ui_manager_nodes = require("Data.UIManagerNodes")
  local missing_child_nodes = _validate_configured_child_nodes(ui_manager_nodes)
  if #missing_child_nodes > 0 then
    error("UI 节点配置缺失: " .. table.concat(missing_child_nodes, ", "))
  end
  UIManager.Builder:new(ui_manager_nodes)
  return ui_manager_nodes
end

local function _resolve_current_game(state, current_game_ref, opts)
  local current_game = current_game_ref[1]
  if not current_game and type(opts.start_runtime) == "function" then
    current_game = opts.start_runtime(state, current_game_ref)
  end
  assert(current_game ~= nil, "missing current_game")
  return current_game
end

local function _bind_current_game(state, current_game_ref)
  canvas_event_router.bind(state, function()
    return current_game_ref[1]
  end)
end

local function _sync_ui_event_roles()
  if ui_events.set_roles then
    ui_events.set_roles(runtime_ports.resolve_roles())
  end
end

local function _assert_required_ui_nodes(ui_manager_nodes)
  bootstrap_nodes.assert_required_nodes(ui_manager_nodes, {
    extra = market_ui.item_buttons or {},
  })
end

local function _initialize_game_ui(state, current_game)
  ui_events.send_to_all(ui_events.show["加载屏"], {})
  local board_map = current_game and current_game.board and current_game.board.map or nil
  M.spawn_startup_synthetic_actors(current_game)
  board_scene.init(state, board_map, current_game)
  ui_view.init_ui_assets(state)
  ui_view.capture_player_colors(state, current_game)
  -- 放大卡覆盖层编辑器默认可见性不可靠,开局统一压灭,展示时再按 role 点亮
  -- （#544:覆盖层住图鉴 canvas,显隐走 per-role 路径,只推浏览者客户端）。
  item_atlas_view.hide_enlarged(state)
end

local function _schedule_loading_transition(state)
  runtime_ports.schedule(timing.loading_to_game_transition_seconds, function()
    ui_events.send_to_all(ui_events.hide["加载屏"], {})
    canvas_coordinator.switch(state.ui, base_nodes.canvas)
  end)
end

-- current_game_ref 是一个单元素数组 { nil }，供 set/get 当前 game 使用
function M.install(state, current_game_ref, opts)
  opts = opts or {}
  RegisterTriggerEvent({ EVENT.GAME_INIT }, function()
    -- UIManager modules cache role globals during require.
    _install_role_globals()
    local ui_manager_nodes = _build_ui_manager_nodes()
    local current_game = _resolve_current_game(state, current_game_ref, opts)
    _bind_current_game(state, current_game_ref)
    _sync_ui_event_roles()
    _assert_required_ui_nodes(ui_manager_nodes)
    _initialize_game_ui(state, current_game)
    -- #466:点赞/收藏/订阅事件链路开局接线——setup 幂等注册三个 UI 自定义事件
    -- 监听并调度进图 0.1s 订阅检测。真机无需编辑器侧开局触发器,参考伪人检查站
    -- 守卫蛋仔岛 Person.lua 的开局直注册模式。
    like_collect_subscribe.setup(current_game)
    _schedule_loading_transition(state)
  end)
end

return M

