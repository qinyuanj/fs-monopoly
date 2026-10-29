require("test.bootstrap").install_package_paths()
-- busted injects luassert fields on assert.
-- luacheck: ignore 143
local luassert = assert
local support = require("test.support.shared_support")
local function _assert_eq(actual, expected, message)
  luassert.is.equal(expected, actual, message)
end
local with_patches = support.with_patches

local function _entry(overrides)
  local entry = {
    product_id = 2009,
    name = "强征卡",
    currency = "金豆",
    market_enabled = true,
  }
  for key, value in pairs(overrides or {}) do
    entry[key] = value
  end
  return entry
end

local function _player(id)
  return { id = id or 1, name = "玩家" .. tostring(id or 1) }
end

local function _game_with_player(player)
  return {
    players = { player },
    find_player_by_id = function(_, player_id)
      if tostring(player_id) == tostring(player.id) then
        return player
      end
      return nil
    end,
  }
end

local function _purchase_role(overrides)
  local role = {
    get_roleid = function()
      return 77
    end,
    show_goods_purchase_panel = function() end,
    set_goods_panel_visible = function() end,
  }
  for key, value in pairs(overrides or {}) do
    role[key] = value
  end
  return role
end

local function _with_gateway_env(opts, fn)
  opts = opts or {}
  local goods_list = opts.goods_list
  if goods_list == nil then
    goods_list = {
      { name = opts.goods_name or "强征卡", goods_id = opts.goods_id or "goods_strong_card" },
    }
  end
  local role = opts.role or _purchase_role()
  local runtime_ports = require("src.foundation.ports.runtime_ports")
  with_patches({
    {
      key = "GameAPI",
      value = opts.game_api or {
        get_goods_list = function()
          return goods_list
        end,
      },
    },
    {
      target = runtime_ports,
      key = "resolve_role",
      value = opts.resolve_role or function()
        return role
      end,
    },
  }, fn)
end

describe("TestPaidPurchaseGateway", function()

local function _test_eggy_paid_gateway_callback_missing_goods_id()
  local gateway = require("src.host.paid_purchase_gateway")
  local game = { players = {} }
  local rt = gateway._runtime(game)
  local warned = nil

  with_patches({
    {
      target = require("src.foundation.log"),
      key = "warn",
      value = function(msg)
        warned = msg
      end,
    },
  }, function()
    gateway._on_purchase_goods_callback(game, rt, {})
  end)

  _assert_eq(warned, "market paid callback ignored: goods_id missing", "should warn when goods_id is missing")
end

local function _test_eggy_paid_gateway_callback_empty_goods_id()
  local gateway = require("src.host.paid_purchase_gateway")
  local game = { players = {} }
  local rt = gateway._runtime(game)
  local warned = nil

  with_patches({
    {
      target = require("src.foundation.log"),
      key = "warn",
      value = function(msg)
        warned = msg
      end,
    },
  }, function()
    gateway._on_purchase_goods_callback(game, rt, { goods_id = "" })
  end)

  _assert_eq(warned, "market paid callback ignored: goods_id missing", "should warn when goods_id is empty")
end

local function _test_eggy_paid_gateway_callback_missing_pending()
  local gateway = require("src.host.paid_purchase_gateway")
  local game = { players = {} }
  local rt = gateway._runtime(game)
  local warned = nil

  with_patches({
    {
      target = require("src.foundation.log"),
      key = "warn",
      value = function(msg, ctx1, ctx2)
        warned = msg .. " " .. tostring(ctx1) .. " " .. tostring(ctx2)
      end,
    },
  }, function()
    gateway._on_purchase_goods_callback(game, rt, { goods_id = "goods_123" })
  end)

  luassert.truthy(warned and warned:find("pending missing", 1, true), "should warn when pending is missing: " .. tostring(warned))
end

local function _test_eggy_paid_gateway_callback_missing_player()
  local gateway = require("src.host.paid_purchase_gateway")
  local game = {
    players = {},
    find_player_by_id = function()
      return nil
    end,
  }
  local rt = gateway._runtime(game)
  gateway._push_pending(rt, 5, { player_id = 99, product_id = 1001, goods_id = "goods_123" })
  local warned = nil

  with_patches({
    {
      target = require("src.foundation.log"),
      key = "warn",
      value = function(msg, ctx)
        warned = msg .. " " .. tostring(ctx)
      end,
    },
  }, function()
    gateway._on_purchase_goods_callback(game, rt, { goods_id = "goods_123", role = { get_roleid = function() return 5 end } })
  end)

  luassert.truthy(warned and warned:find("player missing", 1, true), "should warn when player is missing: " .. tostring(warned))
end

local function _test_eggy_paid_gateway_callback_missing_entry()
  local gateway = require("src.host.paid_purchase_gateway")
  local mock_player = { id = 99 }
  local game = {
    players = { mock_player },
    find_player_by_id = function()
      return mock_player
    end,
  }
  local rt = gateway._runtime(game)
  gateway._push_pending(rt, 5, { player_id = 99, product_id = 9999, goods_id = "goods_123" })
  local warned = nil

  with_patches({
    {
      target = require("src.foundation.log"),
      key = "warn",
      value = function(msg, ctx)
        warned = msg .. " " .. tostring(ctx)
      end,
    },
  }, function()
    gateway._on_purchase_goods_callback(game, rt, { goods_id = "goods_123", role = { get_roleid = function() return 5 end } })
  end)

  luassert.truthy(warned and warned:find("market entry missing", 1, true), "should warn when entry is missing: " .. tostring(warned))
end

local function _test_eggy_paid_gateway_callback_success_with_on_purchase()
  local gateway = require("src.host.paid_purchase_gateway")
  local mock_player = { id = 99 }
  local mock_entry = { product_id = 1001, name = "Test Item" }
  local game = {
    players = { mock_player },
    find_player_by_id = function()
      return mock_player
    end,
  }
  local rt = gateway._runtime(game)
  local purchase_called = false
  rt.on_purchase = function(g, p, e, pending)
    purchase_called = true
    _assert_eq(g, game, "game should match")
    _assert_eq(p, mock_player, "player should match")
    _assert_eq(e, mock_entry, "entry should match")
    _assert_eq(pending.product_id, 1001, "pending product_id should match")
  end
  gateway._push_pending(rt, 5, { player_id = 99, product_id = 1001, entry = mock_entry, goods_id = "goods_123" })
  gateway._on_purchase_goods_callback(game, rt, { goods_id = "goods_123", role = { get_roleid = function() return 5 end } })

  _assert_eq(purchase_called, true, "on_purchase should be called")
end

local function _test_eggy_paid_gateway_callback_uses_pending_specific_on_purchase()
  local gateway = require("src.host.paid_purchase_gateway")
  local mock_player = { id = 99 }
  local mock_entry = { product_id = 5003, name = "海绵宝宝" }
  local game = {
    players = { mock_player },
    find_player_by_id = function()
      return mock_player
    end,
  }
  local rt = gateway._runtime(game)
  local pending_called = false
  local runtime_called = false
  rt.on_purchase = function()
    runtime_called = true
  end
  gateway._push_pending(rt, 5, {
    player_id = 99,
    product_id = 5003,
    entry = mock_entry,
    goods_id = "goods_skin_1",
    on_purchase = function(g, p, e, pending)
      pending_called = true
      _assert_eq(g, game, "game should match")
      _assert_eq(p, mock_player, "player should match")
      _assert_eq(e, mock_entry, "entry should match")
      _assert_eq(pending.product_id, 5003, "pending product_id should match")
    end,
  })

  gateway._on_purchase_goods_callback(game, rt, {
    goods_id = "goods_skin_1",
    role = { get_roleid = function() return 5 end },
  })

  _assert_eq(pending_called, true, "pending-specific on_purchase should be called")
  _assert_eq(runtime_called, false, "runtime on_purchase should not handle pending-specific purchases")
end

local function _test_eggy_paid_gateway_callback_success_without_on_purchase()
  local gateway = require("src.host.paid_purchase_gateway")
  local mock_player = { id = 99 }
  local mock_entry = { product_id = 1001, name = "Test Item" }
  local game = {
    players = { mock_player },
    find_player_by_id = function()
      return mock_player
    end,
  }
  local rt = gateway._runtime(game)
  gateway._push_pending(rt, 5, { player_id = 99, product_id = 1001, entry = mock_entry, goods_id = "goods_123" })
  gateway._on_purchase_goods_callback(game, rt, { goods_id = "goods_123", role = { get_roleid = function() return 5 end } })

  -- on_purchase 缺省时回调仍须走完成功路径:pending 已消费,不得残留待重放
  _assert_eq(rt.pending_by_role_id[5], nil, "pending should be consumed even without an on_purchase handler")
end

local function _test_eggy_paid_gateway_start_missing_purchase_api()
  local gateway = require("src.host.paid_purchase_gateway")
  local game = {
    players = {
      { id = 1 },
    },
  }
  local entry = {
    product_id = 2009,
    name = "强征卡",
    currency = "金豆",
    market_enabled = true,
  }

  with_patches({
    {
      key = "GameAPI",
      value = {
        get_goods_list = function()
          return {
            { name = "强征卡", goods_id = "goods_strong_card" },
          }
        end,
      },
    },
    {
      target = require("src.foundation.ports.runtime_ports"),
      key = "resolve_role",
      value = function()
        return {
          get_roleid = function()
            return 1
          end,
        }
      end,
    },
  }, function()
    local ok, reason = gateway.start(game, game.players[1], entry)
    _assert_eq(ok, false, "start should reject when purchase api is missing")
    _assert_eq(reason, "purchase_api_missing", "start should return explicit missing api reason")
  end)
end

local function _test_eggy_paid_gateway_start_uses_zero_arity_role_id_and_dot_panel_args()
  local gateway = require("src.host.paid_purchase_gateway")
  local player = { id = 1 }
  local game = {
    players = { player },
  }
  local entry = {
    product_id = 2009,
    name = "强征卡",
    currency = "金豆",
    market_enabled = true,
  }
  local panel_call = nil

  with_patches({
    {
      key = "GameAPI",
      value = {
        get_goods_list = function()
          return {
            { name = "强征卡", goods_id = "goods_strong_card" },
          }
        end,
      },
    },
    {
      target = require("src.foundation.ports.runtime_ports"),
      key = "resolve_role",
      value = function(role_id)
        if role_id ~= player.id then
          return nil
        end
        return {
          get_roleid = function(...)
            _assert_eq(select("#", ...), 0, "get_roleid should be called without implicit self")
            return 77
          end,
          show_goods_purchase_panel = function(...)
            _assert_eq(select("#", ...), 2, "show_goods_purchase_panel should receive exactly goods_id and show_time")
            panel_call = {
              goods_id = select(1, ...),
              show_time = select(2, ...),
            }
          end,
        }
      end,
    },
  }, function()
    local ok, reason = gateway.start(game, player, entry)
    _assert_eq(ok, true, "start should succeed with valid zero-arity role api")
    _assert_eq(reason, nil, "start should not return error on valid host api")
  end)

  _assert_eq(panel_call and panel_call.goods_id, "goods_strong_card", "panel should receive mapped goods id")
  _assert_eq(panel_call and panel_call.show_time, 10.0, "panel should receive configured show time")

  local rt = gateway._runtime(game)
  _assert_eq(type(rt.pending_by_role_id[77]), "table", "pending queue should use resolved host role id")
  _assert_eq(rt.pending_by_role_id[77][1].goods_id, "goods_strong_card", "pending queue should store goods id under host role id")
  _assert_eq(rt.pending_by_role_id[77][1].entry, entry, "pending queue should carry original market entry")
end

local function _test_eggy_paid_gateway_can_start_reports_mapping_role_and_api_failures()
  local gateway = require("src.host.paid_purchase_gateway")
  local player = _player(1)
  local game = _game_with_player(player)
  local entry = _entry()

  _with_gateway_env({
    game_api = {},
    role = _purchase_role(),
  }, function()
    local ok, reason = gateway.can_start(game, player, entry)
    _assert_eq(ok, false, "can_start should reject missing goods mapping")
    _assert_eq(reason, "goods_mapping_missing", "can_start should report missing goods mapping")
  end)

  _with_gateway_env({
    resolve_role = function()
      return nil
    end,
  }, function()
    local ok, reason = gateway.can_start(game, player, entry)
    _assert_eq(ok, false, "can_start should reject unresolved role")
    _assert_eq(reason, "role_unresolved", "can_start should report unresolved role")
  end)

  _with_gateway_env({
    role = {
      get_roleid = function()
        return 77
      end,
    },
  }, function()
    local ok, reason = gateway.can_start(game, player, entry)
    _assert_eq(ok, false, "can_start should reject missing purchase API")
    _assert_eq(reason, "purchase_api_missing", "can_start should report missing purchase API")
  end)

  _with_gateway_env({}, function()
    local ok, goods_id = gateway.can_start(game, nil, entry)
    _assert_eq(ok, false, "can_start should reject missing player")
    _assert_eq(goods_id, "role_unresolved", "missing player should be an unresolved role")
  end)

  _with_gateway_env({}, function()
    local ok, goods_id = gateway.can_start(game, player, entry)
    local rt = gateway._runtime(game)
    _assert_eq(ok, true, "can_start should accept mapped paid goods")
    _assert_eq(goods_id, "goods_strong_card", "can_start should return mapped goods id")
    _assert_eq(rt.goods_id_by_product_id[entry.product_id], "goods_strong_card",
      "can_start should cache goods mapping")
    _assert_eq(rt.product_id_by_goods_id.goods_strong_card, entry.product_id,
      "can_start should cache reverse goods mapping")
  end)
end

local function _test_eggy_paid_gateway_start_reports_specific_failure_reasons()
  local gateway = require("src.host.paid_purchase_gateway")
  local player = _player(1)
  local game = _game_with_player(player)

  _with_gateway_env({}, function()
    local ok, reason = gateway.start(game, player, nil)
    _assert_eq(ok, false, "start should reject missing entry")
    _assert_eq(reason, "missing_entry", "start should report missing entry")
  end)

  _with_gateway_env({
    game_api = {},
  }, function()
    local ok, reason = gateway.start(game, player, _entry())
    _assert_eq(ok, false, "start should reject missing mapping")
    _assert_eq(reason, "goods_mapping_missing", "start should report missing mapping")
  end)

  _with_gateway_env({
    resolve_role = function()
      return nil
    end,
  }, function()
    local ok, reason = gateway.start(game, player, _entry())
    _assert_eq(ok, false, "start should reject unresolved role")
    _assert_eq(reason, "role_unresolved", "start should report unresolved role")
  end)

  with_patches({
    {
      target = require("src.foundation.log"),
      key = "warn",
      value = function() end,
    },
  }, function()
    _with_gateway_env({
      role = _purchase_role({
        show_goods_purchase_panel = function()
          error("panel boom")
        end,
      }),
    }, function()
      local ok, reason = gateway.start(game, player, _entry())
      _assert_eq(ok, false, "start should reject failed panel call")
      _assert_eq(reason, "panel_call_failed", "start should report failed panel call")
    end)
  end)
end

local function _test_eggy_paid_gateway_treats_empty_goods_id_as_missing_mapping()
  local gateway = require("src.host.paid_purchase_gateway")
  local player = _player(1)
  local game = _game_with_player(player)

  _with_gateway_env({
    goods_list = {
      { name = "强征卡", goods_id = "" },
    },
  }, function()
    local ok, reason = gateway.start(game, player, _entry())
    _assert_eq(ok, false, "empty goods_id should reject purchase")
    _assert_eq(reason, "goods_mapping_missing", "empty goods_id should be a mapping failure")
  end)
end

local function _test_eggy_paid_gateway_ignores_empty_goods_names()
  local gateway = require("src.host.paid_purchase_gateway")
  local player = _player(1)
  local game = _game_with_player(player)

  _with_gateway_env({
    goods_list = {
      { name = "", goods_id = "empty_named_goods" },
    },
  }, function()
    local ok, reason = gateway.start(game, player, _entry({ name = "" }))
    _assert_eq(ok, false, "empty goods names should not be mapped")
    _assert_eq(reason, "goods_mapping_missing", "empty goods names should be treated as missing mappings")
  end)
end

local function _test_eggy_paid_gateway_falls_back_to_player_id_when_role_id_fails()
  local gateway = require("src.host.paid_purchase_gateway")
  local player = _player(8)
  local game = _game_with_player(player)

  with_patches({
    {
      target = require("src.foundation.log"),
      key = "warn",
      value = function() end,
    },
  }, function()
    _with_gateway_env({
      role = _purchase_role({
        get_roleid = function()
          error("role id unavailable")
        end,
      }),
    }, function()
      local ok, reason = gateway.start(game, player, _entry())
      local rt = gateway._runtime(game)
      _assert_eq(ok, true, "start should fall back when host role id fails")
      _assert_eq(reason, nil, "fallback start should not report an error")
      _assert_eq(type(rt.pending_by_role_id[player.id]), "table", "pending should be keyed by player id fallback")
      _assert_eq(rt.pending_by_role_id[player.id][1].goods_id, "goods_strong_card",
        "fallback pending should preserve mapped goods id")
    end)
  end)
end

local function _test_eggy_paid_gateway_warns_mapping_edge_cases()
  local gateway = require("src.host.paid_purchase_gateway")
  local player = _player(1)
  local game = _game_with_player(player)
  local warnings = {}

  with_patches({
    {
      target = require("src.foundation.log"),
      key = "warn",
      value = function(...)
        warnings[#warnings + 1] = table.concat({ ... }, " ")
      end,
    },
  }, function()
    _with_gateway_env({
      goods_list = {
        { name = "重复商品", goods_id = "goods_a" },
        { name = "重复商品", goods_id = "goods_b" },
      },
    }, function()
      local ok = gateway.start(game, player, _entry({ name = "重复商品", product_id = 3001 }))
      _assert_eq(ok, true, "duplicate-name mapping should still start")
    end)

    _with_gateway_env({
      goods_list = {
        { name = "商品A", goods_id = "goods_shared" },
        { name = "商品B", goods_id = "goods_shared" },
      },
    }, function()
      _assert_eq(gateway.start(game, player, _entry({ name = "商品A", product_id = 3002 })), true,
        "first shared goods mapping should start")
      _assert_eq(gateway.start(game, player, _entry({ name = "商品B", product_id = 3003 })), true,
        "second shared goods mapping should start")
    end)
  end)

  local text = table.concat(warnings, "\n")
  luassert.truthy(text:find("duplicate name match", 1, true), "duplicate name should warn: " .. text)
  luassert.truthy(text:find("ambiguous goods_id", 1, true), "ambiguous goods id should warn: " .. text)
end

local function _test_eggy_paid_gateway_warns_distinct_mapping_failure_reasons()
  local gateway = require("src.host.paid_purchase_gateway")
  local player = _player(1)
  local warnings = {}

  with_patches({
    {
      target = require("src.foundation.log"),
      key = "warn",
      value = function(...)
        warnings[#warnings + 1] = table.concat({ ... }, " ")
      end,
    },
  }, function()
    _with_gateway_env({
      game_api = {},
    }, function()
      gateway.start(_game_with_player(player), player, _entry({ product_id = 4001 }))
    end)

    _with_gateway_env({
      goods_list = {},
    }, function()
      gateway.start(_game_with_player(player), player, _entry({ product_id = 4002 }))
    end)
  end)

  local text = table.concat(warnings, "\n")
  local function has_warning(product_id, reason)
    for _, warning in ipairs(warnings) do
      if warning:find("product_id=" .. tostring(product_id), 1, true)
        and warning:find("reason=" .. tostring(reason), 1, true) then
        return true
      end
    end
    return false
  end

  luassert.truthy(has_warning(4001, "goods_list_unavailable"),
    "unavailable goods list should warn its reason: " .. text)
  luassert.truthy(has_warning(4002, "name_mapping_not_found"),
    "missing name mapping should warn its reason: " .. text)
end

local function _test_eggy_paid_gateway_missing_or_broken_goods_list_maps_unavailable()
  local gateway = require("src.host.paid_purchase_gateway")
  local player = _player(1)

  local function _start_with_game_api(game_api)
    local game = _game_with_player(player)
    local ok, reason
    with_patches({
      {
        key = "GameAPI",
        value = game_api,
      },
    }, function()
      ok, reason = gateway.start(game, player, _entry({ product_id = 5003 }))
    end)
    return ok, reason
  end

  local no_api_ok, no_api_reason = _start_with_game_api(nil)
  _assert_eq(no_api_ok, false, "start without GameAPI should reject")
  _assert_eq(no_api_reason, "goods_mapping_missing", "start without GameAPI should fail goods mapping")

  local throwing_ok, throwing_reason = _start_with_game_api({
    get_goods_list = function()
      error("host goods list exploded")
    end,
  })
  _assert_eq(throwing_ok, false, "throwing get_goods_list should reject")
  _assert_eq(throwing_reason, "goods_mapping_missing", "throwing get_goods_list should fail goods mapping")

  local non_table_ok, non_table_reason = _start_with_game_api({
    get_goods_list = function()
      return "not-a-table"
    end,
  })
  _assert_eq(non_table_ok, false, "non-table get_goods_list result should reject")
  _assert_eq(non_table_reason, "goods_mapping_missing", "non-table goods list should fail goods mapping")
end

local function _test_eggy_paid_gateway_callback_pending_missing_or_unmatched()
  local gateway = require("src.host.paid_purchase_gateway")
  local game = { players = {} }
  local rt = gateway._runtime(game)
  local warned = nil

  with_patches({
    {
      target = require("src.foundation.log"),
      key = "warn",
      value = function(msg, ctx1, ctx2)
        warned = msg .. " " .. tostring(ctx1) .. " " .. tostring(ctx2)
      end,
    },
  }, function()
    gateway._on_purchase_goods_callback(game, rt, {
      goods_id = "goods_123",
      role = { get_roleid = function() return 5 end },
    })
    luassert.truthy(warned and warned:find("pending missing", 1, true),
      "missing pending queue should warn pending missing: " .. tostring(warned))

    rt.pending_by_role_id[5] = {
      { goods_id = "goods_other", player_id = 99, product_id = 1001 },
    }
    gateway._on_purchase_goods_callback(game, rt, {
      goods_id = "goods_123",
      role = { get_roleid = function() return 5 end },
    })
    luassert.truthy(warned and warned:find("pending missing", 1, true),
      "unmatched goods_id should warn pending missing: " .. tostring(warned))
  end)
end

local function _test_eggy_paid_gateway_pending_queue_recovers_and_cleans_up()
  local gateway = require("src.host.paid_purchase_gateway")
  local player = _player(99)
  local entry = _entry()
  local game = _game_with_player(player)
  local rt = gateway._runtime(game)
  local called = false

  rt.pending_by_role_id[5] = "corrupt"
  gateway._push_pending(rt, 5, {
    player_id = player.id,
    product_id = entry.product_id,
    entry = entry,
    goods_id = "goods_123",
    on_purchase = function()
      called = true
    end,
  })

  gateway._on_purchase_goods_callback(game, rt, {
    goods_id = "goods_123",
    role = { get_roleid = function() return 5 end },
  })

  _assert_eq(called, true, "callback should consume recovered pending entry")
  _assert_eq(rt.pending_by_role_id[5], nil, "empty pending queue should be removed")
end

local function _test_eggy_paid_gateway_pending_queue_appends_existing_queue()
  local gateway = require("src.host.paid_purchase_gateway")
  local game = { players = {} }
  local rt = gateway._runtime(game)
  local existing = { { goods_id = "old_goods" } }

  rt.pending_by_role_id[5] = existing
  gateway._push_pending(rt, 5, { goods_id = "new_goods" })

  _assert_eq(rt.pending_by_role_id[5], existing, "existing queue table should be reused")
  _assert_eq(#existing, 2, "new pending should append to existing queue")
  _assert_eq(existing[2].goods_id, "new_goods", "new pending should append at the end")
end

-- 批3 击杀：映射缺失告警的完整参数面——name/currency 的 _entry_field 取值通道
-- （call 换 nil + key 换 nil + and/or 变异 + 空串兜底）全部由精确告警文案钉死。
local function _test_eggy_paid_gateway_mapping_missing_warn_carries_full_args()
  local gateway = require("src.host.paid_purchase_gateway")
  local player = _player(1)
  local warnings = {}

  with_patches({
    {
      target = require("src.foundation.log"),
      key = "warn",
      value = function(...)
        warnings[#warnings + 1] = table.concat({ ... }, " ")
      end,
    },
  }, function()
    _with_gateway_env({
      goods_list = {},
    }, function()
      gateway.start(_game_with_player(player), player, _entry({ product_id = 4002 }))
    end)

    _with_gateway_env({
      goods_list = {},
    }, function()
      local entry = _entry({ product_id = 4003 })
      entry.name = nil
      entry.currency = nil
      gateway.start(_game_with_player(player), player, entry)
    end)
  end)

  luassert.truthy(warnings[1] == "market paid goods mapping missing: product_id=4002 name=强征卡 currency=金豆 reason=name_mapping_not_found",
    "mapping missing warn should carry full entry args, got: " .. tostring(warnings[1]))
  luassert.truthy(warnings[2] == "market paid goods mapping missing: product_id=4003 name= currency= reason=name_mapping_not_found",
    "mapping missing warn should expand missing fields to empty strings, got: " .. tostring(warnings[2]))
end

-- 批3 击杀 L60：role_id 解析失败回退时，告警必须带真实的 player_id 字段。
local function _test_eggy_paid_gateway_role_id_failure_warn_carries_player_id()
  local gateway = require("src.host.paid_purchase_gateway")
  local player = _player(8)
  local game = _game_with_player(player)
  local warnings = {}

  with_patches({
    {
      target = require("src.foundation.log"),
      key = "warn",
      value = function(...)
        warnings[#warnings + 1] = table.concat({ ... }, " ")
      end,
    },
  }, function()
    _with_gateway_env({
      role = _purchase_role({
        get_roleid = function()
          error("role id unavailable")
        end,
      }),
    }, function()
      local ok = gateway.start(game, player, _entry())
      _assert_eq(ok, true, "start should still fall back when host role id fails")
    end)
  end)

  luassert.truthy(warnings[1] and warnings[1]:find("market paid role_id resolve failed player_id=8", 1, true),
    "role-id failure warn should carry the player id, got: " .. tostring(warnings[1]))
end

-- 批3 击杀 L376：_already_registered 守卫——setup_done 复位后重跑 setup，
-- 已注册角色不得二次注册（变异把守卫换 nil 会重复注册）。
local function _test_eggy_paid_gateway_register_guard_skips_already_registered_roles()
  local gateway = require("src.host.paid_purchase_gateway")
  local game = { players = { _player(1) } }
  local registrations = {}

  with_patches({
    {
      target = require("src.foundation.ports.runtime_ports"),
      key = "resolve_role",
      value = function()
        return { get_roleid = function() return 5 end }
      end,
    },
    { key = "EVENT", value = { SPEC_ROLE_PURCHASE_GOODS = "SPEC_ROLE_PURCHASE_GOODS" } },
    {
      key = "RegisterTriggerEvent",
      value = function(event_key)
        registrations[#registrations + 1] = event_key
      end,
    },
  }, function()
    gateway.setup_for_game(game)
    local rt = gateway._runtime(game)
    rt.setup_done = false -- 模拟运行时重建后再次 setup
    gateway.setup_for_game(game)
  end)

  _assert_eq(#registrations, 1, "an already-registered role must not register twice")
end

-- 批3 击杀 L460：面板调用失败告警必须带固定 caption。
local function _test_eggy_paid_gateway_panel_call_failure_warns_with_caption()
  local gateway = require("src.host.paid_purchase_gateway")
  local player = _player(1)
  local game = _game_with_player(player)
  local warnings = {}

  with_patches({
    {
      target = require("src.foundation.log"),
      key = "warn",
      value = function(...)
        warnings[#warnings + 1] = table.concat({ ... }, " ")
      end,
    },
  }, function()
    _with_gateway_env({
      role = _purchase_role({
        show_goods_purchase_panel = function()
          error("panel exploded")
        end,
      }),
    }, function()
      local ok, reason = gateway.start(game, player, _entry())
      _assert_eq(ok, false, "a raising panel call should reject start")
      _assert_eq(reason, "panel_call_failed", "a raising panel call reports panel_call_failed")
    end)
  end)

  luassert.truthy(warnings[1] and warnings[1]:find("market paid panel call failed player_id=1", 1, true),
    "panel failure warn should carry the caption and player id, got: " .. tostring(warnings[1]))
end

-- 批3 击杀 L484 五处：pending 里的 on_purchase 字段——函数类型原样进入，
-- 非函数（如字符串）必须落 nil，不能泄漏进上下文。
local function _test_eggy_paid_gateway_pending_on_purchase_field_keeps_only_functions()
  local gateway = require("src.host.paid_purchase_gateway")
  local player = _player(1)
  local fn = function() end

  local game = _game_with_player(player)
  local rt = gateway._runtime(game)
  _with_gateway_env({}, function()
    local ok = gateway.start(game, player, _entry({ on_purchase = fn }))
    _assert_eq(ok, true, "start with a function on_purchase should succeed")
  end)

  _assert_eq(rt.pending_by_role_id[77][1].on_purchase, fn,
    "a function on_purchase should enter the pending context unchanged")

  local other_rt = gateway._runtime(game)
  _with_gateway_env({}, function()
    local ok = gateway.start(game, player, _entry({ on_purchase = "not-a-function" }))
    _assert_eq(ok, true, "start with a non-function on_purchase should succeed")
  end)

  _assert_eq(other_rt.pending_by_role_id[77][2].on_purchase, nil,
    "a non-function on_purchase must not leak into the pending context")
end

local function _test_eggy_paid_gateway_callback_hides_purchase_panel()
  local gateway = require("src.host.paid_purchase_gateway")
  local player = _player(99)
  local entry = _entry()
  local game = _game_with_player(player)
  local rt = gateway._runtime(game)
  local hidden = nil

  gateway._push_pending(rt, 5, {
    player_id = player.id,
    product_id = entry.product_id,
    entry = entry,
    goods_id = "goods_123",
  })

  with_patches({
    {
      target = require("src.foundation.ports.runtime_ports"),
      key = "resolve_role",
      value = function()
        return {
          set_goods_panel_visible = function(visible)
            hidden = visible
          end,
        }
      end,
    },
  }, function()
    gateway._on_purchase_goods_callback(game, rt, {
      goods_id = "goods_123",
      role = { get_roleid = function() return 5 end },
    })
  end)

  _assert_eq(hidden, false, "successful callback should hide purchase panel")
end

-- 购买页无关闭接口:回调里对同一商品以 0.1 秒重开,把购买页立即收起(真机 2026-10-29 验证)。
local function _closing_callback_role(calls)
  return {
    get_roleid = function() return 5 end,
    show_goods_purchase_panel = function(goods_id, show_time)
      calls[#calls + 1] = { goods_id = goods_id, show_time = show_time }
    end,
  }
end

local function _test_eggy_paid_gateway_callback_closes_goods_purchase_panel()
  local gateway = require("src.host.paid_purchase_gateway")
  local player = _player(99)
  local entry = _entry()
  local game = _game_with_player(player)
  local rt = gateway._runtime(game)
  local calls = {}
  gateway._push_pending(rt, 5, {
    player_id = player.id,
    product_id = entry.product_id,
    entry = entry,
    goods_id = "goods_123",
  })

  with_patches({
    {
      target = require("src.foundation.ports.runtime_ports"),
      key = "resolve_role",
      value = function() return {} end,
    },
  }, function()
    gateway._on_purchase_goods_callback(game, rt, { goods_id = "goods_123", role = _closing_callback_role(calls) })
  end)

  luassert.same({ { goods_id = "goods_123", show_time = 0.1 } }, calls,
    "successful callback should reopen the same goods with 0.1s to close the purchase panel")
end

local function _test_eggy_paid_gateway_callback_closes_panel_even_without_pending()
  local gateway = require("src.host.paid_purchase_gateway")
  local game = _game_with_player(_player(99))
  local rt = gateway._runtime(game)
  local calls = {}

  gateway._on_purchase_goods_callback(game, rt, { goods_id = "goods_123", role = _closing_callback_role(calls) })

  luassert.same({ { goods_id = "goods_123", show_time = 0.1 } }, calls,
    "callback without pending should still close the purchase panel")
end

local function _test_eggy_paid_gateway_registers_purchase_events_once()
  local gateway = require("src.host.paid_purchase_gateway")
  local player = _player(1)
  local game = _game_with_player(player)
  local registrations = {}

  with_patches({
    {
      target = require("src.foundation.ports.runtime_ports"),
      key = "resolve_role",
      value = function()
        return { get_roleid = function() return 5 end }
      end,
    },
    { key = "EVENT", value = { SPEC_ROLE_PURCHASE_GOODS = "SPEC_ROLE_PURCHASE_GOODS" } },
    {
      key = "RegisterTriggerEvent",
      value = function(event_key)
        registrations[#registrations + 1] = event_key
      end,
    },
  }, function()
    gateway.setup_for_game(game)
    gateway.setup_for_game(game)
  end)

  local rt = gateway._runtime(game)
  _assert_eq(#registrations, 1, "setup should register each role once")
  _assert_eq(registrations[1][1], "SPEC_ROLE_PURCHASE_GOODS", "event kind should be purchase callback")
  _assert_eq(registrations[1][2], 5, "event should register host role id")
  _assert_eq(rt.registered_role_ids[5], true, "runtime should remember registered role id")
  _assert_eq(rt.setup_done, true, "runtime should mark setup done")
end

local function _test_eggy_paid_gateway_skips_event_registration_without_event_contract()
  local gateway = require("src.host.paid_purchase_gateway")
  local player = _player(1)
  local game = _game_with_player(player)
  local registrations = 0

  with_patches({
    {
      target = require("src.foundation.ports.runtime_ports"),
      key = "resolve_role",
      value = function()
        return { get_roleid = function() return 5 end }
      end,
    },
    { key = "EVENT", value = nil },
    {
      key = "RegisterTriggerEvent",
      value = function()
        registrations = registrations + 1
      end,
    },
  }, function()
    gateway.setup_for_game(game)
  end)

  _assert_eq(registrations, 0, "missing EVENT contract should not register trigger")
  _assert_eq(gateway._runtime(game).registered_role_ids[5], nil,
    "missing EVENT contract should not mark role registered")
end


it("test_eggy_paid_gateway_callback_missing_goods_id", _test_eggy_paid_gateway_callback_missing_goods_id)
it("test_eggy_paid_gateway_callback_empty_goods_id", _test_eggy_paid_gateway_callback_empty_goods_id)
it("test_eggy_paid_gateway_callback_missing_pending", _test_eggy_paid_gateway_callback_missing_pending)
it("test_eggy_paid_gateway_callback_missing_player", _test_eggy_paid_gateway_callback_missing_player)
it("test_eggy_paid_gateway_callback_missing_entry", _test_eggy_paid_gateway_callback_missing_entry)
it("test_eggy_paid_gateway_callback_success_with_on_purchase", _test_eggy_paid_gateway_callback_success_with_on_purchase)
it("test_eggy_paid_gateway_callback_uses_pending_specific_on_purchase", _test_eggy_paid_gateway_callback_uses_pending_specific_on_purchase)
it("test_eggy_paid_gateway_callback_success_without_on_purchase", _test_eggy_paid_gateway_callback_success_without_on_purchase)
it("test_eggy_paid_gateway_start_missing_purchase_api", _test_eggy_paid_gateway_start_missing_purchase_api)
it("test_eggy_paid_gateway_start_uses_zero_arity_role_id_and_dot_panel_args", _test_eggy_paid_gateway_start_uses_zero_arity_role_id_and_dot_panel_args)
it("test_eggy_paid_gateway_can_start_reports_mapping_role_and_api_failures", _test_eggy_paid_gateway_can_start_reports_mapping_role_and_api_failures)
it("test_eggy_paid_gateway_start_reports_specific_failure_reasons", _test_eggy_paid_gateway_start_reports_specific_failure_reasons)
it("test_eggy_paid_gateway_treats_empty_goods_id_as_missing_mapping", _test_eggy_paid_gateway_treats_empty_goods_id_as_missing_mapping)
it("test_eggy_paid_gateway_ignores_empty_goods_names", _test_eggy_paid_gateway_ignores_empty_goods_names)
it("test_eggy_paid_gateway_falls_back_to_player_id_when_role_id_fails", _test_eggy_paid_gateway_falls_back_to_player_id_when_role_id_fails)
it("test_eggy_paid_gateway_warns_mapping_edge_cases", _test_eggy_paid_gateway_warns_mapping_edge_cases)
it("test_eggy_paid_gateway_warns_distinct_mapping_failure_reasons", _test_eggy_paid_gateway_warns_distinct_mapping_failure_reasons)
it("test_eggy_paid_gateway_missing_or_broken_goods_list_maps_unavailable", _test_eggy_paid_gateway_missing_or_broken_goods_list_maps_unavailable)
it("test_eggy_paid_gateway_callback_pending_missing_or_unmatched", _test_eggy_paid_gateway_callback_pending_missing_or_unmatched)
it("test_eggy_paid_gateway_pending_queue_recovers_and_cleans_up", _test_eggy_paid_gateway_pending_queue_recovers_and_cleans_up)
it("test_eggy_paid_gateway_pending_queue_appends_existing_queue", _test_eggy_paid_gateway_pending_queue_appends_existing_queue)
it("test_eggy_paid_gateway_mapping_missing_warn_carries_full_args", _test_eggy_paid_gateway_mapping_missing_warn_carries_full_args)
it("test_eggy_paid_gateway_role_id_failure_warn_carries_player_id", _test_eggy_paid_gateway_role_id_failure_warn_carries_player_id)
it("test_eggy_paid_gateway_register_guard_skips_already_registered_roles", _test_eggy_paid_gateway_register_guard_skips_already_registered_roles)
it("test_eggy_paid_gateway_panel_call_failure_warns_with_caption", _test_eggy_paid_gateway_panel_call_failure_warns_with_caption)
it("test_eggy_paid_gateway_pending_on_purchase_field_keeps_only_functions", _test_eggy_paid_gateway_pending_on_purchase_field_keeps_only_functions)
it("test_eggy_paid_gateway_callback_hides_purchase_panel", _test_eggy_paid_gateway_callback_hides_purchase_panel)
it("test_eggy_paid_gateway_callback_closes_goods_purchase_panel", _test_eggy_paid_gateway_callback_closes_goods_purchase_panel)
it("test_eggy_paid_gateway_callback_closes_panel_even_without_pending",
  _test_eggy_paid_gateway_callback_closes_panel_even_without_pending)
it("test_eggy_paid_gateway_registers_purchase_events_once", _test_eggy_paid_gateway_registers_purchase_events_once)
it("test_eggy_paid_gateway_skips_event_registration_without_event_contract", _test_eggy_paid_gateway_skips_event_registration_without_event_contract)
end)
