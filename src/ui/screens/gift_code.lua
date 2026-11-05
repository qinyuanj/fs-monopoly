-- gift_code(礼包码屏)屏:点击意图 + 开关屏 + 输入缓存 + 兑换提交,单一归宿(#199)。
--
-- 这是 canvas 面,不是选择屏:没有 descriptor / open / canvas 三契约(详见
-- screens_registry 的说明)。入口按钮住基础屏,其点击路由(open_gift_code_screen)
-- 也由本屏发射,受入口开关 gift_codes.entry_enabled 控制:关闭时不路由入口点击,
-- 开局压灭入口按钮及其装饰节点。
-- 宿主没有读取输入框文本的接口:监听「输入框输入完成」事件按玩家缓存最近一次输入,
-- 点确认时登记待兑换,延后一小段再把缓存交给兑换门面(经 seams/gift_code 注入;#226:
-- 宿主先派发点击、后派发输入完成),没有缓存按空输入处理;
-- 开屏时把该玩家的草稿回填进输入框(无草稿写空串)。清草稿与输入框只有两条路径:
-- 点取消(#201:明确放弃),以及兑换结果为 granted / all_owned 时的自动收屏(#224);
-- 被打断或其余兑换结果后重开都保留草稿。
-- 兑换结果是领域状态 { status, granted }(#204),本屏按 status 取配置里的提示模板,
-- granted 时填入皮肤名,按玩家入队;屏内不加结果节点。granted / all_owned 时提示
-- 入队后自动收屏,并对这名玩家隐藏入口;其余结果屏不关闭,由玩家改码重试或取消。
-- 入口按玩家显隐(#224):开局读档后经 refresh_entry 按 seam 查询「已拥有所有在用码
-- 的全部奖励」隐藏或显示,全服开关关闭时由 install_entry 统一压灭。
-- 草稿只活在本局内存,不写存档。
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
local runtime_ports = require("src.foundation.ports.runtime_ports")
local logger = require("src.foundation.log")
local gift_codes = require("src.config.content.gift_codes")
local skins = require("src.config.content.skins")

local gift_code = { key = "gift_code" }

local TIP_DURATION = 2.0

local function _ensure(state)
  local ui = assert(assert(state, "missing state").ui, "missing state.ui")
  ui.gift_code = ui.gift_code or { input_by_role = {}, pending_by_role = {}, next_pending = 0 }
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

-- 取消 = 明确放弃:清掉该玩家草稿与输入框,再收屏。兑换成功 / 已全部拥有的自动收屏
-- (#224)共用 _close_and_clear,两者是仅有的清草稿路径;#202 起黑市开屏不再经此收屏(礼包码屏
-- 不注册 panel_interrupt closer)。
local function _close_and_clear(state, role_id)
  local screen = _ensure(state)
  local key = _role_key(role_id)
  if key ~= nil then
    screen.input_by_role[key] = nil
    screen.pending_by_role[key] = nil
  end
  _write_input_field(state, role_id, "")
  screen.open = false
  canvas.switch_by_role_id(state.ui, base_nodes.canvas, role_id)
  return screen
end

function gift_code.cancel(state, role_id)
  return _close_and_clear(state, role_id)
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

local function _entry_node_names()
  local names = { base_nodes.gift_code_button }
  for _, name in ipairs(base_nodes.gift_code_decor_nodes) do
    names[#names + 1] = name
  end
  return names
end

-- 按玩家写入口按钮及其装饰节点的显隐(同名节点全量命中)。必须按角色推送:玩家解析
-- 不出时不写,否则 node_ops 会退成全服写入。写入失败带 err 留 warn。
local function _set_entry_visible(state, role_id, visible)
  if runtime_ports.resolve_role(role_id) == nil then
    logger.warn("gift_code entry visibility skipped: role unresolved", tostring(role_id))
    return false
  end
  panel_helpers.with_owner_role(state, role_id, function()
    for _, name in ipairs(_entry_node_names()) do
      local ok, err = pcall(node_ops.set_visible_all, nil, name, visible)
      if not ok then
        logger.warn("gift_code entry visibility write failed:", name, tostring(err))
      end
    end
  end)
  return true
end

-- #224:奖励已到手(本次发放或早已全部拥有)的结果才收屏;already_redeemed 不代表
-- 奖励到手,write_failed 等失败要留着草稿重试。收屏后直接隐藏入口、不重查:同时有
-- 多个在用码时,兑完其中一个入口也当场隐藏,下局开局 refresh_entry 再按归属重算。
local _CLOSING_STATUSES = { granted = true, all_owned = true }

local function _redeem_draft(state, role_id)
  local screen = _ensure(state)
  local key = _role_key(role_id)
  local input_text = key ~= nil and screen.input_by_role[key] or nil
  local result = gift_code_port.redeem(state, role_id, input_text)
  _enqueue_result(role_id, result)
  if type(result) == "table" and _CLOSING_STATUSES[result.status] then
    _close_and_clear(state, role_id)
    _set_entry_visible(state, role_id, false)
  end
end

-- #226:宿主先派发兑换按钮点击,再派发输入框失焦带出的「输入完成」(真机取证),点击
-- 当下的草稿是点击前的旧值。确认只登记该玩家的待兑换令牌,延后 confirm_settle_seconds
-- 再读草稿兑换;待兑换期间重复点击不再登记,取消清掉令牌,到点令牌不符即不兑换。
function gift_code.confirm(state, role_id)
  local screen = _ensure(state)
  local key = _role_key(role_id)
  if key == nil then
    _redeem_draft(state, role_id)
    return screen
  end
  if screen.pending_by_role[key] ~= nil then
    return screen
  end
  screen.next_pending = screen.next_pending + 1
  local token = screen.next_pending
  screen.pending_by_role[key] = token
  runtime_ports.schedule(gift_codes.confirm_settle_seconds, function()
    if screen.pending_by_role[key] ~= token then
      return
    end
    screen.pending_by_role[key] = nil
    _redeem_draft(state, role_id)
  end)
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

-- 开局读档后(app/gameplay_start 调用,#224):按 seam 查询对这名玩家显示或隐藏入口。
-- 全服开关关闭时不动作,交给 install_entry 的全服压灭。
function gift_code.refresh_entry(state, role_id)
  if not _entry_enabled() then
    return false
  end
  local visible = not gift_code_port.owns_all_rewards(state, role_id)
  return _set_entry_visible(state, role_id, visible)
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
  for _, name in ipairs(_entry_node_names()) do
    _hide_entry_node(name)
  end
  return false
end

return gift_code
