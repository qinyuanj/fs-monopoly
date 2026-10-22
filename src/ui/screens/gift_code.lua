-- gift_code(礼包码屏)屏:点击意图 + 开关屏 + 输入缓存 + 兑换提交,单一归宿(#199)。
--
-- 这是 canvas 面,不是选择屏:没有 descriptor / open / canvas 三契约(详见
-- screens_registry 的说明)。入口按钮住基础屏(route_base 发 open_gift_code_screen)。
-- 宿主没有读取输入框文本的接口:监听「输入框输入完成」事件按玩家缓存最近一次输入,
-- 点确认时把缓存交给兑换门面(经 seams/gift_code 注入),没有缓存按空输入处理;
-- 开屏时清空输入框并清掉该玩家的缓存。结果提示文本取门面返回值,按玩家入队,
-- 接线层不另写文案、屏内不加结果节点;兑换后屏不关闭,点取消关闭。
local append_intent_spec = require("src.ui.input.route_specs")
local canvas = require("src.ui.coord.canvas_coordinator")
local base_nodes = require("src.ui.schema.base")
local gift_code_nodes = require("src.ui.schema.gift_code")
local panel_helpers = require("src.ui.render.support.panel_helpers")
local node_ops = require("src.ui.render.support.node_ops")
local runtime_ui = require("src.ui.render.support.runtime_ui")
local host_events = require("src.ui.seams.host_events")
local gift_code_port = require("src.ui.seams.gift_code")
local tip_queue = require("src.foundation.tips")
local role_id_utils = require("src.foundation.identity")
local logger = require("src.foundation.log")

local gift_code = { key = "gift_code" }

local TIP_DURATION = 2.0

local function _ensure(state)
  local ui = assert(assert(state, "missing state").ui, "missing state.ui")
  ui.gift_code = ui.gift_code or { input_by_role = {} }
  return ui.gift_code
end

-- ===== route 面 =====

local _append = append_intent_spec.builder("gift_code_action")

function gift_code.build_route_specs(_state)
  local specs = {}
  _append(specs, gift_code_nodes.confirm_button, "confirm")
  _append(specs, gift_code_nodes.cancel_button, "cancel")
  return specs
end

-- ===== 开关屏 =====

local function _clear_input_field()
  node_ops.set_text(nil, gift_code_nodes.input_field, "")
end

-- open 记录 open/role_id:弹窗收屏与黑市开屏的 per-role 回屏按
-- canvas_coordinator 的面板态重解析(#583 分道),不记录会被拽回基础屏。
function gift_code.open(state, role_id)
  local screen = _ensure(state)
  screen.input_by_role[role_id_utils.normalize(role_id) or "?"] = nil
  screen.open = true
  screen.role_id = role_id
  canvas.switch_by_role_id(state.ui, gift_code_nodes.canvas, role_id)
  panel_helpers.with_owner_role(state, role_id, _clear_input_field)
  return screen
end

function gift_code.close(state, role_id)
  local screen = _ensure(state)
  screen.open = false
  canvas.switch_by_role_id(state.ui, base_nodes.canvas, role_id)
  return screen
end

-- ===== 兑换提交 =====

local function _enqueue_result(role_id, result)
  if type(result) ~= "table" or result.message == nil then
    return
  end
  -- 去重粒度按玩家 + 提示文本:连续兑换两个码得到的不同提示都要展示,
  -- 同一条提示重复触发才吞(#195 review:只按 status 会吞掉第二条成功提示)。
  tip_queue.enqueue({
    text = result.message,
    duration = TIP_DURATION,
    dedupe_key = "gift_code:" .. tostring(role_id) .. ":" .. result.message,
    blocks_inter_turn = false,
    role_id = role_id,
    source = "ui.gift_code",
  })
end

function gift_code.confirm(state, role_id)
  local screen = _ensure(state)
  local input_text = screen.input_by_role[role_id_utils.normalize(role_id) or "?"]
  _enqueue_result(role_id, gift_code_port.redeem(state, role_id, input_text))
  return screen
end

local _ACTIONS = {
  confirm = gift_code.confirm,
  cancel = gift_code.close,
}

function gift_code.handle_action(state, action, role_id)
  local handler = _ACTIONS[action]
  if handler == nil then
    logger.warn("gift_code unknown action:", tostring(action))
    return _ensure(state)
  end
  return handler(state, role_id)
end

-- ===== 输入缓存 =====

-- 宿主「输入框输入完成」回调:data.role 为输入玩家,data.content 为输入内容。
function gift_code.remember_input(state, data)
  local role_id = runtime_ui.resolve_role_id(data and data.role or nil)
  if role_id == nil then
    logger.warn("gift_code input ignored: role unresolved")
    return false
  end
  local content = data.content
  _ensure(state).input_by_role[role_id] = type(content) == "string" and content or nil
  return true
end

-- 宿主调用节:查询异常(含节点缺失,query_node 以 error 报出)带 err 留
-- warn,不静默吞掉。
local function _query_input_node()
  local ok, node = pcall(runtime_ui.query_node, gift_code_nodes.input_field)
  if not ok then
    logger.warn("gift_code input node query failed:", tostring(node))
    return nil
  end
  return node
end

-- 开局接线(app/ui_bootstrap 调用):在输入框上注册宿主输入完成监听。
-- 查询失败(已带 err 留 warn)、端口不可用或宿主拒绝注册(句柄为 nil)
-- 都留 warn 并返回 false。
function gift_code.bind_input(state)
  local node = _query_input_node()
  if node == nil then
    return false
  end
  local port_ok, trigger = host_events.register_input_text_end(node.id, function(_, _, data)
    gift_code.remember_input(state, data)
  end)
  if not port_ok then
    logger.warn("gift_code input listener skipped: register_input_text_end unavailable")
    return false
  end
  if trigger == nil then
    logger.warn("gift_code input listener skipped: host rejected registration")
    return false
  end
  return true
end

local panel_interrupt = require("src.ui.state.panel_interrupt")
-- screen registry 只有进程级注册、没有卸载生命周期；模块热重载时由固定键
-- 覆盖旧 closer，避免保留旧模块闭包，也无需伪造 screen 实例注销点。
panel_interrupt.register_panel_closer("gift_code", function(state, role_id)
  gift_code.close(state, role_id)
end)

return gift_code
