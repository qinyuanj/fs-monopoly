local logger = require("src.foundation.log")
local runtime_ports = require("src.foundation.ports.runtime_ports")

local gateway = {}

local runtime_field = "__market_paid_runtime"
local panel_show_seconds = 10.0

local function _new_runtime()
  return {
    goods_id_by_product_id = {},
    product_id_by_goods_id = {},
    warned_missing_by_product_id = {},
    registered_role_ids = {},
    pending_by_role_id = {},
    on_purchase = nil,
    setup_done = false,
  }
end

local function _runtime(game)
  local rt = game[runtime_field]
  if not rt then
    rt = _new_runtime()
    game[runtime_field] = rt
  end
  return rt
end

local function _resolve_role(player)
  if not player or player.id == nil then
    return nil
  end
  local ok, role = pcall(runtime_ports.resolve_role, player.id)
  if not ok then
    return nil
  end
  return role
end

local function _role_id_field(player)
  return player and player.id or nil
end

local function _try_role_id(role)
  if role and type(role.get_roleid) == "function" then
    local ok, role_id = pcall(role.get_roleid)
    if ok and role_id ~= nil then
      return role_id
    end
  end
  return nil
end

local function _resolve_role_id(player, role)
  local role_id = _try_role_id(role)
  if role_id ~= nil then
    return role_id
  end
  logger.warn("market paid role_id resolve failed", "player_id=" .. tostring(_role_id_field(player)))
  return _role_id_field(player)
end

local function _mapping_warning_already_seen(rt, product_id)
  if rt.warned_missing_by_product_id[product_id] then
    return true
  end
  return false
end

local function _entry_field(entry, key)
  return entry and entry[key] or ""
end

local function _warn_mapping_missing_once(rt, entry, reason)
  local product_id = entry.product_id
  if _mapping_warning_already_seen(rt, product_id) then
    return
  end
  rt.warned_missing_by_product_id[product_id] = true
  logger.warn(
    "market paid goods mapping missing:",
    "product_id=" .. tostring(product_id),
    "name=" .. tostring(_entry_field(entry, "name")),
    "currency=" .. tostring(_entry_field(entry, "currency")),
    "reason=" .. tostring(reason or "mapping_missing")
  )
end

local function _load_goods_list()
  if GameAPI == nil then
    return nil
  end
  local get_goods_list = GameAPI.get_goods_list
  if type(get_goods_list) ~= "function" then
    return nil
  end
  local ok, list = pcall(get_goods_list)
  if not ok then
    return nil
  end
  if type(list) ~= "table" then
    return nil
  end
  return list
end

local function _goods_name(goods)
  return goods and goods.name or nil
end

local function _name_usable(name)
  return type(name) == "string" and name ~= ""
end

local function _duplicate(goods_by_name, name, goods)
  return goods_by_name[name] ~= nil and goods_by_name[name] ~= goods
end

local function _record_goods_name(goods_by_name, duplicate_name, goods)
  local name = _goods_name(goods)
  if not _name_usable(name) then
    return
  end
  if _duplicate(goods_by_name, name, goods) then
    duplicate_name[name] = true
    return
  end
  goods_by_name[name] = goods
end

local function _index_goods_by_name(goods_list)
  local goods_by_name = {}
  local duplicate_name = {}
  if type(goods_list) == "table" then
    for _, goods in ipairs(goods_list) do
      _record_goods_name(goods_by_name, duplicate_name, goods)
    end
  end
  return goods_by_name, duplicate_name
end

local function _record_product_goods_id(rt, entry, goods_id)
  rt.goods_id_by_product_id[entry.product_id] = goods_id
  local mapped_product_id = rt.product_id_by_goods_id[goods_id]
  if mapped_product_id == nil then
    rt.product_id_by_goods_id[goods_id] = entry.product_id
  elseif mapped_product_id ~= entry.product_id then
    logger.warn(
      "market paid goods ambiguous goods_id:",
      "goods_id=" .. tostring(goods_id),
      "product_id=" .. tostring(entry.product_id),
      "mapped_product_id=" .. tostring(mapped_product_id)
    )
  end
end

local function _warn_duplicate_name_match(entry, market_name, duplicate_name)
  if duplicate_name[market_name] then
    logger.warn(
      "market paid goods duplicate name match:",
      "name=" .. tostring(market_name),
      "product_id=" .. tostring(entry.product_id)
    )
  end
end

local function _record_goods_mapping(rt, entry, market_name, goods_id, duplicate_name)
  _record_product_goods_id(rt, entry, goods_id)
  _warn_duplicate_name_match(entry, market_name, duplicate_name)
end

local function _resolve_missing_mapping_reason(goods_list)
  if type(goods_list) == "table" then
    return "name_mapping_not_found"
  end
  return "goods_list_unavailable"
end

local function _is_missing_goods_id(goods_id)
  return goods_id == nil or goods_id == ""
end

local function _entry_product_id(entry)
  return entry and entry.product_id or nil
end

-- 按 entry.name 在商品表里查 goods_id:名字缺省或未登记时 goods_id 为 nil;
-- 名字同时回传,供记录映射时复用(与调用方原查找语义一致)。
local function _goods_for_entry(entry, goods_by_name)
  local market_name = entry.name
  local goods = market_name and goods_by_name[market_name] or nil
  return goods and goods.goods_id or nil, market_name
end

local function _try_record_entry_mapping(rt, entry)
  local goods_list = _load_goods_list()
  local goods_by_name, duplicate_name = _index_goods_by_name(goods_list)
  local goods_id, market_name = _goods_for_entry(entry, goods_by_name)
  if not _is_missing_goods_id(goods_id) then
    _record_goods_mapping(rt, entry, market_name, goods_id, duplicate_name)
    return goods_id, nil
  end
  return nil, _resolve_missing_mapping_reason(goods_list)
end

local function _lookup_goods_id(rt, entry, product_id)
  local goods_id = rt.goods_id_by_product_id[product_id]
  if _is_missing_goods_id(goods_id) then
    return _try_record_entry_mapping(rt, entry)
  end
  return goods_id, nil
end

local function _missing_goods_id_result(rt, entry, missing_reason, opts)
  if opts.warn_missing == true then
    _warn_mapping_missing_once(rt, entry, missing_reason)
  end
  return nil, "goods_mapping_missing"
end

local function _resolve_goods_id(game, entry, opts)
  opts = opts or {}
  local rt = _runtime(game)
  local product_id = _entry_product_id(entry)
  if product_id == nil then
    return nil, "missing_entry"
  end
  local goods_id, missing_reason = _lookup_goods_id(rt, entry, product_id)
  if _is_missing_goods_id(goods_id) then
    return _missing_goods_id_result(rt, entry, missing_reason, opts)
  end
  return goods_id, nil
end

local function _pending_queue(rt, role_id)
  local queue = rt.pending_by_role_id[role_id]
  if type(queue) ~= "table" then
    queue = {}
    rt.pending_by_role_id[role_id] = queue
  end
  return queue
end

local function _push_pending(rt, role_id, pending)
  local queue = _pending_queue(rt, role_id)
  queue[#queue + 1] = pending
end

local function _consume_pending(rt, role_id, goods_id)
  local queue = rt.pending_by_role_id[role_id]
  if type(queue) ~= "table" then
    return nil
  end
  local target_goods_id = tostring(goods_id)
  for index, pending in ipairs(queue) do
    if tostring(pending.goods_id) == target_goods_id then
      table.remove(queue, index)
      if #queue == 0 then
        rt.pending_by_role_id[role_id] = nil
      end
      return pending
    end
  end
  return nil
end

local function _callback_goods_id(data)
  local goods_id = data and data.goods_id or nil
  if goods_id == nil or goods_id == "" then
    logger.warn("market paid callback ignored: goods_id missing")
    return nil
  end
  return goods_id
end

local function _callback_role_id(data)
  return _resolve_role_id(nil, data and data.role or nil)
end

local function _consume_callback_pending(rt, data, goods_id)
  local callback_role_id = _callback_role_id(data)
  local pending = callback_role_id and _consume_pending(rt, callback_role_id, goods_id) or nil
  if pending then
    return pending
  end
  logger.warn("market paid callback ignored: pending missing", "role_id=" .. tostring(callback_role_id), "goods_id=" .. tostring(goods_id))
  return nil
end

local function _callback_player(game, pending)
  local callback_player = game:find_player_by_id(pending.player_id)
  if callback_player then
    return callback_player
  end
  logger.warn("market paid callback ignored: player missing", "player_id=" .. tostring(pending.player_id))
  return nil
end

local function _callback_entry(pending)
  local entry = pending.entry
  if entry then
    return entry
  end
  logger.warn("market paid callback ignored: market entry missing", "product_id=" .. tostring(pending.product_id))
  return nil
end

local function _run_purchase_handler(game, rt, callback_player, entry, pending)
  if type(pending.on_purchase) == "function" then
    pending.on_purchase(game, callback_player, entry, pending)
    return
  end
  if type(rt.on_purchase) == "function" then
    rt.on_purchase(game, callback_player, entry, pending)
  end
end

local function _hide_purchase_panel(player)
  local panel_role = _resolve_role(player)
  if panel_role and type(panel_role.set_goods_panel_visible) == "function" then
    pcall(panel_role.set_goods_panel_visible, false)
  end
end

local function _on_purchase_goods_callback(game, rt, data)
  local goods_id = _callback_goods_id(data)
  if goods_id == nil then
    return
  end
  local pending = _consume_callback_pending(rt, data, goods_id)
  if pending == nil then
    return
  end
  local callback_player = _callback_player(game, pending)
  if callback_player == nil then
    return
  end
  local entry = _callback_entry(pending)
  if entry == nil then
    return
  end
  _run_purchase_handler(game, rt, callback_player, entry, pending)
  _hide_purchase_panel(callback_player)
end

local function _trigger_ready()
  return RegisterTriggerEvent ~= nil and EVENT ~= nil and EVENT.SPEC_ROLE_PURCHASE_GOODS ~= nil
end

local function _registered_role_id(player)
  local role = _resolve_role(player)
  if role then
    local role_id = _resolve_role_id(player, role)
    if role_id ~= nil then
      return role_id
    end
  end
  return nil
end

local function _already_registered(rt, role_id)
  return rt.registered_role_ids[role_id] ~= nil
end

local function _register_purchase_event_for_role(game, player)
  if not _trigger_ready() then
    return
  end
  local role_id = _registered_role_id(player)
  if role_id == nil then
    return
  end
  local rt = _runtime(game)
  if _already_registered(rt, role_id) then
    return
  end
  RegisterTriggerEvent({ EVENT.SPEC_ROLE_PURCHASE_GOODS, role_id }, function(_, _, data)
    _on_purchase_goods_callback(game, rt, data)
  end)
  rt.registered_role_ids[role_id] = true
end

local function _set_runtime_on_purchase(rt, on_purchase)
  if type(on_purchase) == "function" then
    rt.on_purchase = on_purchase
  end
end

local function _setup_purchase_events(game, rt)
  local players = game and game.players or nil
  if type(players) ~= "table" then
    return
  end
  for _, player in ipairs(players) do
    _register_purchase_event_for_role(game, player)
  end
end

function gateway.setup_for_game(game, on_purchase)
  local rt = _runtime(game)
  _set_runtime_on_purchase(rt, on_purchase)
  if rt.setup_done == true then
    return
  end
  _setup_purchase_events(game, rt)
  rt.setup_done = true
end

function gateway.can_start(game, player, entry)
  gateway.setup_for_game(game)
  local goods_id, goods_reason = _resolve_goods_id(game, entry)
  if goods_id == nil then
    return false, goods_reason
  end
  local role = _resolve_role(player)
  if not role then
    return false, "role_unresolved"
  end
  if type(role.show_goods_purchase_panel) ~= "function" then
    return false, "purchase_api_missing"
  end
  return true, goods_id
end

local function _resolve_purchase_panel_role(player)
  local role = _resolve_role(player)
  if not role then
    return nil, "role_unresolved"
  end
  if type(role.show_goods_purchase_panel) ~= "function" then
    return nil, "purchase_api_missing"
  end
  return role, nil
end

local function _resolve_start_context(game, player, entry)
  gateway.setup_for_game(game)
  local goods_id, goods_reason = _resolve_goods_id(game, entry, { warn_missing = true })
  if goods_id == nil then
    return nil, goods_reason
  end
  local role, role_reason = _resolve_purchase_panel_role(player)
  if role == nil then
    return nil, role_reason
  end
  local role_id = _resolve_role_id(player, role)
  return {
    goods_id = goods_id,
    role = role,
    role_id = role_id,
  }, nil
end

local function _show_purchase_panel(player, entry, context)
  local ok_call = pcall(context.role.show_goods_purchase_panel, context.goods_id, panel_show_seconds)
  if not ok_call then
    logger.warn(
      "market paid panel call failed",
      "player_id=" .. tostring(player.id),
      "product_id=" .. tostring(entry.product_id),
      "goods_id=" .. tostring(context.goods_id)
    )
    return false
  end
  return true
end

function gateway.start(game, player, entry)
  local context, reason = _resolve_start_context(game, player, entry)
  if context == nil then
    return false, reason
  end
  if not _show_purchase_panel(player, entry, context) then
    return false, "panel_call_failed"
  end
  local rt = _runtime(game)
  _push_pending(rt, context.role_id, {
    player_id = player.id,
    product_id = entry.product_id,
    entry = entry,
    goods_id = context.goods_id,
    on_purchase = type(entry.on_purchase) == "function" and entry.on_purchase or nil,
  })
  return true, nil
end

-- Test seam exports
gateway._on_purchase_goods_callback = _on_purchase_goods_callback
gateway._runtime = _runtime
gateway._push_pending = _push_pending

return gateway

