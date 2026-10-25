-- #204 皮肤归属模块接口(ADR 0074):只经 skin_ownership 的命令与查询驱动,观察返回值、
-- 存档替身里的 key 值、角色替身上的换模型调用、付费 port 是否被调用、on_complete
-- 回调与成就上报。宿主只在 runtime_ports / 付费购买 port / 成就进度 port 边界替身。
require("test.bootstrap").install_package_paths()
-- busted injects luassert fields on assert.
-- luacheck: ignore 143
local luassert = assert
local support = require("test.support.shared_support")
local host_double = require("test.support.skin_ownership_host")
local logger = require("src.foundation.log")
local runtime_ports = require("src.foundation.ports.runtime_ports")
local achievement_progress_port = require("src.rules.ports.achievement_progress")
local skins = require("src.config.content.skins")
local gift_codes = require("src.config.content.gift_codes")
local skin_ownership = require("src.rules.skin_ownership")

local NAILONG, NAILONG_KEY, NAILONG_ASSET = 5005, 1054, 1073909878
local CAPYBARA, CAPYBARA_KEY = 5006, 1053
local SPONGEBOB, SPONGEBOB_KEY = 5003, 1055
local EQUIPPED_KEY = 1051
local DEFAULT_CREATURE = 1
-- code_hash 由外部 sha256sum 对规范化明文 EGG2026 算出。
local SPONGEBOB_CODE = {
  { id = 3, code_hash = "682f05b696b1ca1d9b2818d793b2b352f4128f8ba4fa9db8770cfb279fce1f3f", rewards = { SPONGEBOB } },
}

local function _assert_eq(actual, expected, message)
  luassert.is.equal(expected, actual, message)
end

local function _patch(patches, fn)
  support.with_patches(patches, fn, { skip_runtime_context_refresh = true })
end

local function _with_warns(fn)
  local warns = {}
  _patch({
    {
      target = logger,
      key = "warn",
      value = function(...)
        warns[#warns + 1] = table.concat({ ... }, " ")
      end,
    },
  }, fn)
  return warns
end

local function _skin_index(product_id)
  for index, skin in ipairs(skins) do
    if skin.product_id == product_id then
      return index
    end
  end
  error("missing skin " .. tostring(product_id))
end

-- 把目录里某款皮肤临时换成改了字段的副本(nil 字段用 false 占位后剔除)。
local function _with_skin_fields(product_id, fields, fn)
  local index = _skin_index(product_id)
  local changed = {}
  for key, value in pairs(skins[index]) do
    changed[key] = value
  end
  for key, value in pairs(fields) do
    if value == false then
      changed[key] = nil
    else
      changed[key] = value
    end
  end
  _patch({ { target = skins, key = index, value = changed } }, fn)
end

local function _buy(state, role_id, product_id, gateway)
  local completed = {}
  local started = skin_ownership.start_purchase(state, role_id, product_id, function(result)
    completed[#completed + 1] = result
  end)
  local entry = gateway.last_entry()
  return started, entry, completed
end

local function _model_ops(host)
  local ops = {}
  for _, call in ipairs(host.model_calls) do
    ops[#ops + 1] = call.op .. ":" .. tostring(call.args[1])
  end
  return ops
end

describe("TestSkinOwnership", function()
  local achievements

  before_each(function()
    achievements = host_double.install_achievements()
  end)

  after_each(function()
    achievement_progress_port.reset_for_tests()
    support.restore_runtime_services()
  end)

  -- ===== ADR 0074 第 1 条:归属不分来源 =====

  it("test_purchase_gift_and_gift_code_write_the_same_ownership", function()
    local host = host_double.install()
    local gateway = host_double.install_paid_gateway()
    local state = host_double.state()

    local _, entry = _buy(state, 1, NAILONG, gateway)
    entry.on_purchase()
    local granted = skin_ownership.grant(state, 1, CAPYBARA)
    local redeemed
    _patch({ { target = gift_codes, key = "codes", value = SPONGEBOB_CODE } }, function()
      redeemed = skin_ownership.redeem(state, 1, "EGG2026")
    end)

    _assert_eq(granted.accepted, true, "gift should be accepted")
    _assert_eq(granted.persisted, true, "gift should report the archive write")
    _assert_eq(redeemed.status, "granted", "gift code should grant")
    for _, key in ipairs({ NAILONG_KEY, CAPYBARA_KEY, SPONGEBOB_KEY }) do
      _assert_eq(host.read(1, key), 1, "every source should write ownership key " .. key)
    end
    local reentered = host_double.state()
    skin_ownership.restore(reentered, 1)
    for _, product_id in ipairs({ NAILONG, CAPYBARA, SPONGEBOB }) do
      _assert_eq(skin_ownership.owns(state, 1, product_id), true, "owned this session: " .. product_id)
      _assert_eq(skin_ownership.owns(reentered, 1, product_id), true, "owned after re-entry: " .. product_id)
    end
  end)

  it("test_grant_rejects_unknown_product_and_missing_role", function()
    host_double.install()
    local state = host_double.state()

    local unknown = skin_ownership.grant(state, 1, 999)
    local roleless = skin_ownership.grant(state, nil, NAILONG)

    _assert_eq(unknown.accepted, false, "unknown product should be rejected")
    _assert_eq(unknown.reason, "missing_product", "unknown product reason")
    _assert_eq(roleless.accepted, false, "missing role should be rejected")
    _assert_eq(roleless.reason, "missing_role", "missing role reason")
  end)

  -- ===== ADR 0074 第 2 条:存档不可用不卖 =====

  it("test_purchase_is_refused_without_calling_the_paid_port_when_archives_are_disabled", function()
    host_double.install({ enabled = false })
    local gateway = host_double.install_paid_gateway()
    local state = host_double.state()

    local started = _buy(state, 1, NAILONG, gateway)

    _assert_eq(started.accepted, false, "purchase should be refused")
    _assert_eq(started.reason, "archive_unavailable", "refusal reason")
    _assert_eq(#gateway.entries, 0, "paid port must not be called")
  end)

  it("test_purchase_is_refused_for_a_skin_without_archive_key", function()
    host_double.install()
    local gateway = host_double.install_paid_gateway()
    local state = host_double.state()

    _with_skin_fields(NAILONG, { archive_key = false }, function()
      local started = _buy(state, 1, NAILONG, gateway)
      _assert_eq(started.reason, "archive_unavailable", "skin without archive key cannot be sold")
    end)
    _assert_eq(#gateway.entries, 0, "paid port must not be called")
  end)

  -- ===== ADR 0074 第 3 条:付款后写档失败不撤销,开商店幂等补写 =====

  it("test_failed_ownership_write_after_payment_still_grants_and_equips_then_shop_open_backfills", function()
    local host = host_double.install({ int_write_ok = false })
    local gateway = host_double.install_paid_gateway()
    local state = host_double.state()
    local _, entry, completed = _buy(state, 1, NAILONG, gateway)

    local warns = _with_warns(function()
      _assert_eq(entry.on_purchase(), true, "host callback should report fulfilment")
    end)

    _assert_eq(completed[1].accepted, true, "completion should be accepted")
    _assert_eq(completed[1].persisted, false, "completion should report the failed write")
    _assert_eq(skin_ownership.owns(state, 1, NAILONG), true, "paid skin stays owned this session")
    _assert_eq(skin_ownership.equipped(state, 1), NAILONG, "paid skin is put on")
    luassert.truthy(#warns > 0, "failed write should warn")

    host.opts.int_write_ok = true
    skin_ownership.sync_on_shop_open(state, 1)
    _assert_eq(host.read(1, NAILONG_KEY), 1, "opening the shop should backfill the ownership")
  end)

  it("test_failed_equipped_write_keeps_the_skin_on_with_warn", function()
    local host = host_double.install({ seed = { [host_double.seed_key(1, NAILONG_KEY)] = 1 } })
    local state = host_double.state()
    skin_ownership.restore(state, 1)
    host.opts.int_write_ok = false

    local warns = _with_warns(function()
      skin_ownership.equip(state, 1, NAILONG)
    end)

    _assert_eq(skin_ownership.equipped(state, 1), NAILONG, "skin stays on")
    _assert_eq(host.read(1, EQUIPPED_KEY), nil, "equipped write did not land")
    luassert.truthy(#warns > 0, "failed equipped write should warn")
  end)

  it("test_shop_open_backfill_is_idempotent_and_keeps_archived_ownership", function()
    local host = host_double.install({ seed = { [host_double.seed_key(1, CAPYBARA_KEY)] = 1 } })
    local state = host_double.state()

    skin_ownership.sync_on_shop_open(state, 1)
    skin_ownership.sync_on_shop_open(state, 1)

    _assert_eq(skin_ownership.owns(state, 1, CAPYBARA), true, "archived ownership is read on shop open")
    _assert_eq(host.read(1, NAILONG_KEY), nil, "nothing owned is not written")
    _assert_eq(host.read(1, CAPYBARA_KEY), 1, "archived ownership stays")
  end)

  -- ===== ADR 0074 第 4 条:开局读档恢复穿戴,不补写;开商店再读一次 =====

  it("test_restore_loads_ownership_and_reequips_the_saved_skin", function()
    local host = host_double.install({
      seed = {
        [host_double.seed_key(1, NAILONG_KEY)] = 1,
        [host_double.seed_key(1, EQUIPPED_KEY)] = NAILONG,
      },
    })
    local state = host_double.state()

    local restored = skin_ownership.restore(state, 1)

    _assert_eq(restored, NAILONG, "restore reports the re-equipped skin")
    _assert_eq(skin_ownership.owns(state, 1, NAILONG), true, "ownership restored")
    _assert_eq(skin_ownership.equipped(state, 1), NAILONG, "saved skin put back on")
    luassert.same({ "set_model:" .. NAILONG_ASSET }, _model_ops(host), "model changed to the saved skin")
    _assert_eq(#achievements, 1, "re-equip reports skin equipped")
  end)

  it("test_restore_ignores_a_saved_skin_that_is_not_owned", function()
    local host = host_double.install({ seed = { [host_double.seed_key(1, EQUIPPED_KEY)] = NAILONG } })
    local state = host_double.state()

    _assert_eq(skin_ownership.restore(state, 1), nil, "nothing re-equipped")
    _assert_eq(skin_ownership.equipped(state, 1), nil, "unowned saved skin is not put on")
    luassert.same({}, _model_ops(host), "model untouched")
  end)

  it("test_restore_does_not_backfill_session_ownership_missing_from_archive", function()
    local host = host_double.install({ int_write_ok = false })
    local state = host_double.state()
    _with_warns(function()
      skin_ownership.grant(state, 1, NAILONG)
    end)
    host.opts.int_write_ok = true

    skin_ownership.restore(state, 1)

    _assert_eq(host.read(1, NAILONG_KEY), nil, "restore must not backfill")
    _assert_eq(skin_ownership.owns(state, 1, NAILONG), true, "session ownership kept")
  end)

  it("test_shop_open_reads_the_archive_again_after_restore", function()
    local host = host_double.install()
    local state = host_double.state()
    skin_ownership.restore(state, 1)
    host.write(1, CAPYBARA_KEY, 1)

    _assert_eq(skin_ownership.owns(state, 1, CAPYBARA), false, "not yet read")
    skin_ownership.sync_on_shop_open(state, 1)
    _assert_eq(skin_ownership.owns(state, 1, CAPYBARA), true, "shop open re-reads the archive")
  end)

  it("test_disabled_archives_read_nothing_on_restore_or_shop_open", function()
    host_double.install({ enabled = false })
    local state = host_double.state()

    _with_warns(function()
      _assert_eq(skin_ownership.restore(state, 1), nil, "nothing restored")
      skin_ownership.sync_on_shop_open(state, 1)
    end)
    _assert_eq(skin_ownership.owns(state, 1, NAILONG), false, "nothing owned")
  end)

  -- ===== 付费购买与在途约束 =====

  it("test_paid_purchase_builds_a_skin_entry_and_completion_owns_equips_and_reports", function()
    local host = host_double.install()
    local gateway = host_double.install_paid_gateway()
    local state = host_double.state()

    local started, entry, completed = _buy(state, 1, NAILONG, gateway)

    _assert_eq(started.accepted, true, "purchase should start")
    _assert_eq(started.product_id, NAILONG, "start names the product")
    _assert_eq(entry.kind, "skin", "paid entry kind")
    _assert_eq(entry.product_id, NAILONG, "paid entry product")
    _assert_eq(entry.price, 68, "paid entry price")
    _assert_eq(entry.currency, "金豆", "paid entry currency")
    _assert_eq(gateway.entries[1].player.id, 1, "buyer resolved from the game")
    _assert_eq(skin_ownership.owns(state, 1, NAILONG), false, "not owned before the host completes")
    luassert.same({}, completed, "no completion before the host callback")

    _assert_eq(entry.on_purchase(), true, "host callback reports fulfilment")

    _assert_eq(#completed, 1, "on_complete is called once")
    _assert_eq(completed[1].accepted, true, "completion accepted")
    _assert_eq(completed[1].product_id, NAILONG, "completion names the product")
    _assert_eq(completed[1].equipped, true, "model change succeeded")
    _assert_eq(completed[1].persisted, true, "ownership persisted")
    _assert_eq(skin_ownership.owns(state, 1, NAILONG), true, "owned after completion")
    _assert_eq(skin_ownership.equipped(state, 1), NAILONG, "worn after completion")
    _assert_eq(host.read(1, NAILONG_KEY), 1, "ownership archived")
    _assert_eq(host.read(1, EQUIPPED_KEY), NAILONG, "equipped archived")
    _assert_eq(#achievements, 1, "equip reports achievement progress")
  end)

  it("test_only_one_purchase_in_flight_per_role", function()
    host_double.install()
    local gateway = host_double.install_paid_gateway()
    local state = host_double.state()
    _buy(state, 1, NAILONG, gateway)

    local second = _buy(state, 1, CAPYBARA, gateway)
    local other_role = _buy(state, 2, CAPYBARA, gateway)

    _assert_eq(second.accepted, false, "second purchase refused")
    _assert_eq(second.reason, "purchase_in_flight", "in-flight reason")
    _assert_eq(other_role.accepted, true, "another role may buy")
    _assert_eq(#gateway.entries, 2, "refused purchase does not reach the paid port")
  end)

  it("test_duplicate_completion_is_rejected_and_does_not_reequip", function()
    host_double.install()
    local gateway = host_double.install_paid_gateway()
    local state = host_double.state()
    local _, entry, completed = _buy(state, 1, NAILONG, gateway)
    entry.on_purchase()

    _assert_eq(entry.on_purchase(), false, "second callback is not a fulfilment")
    _assert_eq(completed[2].accepted, false, "second completion rejected")
    _assert_eq(completed[2].reason, "pending_purchase_missing", "duplicate reason")
  end)

  it("test_completion_must_match_the_in_flight_product", function()
    host_double.install()
    local refuse_first = true
    local gateway = host_double.install_paid_gateway({
      start = function()
        local accepted = not refuse_first
        refuse_first = false
        return accepted
      end,
    })
    local state = host_double.state()
    local refused, stale_entry = _buy(state, 1, CAPYBARA, gateway)
    _buy(state, 1, NAILONG, gateway)

    local fulfilled = stale_entry.on_purchase()

    _assert_eq(refused.accepted, false, "first purchase refused by the gateway")
    _assert_eq(fulfilled, false, "stale callback is not a fulfilment")
    _assert_eq(skin_ownership.owns(state, 1, CAPYBARA), false, "mismatched product is not granted")
  end)

  it("test_gateway_refusals_keep_their_reason_and_clear_the_in_flight_purchase", function()
    host_double.install()
    local cases = {
      { start = function() return false, "host_busy" end, reason = "host_busy" },
      { start = function() return false end, reason = "paid_gateway_rejected" },
      { start = function() error("boom") end, reason = "paid_gateway_missing" },
    }
    for _, case in ipairs(cases) do
      local gateway = host_double.install_paid_gateway({ start = case.start })
      local state = host_double.state()

      local refused
      _with_warns(function()
        refused = _buy(state, 1, NAILONG, gateway)
      end)
      _assert_eq(refused.accepted, false, "gateway refusal: " .. case.reason)
      _assert_eq(refused.reason, case.reason, "gateway refusal reason")

      local retry_gateway = host_double.install_paid_gateway()
      _assert_eq(_buy(state, 1, NAILONG, retry_gateway).accepted, true, "refusal clears the in-flight purchase")
    end
  end)

  it("test_gateway_error_leaves_a_warn_with_the_error_and_role", function()
    host_double.install()
    local gateway = host_double.install_paid_gateway({ start = function() error("gateway boom") end })

    local warns = _with_warns(function()
      _buy(host_double.state(), 1, NAILONG, gateway)
    end)

    local joined = table.concat(warns, "\n")
    luassert.truthy(joined:find("gateway boom", 1, true) and joined:find("role_id=1", 1, true), joined)
  end)

  it("test_completion_still_wears_and_reports_when_the_model_port_throws", function()
    local host = host_double.install()
    local gateway = host_double.install_paid_gateway()
    local state = host_double.state()
    local _, entry, completed = _buy(state, 1, NAILONG, gateway)

    local warns = _with_warns(function()
      _patch({
        { target = runtime_ports, key = "set_role_model", value = function() error("model boom") end },
      }, function()
        entry.on_purchase()
      end)
    end)

    _assert_eq(#completed, 1, "on_complete still called")
    _assert_eq(completed[1].accepted, true, "completion accepted")
    _assert_eq(completed[1].equipped, false, "model change reported as failed")
    _assert_eq(skin_ownership.equipped(state, 1), NAILONG, "worn this session")
    _assert_eq(host.read(1, EQUIPPED_KEY), NAILONG, "equipped archived")
    luassert.truthy(table.concat(warns, "\n"):find("model boom", 1, true), table.concat(warns, "\n"))
  end)

  it("test_purchase_rejects_missing_buyer_contexts_and_invalid_products", function()
    host_double.install()
    local gateway = host_double.install_paid_gateway()

    _assert_eq(_buy({ ui = {} }, 1, NAILONG, gateway).reason, "missing_game", "no game")
    _assert_eq(_buy({ game = {} }, 1, NAILONG, gateway).reason, "missing_player_lookup", "no lookup")
    local nobody = { game = { find_player_by_id = function() return nil end } }
    _assert_eq(_buy(nobody, 1, NAILONG, gateway).reason, "missing_player", "no player")
    _assert_eq(_buy(host_double.state(), nil, NAILONG, gateway).reason, "missing_role", "no role")
    _assert_eq(_buy(host_double.state(), 1, 999, gateway).reason, "missing_product", "unknown product")
    _with_skin_fields(NAILONG, { unlock = "gift" }, function()
      _assert_eq(_buy(host_double.state(), 1, NAILONG, gateway).reason, "invalid_purchase_skin", "gift skin")
    end)
    _assert_eq(#gateway.entries, 0, "no refused purchase reaches the paid port")
  end)

  -- ===== 穿戴 =====

  it("test_equip_owned_skin_changes_model_persists_and_reports_once", function()
    local host = host_double.install()
    local state = host_double.state()
    skin_ownership.grant(state, 1, NAILONG)

    local result = skin_ownership.equip(state, 1, NAILONG)

    _assert_eq(result.accepted, true, "equip accepted")
    _assert_eq(result.equipped, true, "model changed")
    _assert_eq(skin_ownership.equipped(state, 1), NAILONG, "worn")
    _assert_eq(host.read(1, EQUIPPED_KEY), NAILONG, "equipped archived")
    luassert.same({ "set_model:" .. NAILONG_ASSET }, _model_ops(host), "model set to the skin asset")
    _assert_eq(#achievements, 1, "achievement reported once")
    _assert_eq(achievements[1].product_id, NAILONG, "achievement names the skin")
  end)

  it("test_equip_refuses_unowned_or_unknown_skins_without_touching_the_model", function()
    local host = host_double.install()
    local state = host_double.state()

    _assert_eq(skin_ownership.equip(state, 1, NAILONG).reason, "not_owned", "unowned skin")
    _assert_eq(skin_ownership.equip(state, 1, 999).reason, "missing_product", "unknown skin")
    luassert.same({}, _model_ops(host), "model untouched")
    _assert_eq(skin_ownership.equipped(state, 1), nil, "nothing worn")
  end)

  it("test_failed_model_change_still_wears_the_skin_but_reports_no_achievement", function()
    local host = host_double.install({ set_model_ok = false })
    local state = host_double.state()
    skin_ownership.grant(state, 1, NAILONG)

    local result
    _with_warns(function()
      result = skin_ownership.equip(state, 1, NAILONG)
    end)

    _assert_eq(result.accepted, true, "equip accepted")
    _assert_eq(result.equipped, false, "model change failed")
    _assert_eq(skin_ownership.equipped(state, 1), NAILONG, "selection kept")
    _assert_eq(host.read(1, EQUIPPED_KEY), NAILONG, "equipped archived")
    _assert_eq(#achievements, 0, "no achievement without a model change")
  end)

  it("test_unequip_still_clears_the_saved_skin_when_the_model_port_throws", function()
    local host = host_double.install()
    local state = host_double.state()
    skin_ownership.grant(state, 1, NAILONG)
    skin_ownership.equip(state, 1, NAILONG)

    local result
    local warns = _with_warns(function()
      _patch({
        { target = runtime_ports, key = "reset_role_model", value = function() error("model boom") end },
      }, function()
        result = skin_ownership.unequip(state, 1)
      end)
    end)

    _assert_eq(result.accepted, true, "unequip accepted")
    _assert_eq(skin_ownership.equipped(state, 1), nil, "selection cleared")
    _assert_eq(host.read(1, EQUIPPED_KEY), 0, "saved skin cleared to 0")
    luassert.truthy(table.concat(warns, "\n"):find("model boom", 1, true), table.concat(warns, "\n"))
  end)

  it("test_unequip_clears_saved_skin_and_resets_the_model", function()
    local host = host_double.install()
    local state = host_double.state()
    skin_ownership.grant(state, 1, NAILONG)
    skin_ownership.equip(state, 1, NAILONG)

    local result = skin_ownership.unequip(state, 1)

    _assert_eq(result.accepted, true, "unequip accepted")
    _assert_eq(skin_ownership.equipped(state, 1), nil, "nothing worn")
    _assert_eq(host.read(1, EQUIPPED_KEY), 0, "equipped archive cleared to 0")
    _assert_eq(_model_ops(host)[2], "reset_model:nil", "model reset through the host API")
  end)

  it("test_unequip_falls_back_to_the_default_creature_when_reset_fails", function()
    local host = host_double.install({ reset_model_ok = false })
    local state = host_double.state()

    _with_warns(function()
      skin_ownership.unequip(state, 1)
    end)

    luassert.same({ "reset_model:nil", "set_model:" .. DEFAULT_CREATURE }, _model_ops(host),
      "default creature applied after the failed reset")
    _assert_eq(host.read(1, EQUIPPED_KEY), 0, "equipped archive cleared")
  end)

  it("test_unequip_rejects_a_missing_role", function()
    host_double.install()
    _assert_eq(skin_ownership.unequip(host_double.state(), nil).reason, "missing_role", "no role")
  end)

  -- ===== 纯查询 =====

  it("test_queries_create_no_state", function()
    host_double.install()
    local state = host_double.state()
    local keys_before = {}
    for key in pairs(state) do
      keys_before[#keys_before + 1] = key
    end
    table.sort(keys_before)

    _assert_eq(skin_ownership.owns(state, 1, NAILONG), false, "nothing owned")
    _assert_eq(skin_ownership.equipped(state, 1), nil, "nothing worn")
    _assert_eq(skin_ownership.owns(nil, 1, NAILONG), false, "nil state is safe")
    _assert_eq(skin_ownership.equipped(nil, 1), nil, "nil state is safe")

    local keys_after = {}
    for key in pairs(state) do
      keys_after[#keys_after + 1] = key
    end
    table.sort(keys_after)
    luassert.same(keys_before, keys_after, "queries must not add state")
  end)

  -- ===== 目录(#495 裁定)=====

  it("test_catalog_sorts_by_price_then_order_then_source_index_with_missing_price_last", function()
    local source = {
      { product_id = 1, price = nil, order = 1 },
      { product_id = 2, price = 198, order = 6 },
      { product_id = 3, price = 198, order = 5 },
      { product_id = 4, price = 68, order = 9 },
      { product_id = 5, price = 198, order = 5 },
    }
    local patches = {}
    for index = 1, #source do
      patches[#patches + 1] = { target = skins, key = index, value = source[index] }
    end
    local ids = {}
    _patch(patches, function()
      for _, skin in ipairs(skin_ownership.catalog()) do
        ids[#ids + 1] = skin.product_id
      end
    end)
    luassert.same({ 4, 3, 5, 2, 1 }, ids, "price asc, order asc, source index, missing price last")
  end)

  it("test_default_catalog_puts_the_cheapest_skin_first", function()
    local ids = {}
    for _, skin in ipairs(skin_ownership.catalog()) do
      ids[#ids + 1] = skin.product_id
    end
    luassert.same({ NAILONG, CAPYBARA, SPONGEBOB, 5004 }, ids, "default catalog order")
  end)
end)
