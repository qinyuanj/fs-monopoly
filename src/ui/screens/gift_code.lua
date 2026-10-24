-- gift_code(礼包码屏)屏:点击意图 + 开关屏 + 输入缓存 + 兑换提交,单一归宿(#199)。
--
-- 这是 canvas 面,不是选择屏:没有 descriptor / open / canvas 三契约(详见
-- screens_registry 的说明)。入口按钮住基础屏,其点击路由(open_gift_code_screen)
-- 也由本屏发射,受入口开关 gift_codes.entry_enabled 控制:关闭时不路由入口点击,
-- 开局压灭入口按钮及其装饰节点。
-- 宿主没有读取输入框文本的接口:监听「输入框输入完成」事件按玩家缓存最近一次输入,
-- 点确认时把缓存交给兑换门面(经 seams/gift_code 注入),没有缓存按空输入处理;
-- 开屏时把该玩家的草稿回填进输入框(无草稿写空串),点取消才清掉草稿与输入框
-- (#201:取消 = 明确放弃,是唯一清草稿的路径;被打断或兑换后重开都保留草稿)。
-- 兑换结果是领域状态 { status, granted }(#204),本屏按 status 取配置里的提示模板,
-- granted 时填入皮肤名,按玩家入队;屏内不加结果节点;
-- 兑换后屏不关闭,点取消关闭。草稿只活在本局内存,不写存档。
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
local gift_codes = require("src.config.content.gift_codes")
local skins = require("src.config.content.skins")

local gift_code = { key = "gift_code" }

local TIP_DURATION = 2.0

local function _ensure(state)
  local ui = assert(assert(state, "missing state").ui, "missing state.ui")
  ui.gift_code = ui.gift_code or { input_by_role = {} }
  return ui.gift_code
end

-- ===== route 面 =====

local _append = append_intent_spec.builder("gift_code_action")

-- 测试替身:nil 时以配置为准。config 模块会被测试重载,测试改开关只经这里。
local _entry_enabled_override = nil

local function _entry_enabled()
  if _entry_enabled_override ~= nil then
    return _entry_enabled_override
  end
  return gift_codes.entry_enabled == true
end

function gift_code.configure_entry_for_tests(enabled)
  _entry_enabled_override = enabled == true
end

function gift_code.reset_entry_for_tests()
  _entry_enabled_override = nil
end

function gift_code.build_route_specs(_state)
  local specs = {}
  if _entry_enabled() then
    specs[#specs + 1] = {
      name = base_nodes.gift_code_button,
      build_intent = function()
        return { type = "open_gift_code_screen" }
      end,
    }
  end
  _append(specs, gift_code_nodes.confirm_button, "confirm")
  _append(specs, gift_code_nodes.cancel_button, "cancel")
  return specs
end

-- ===== 开关屏 =====

-- 缓存键单一口径(#195 review):输入缓存、开屏回填、取消清理、确认读取都经同一
-- 归一化函数——入缓存的玩家和确认的玩家是同一个键(测试按字符串/数值
-- 两种 id 表示钉住)。未解析出玩家时不落键,不再用 "?" 哨兵桶。
local function _role_key(role_id)
  return role_id_utils.normalize(role_id)
end

local function _write_input_field(state, role_id, text)
  panel_helpers.with_owner_role(state, role_id, function()
    node_ops.set_text(nil, gift_code_nodes.input_field, text or "")
  end)
end

-- open 记录 open/role_id:弹窗收屏与黑市开屏的 per-role 回屏按
-- canvas_coordinator 的面板态重解析(#583 分道),不记录会被拽回基础屏。
-- 开屏只回填草稿,不清缓存(#201):未点取消的输入在重开时仍在。
function gift_code.open(state, role_id)
  local screen = _ensure(state)
  local key = _role_key(role_id)
  local draft = key ~= nil and screen.input_by_role[key] or nil
  screen.open = true
  screen.role_id = role_id
  canvas.switch_by_role_id(state.ui, gift_code_nodes.canvas, role_id)
  _write_input_field(state, role_id, draft)
  return screen
end

-- 取消 = 明确放弃:清掉该玩家草稿与输入框,再收屏。唯一清草稿的路径。
-- 收屏只动 open 与 canvas,不动草稿;#202 起黑市开屏不再经此收屏(礼包码屏不注册
-- panel_interrupt closer),所以“收屏但保留草稿”只有取消一条路。
function gift_code.cancel(state, role_id)
  local screen = _ensure(state)
  local key = _role_key(role_id)
  if key ~= nil then
    screen.input_by_role[key] = nil
  end
  _write_input_field(state, role_id, "")
  screen.open = false
  canvas.switch_by_role_id(state.ui, base_nodes.canvas, role_id)
  return screen
end

-- ===== 兑换提交 =====

-- 发放的皮肤名,顿号分隔;名字取自皮肤目录配置。
local function _skin_names(product_ids)
  local names = {}
  for _, product_id in ipairs(product_ids or {}) do
    for _, skin in ipairs(skins) do
      if skin.product_id == product_id and skin.name ~= nil then
        names[#names + 1] = skin.name
      end
    end
  end
  return table.concat(names, "、")
end

local function _message(result)
  if type(result) ~= "table" then
    return nil
  end
  local template = gift_codes.messages[result.status]
  if template ~= nil and result.status == "granted" then
    return string.format(template, _skin_names(result.granted))
  end
  return template
end

local function _enqueue_result(role_id, result)
  local message = _message(result)
  if message == nil then
    return
  end
  -- 去重粒度按玩家 + 提示文本:连续兑换两个码得到的不同提示都要展示,
  -- 同一条提示重复触发才吞(#195 review:只按 status 会吞掉第二条成功提示)。
  tip_queue.enqueue({
    text = message,
    duration = TIP_DURATION,
    dedupe_key = "gift_code:" .. tostring(role_id) .. ":" .. message,
    blocks_inter_turn = false,
    role_id = role_id,
    source = "ui.gift_code",
  })
end

function gift_code.confirm(state, role_id)
  local screen = _ensure(state)
  local key = _role_key(role_id)
  local input_text = key ~= nil and screen.input_by_role[key] or nil
  _enqueue_result(role_id, gift_code_port.redeem(state, role_id, input_text))
  return screen
end

local _ACTIONS = {
  confirm = gift_code.confirm,
  cancel = gift_code.cancel,
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
  local key = _role_key(role_id)
  if key == nil then
    logger.warn("gift_code input ignored: role unresolved")
    return false
  end
  local content = data.content
  _ensure(state).input_by_role[key] = type(content) == "string" and content or nil
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

local function _hide_entry_node(name)
  local ok, err = pcall(node_ops.set_visible_all, nil, name, false)
  if not ok then
    logger.warn("gift_code entry hide failed:", name, tostring(err))
  end
end

-- 开局入口(app/ui_bootstrap 调用):入口开启时挂输入监听;关闭时压灭基础屏入口
-- 按钮及其装饰节点(同名节点全量命中),玩家看不到也点不到。压灭失败与查输入框
-- 同口径:带 err 留 warn,不打断开局。
function gift_code.install_entry(state)
  if _entry_enabled() then
    return gift_code.bind_input(state)
  end
  _hide_entry_node(base_nodes.gift_code_button)
  for _, name in ipairs(base_nodes.gift_code_decor_nodes) do
    _hide_entry_node(name)
  end
  return false
end

return gift_code
