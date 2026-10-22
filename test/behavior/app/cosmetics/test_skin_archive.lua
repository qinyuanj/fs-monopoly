-- #193 / ADR 0074:皮肤归属以宿主玩家存档为真源。经 transaction 门面 + 生产
-- 存档适配器(skin_archive)观察跨局持久;宿主存档只在 runtime_ports 边界替身。
require("test.bootstrap").install_package_paths()
-- busted injects luassert fields on assert.
-- luacheck: ignore 143
local luassert = assert
local support = require("test.support.shared_support")
local logger = require("src.foundation.log")
local runtime_ports = require("src.foundation.ports.runtime_ports")
local paid_purchase_port = require("src.rules.ports.paid_purchase")
local transaction = require("src.app.cosmetics.transaction")
local skin_archive = require("src.app.cosmetics.skin_archive")

local EQUIPPED_KEY = 1051
local NAILONG = 5005 -- 奶龙,存档 key 1054,目录排序后在槽位 1
local NAILONG_KEY = 1054
local CAPYBARA = 5006 -- 水豚嘟嘟,存档 key 1053,槽位 2
local CAPYBARA_KEY = 1053

local function _assert_eq(actual, expected, message)
  luassert.is.equal(expected, actual, message)
end

-- 宿主自定义存档替身:按 role|key 存 Int;write_ok=false 模拟写档失败(宿主
-- 不报错但值没落下)。
local function _install_archives(opts)
  opts = opts or {}
  local store = {}
  for key, value in pairs(opts.seed or {}) do
    store["1|" .. tostring(key)] = value
  end
  runtime_ports.configure({
    archives_enabled = function()
      return opts.enabled ~= false
    end,
    get_archive_int = function(role_id, key)
      return store[tostring(role_id) .. "|" .. tostring(key)] or 0
    end,
    set_archive_int = function(role_id, key, value)
      if opts.write_ok == false then
        return true
      end
      store[tostring(role_id) .. "|" .. tostring(key)] = value
      return true
    end,
  })
  return function(key)
    return store["1|" .. tostring(key)] or 0
  end
end

local function _state(players)
  players = players or { { id = 1 } }
  return {
    ui = {},
    game = {
      players = players,
      find_player_by_id = function(_, role_id)
        for _, player in ipairs(players) do
          if tostring(player.id) == tostring(role_id) then
            return player
          end
        end
        return nil
      end,
    },
  }
end

local function _capture_equips()
  local equipped = {}
  transaction.configure_equip(function(role_id, skin)
    equipped[#equipped + 1] = { role_id = role_id, product_id = skin.product_id }
    return true
  end)
  return equipped
end

local function _with_paid_gateway(fn)
  local captured = {}
  support.with_patches({
    {
      target = paid_purchase_port,
      key = "start",
      value = function(_, _, entry)
        captured.entry = entry
        return true
      end,
    },
  }, function()
    fn(captured)
  end, { skip_runtime_context_refresh = true })
  return captured
end

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

describe("TestSkinArchive", function()
  before_each(function()
    transaction.reset_for_tests()
    transaction.configure_archive(skin_archive)
  end)

  after_each(function()
    transaction.reset_for_tests()
    paid_purchase_port.reset_for_tests()
    support.restore_runtime_services()
  end)

  it("test_paid_purchase_persists_ownership_and_equipped_skin", function()
    local read = _install_archives()
    local state = _state()
    transaction.handle_skin_transaction(state, 1, { type = "open" })

    _with_paid_gateway(function(captured)
      local started = transaction.handle_skin_transaction(state, 1, { type = "equip_slot", slot_index = 1 })
      _assert_eq(started.action, "purchase_start", "locked skin should start a paid purchase")
      _assert_eq(captured.entry.on_purchase(), true, "payment callback should fulfil")
    end)

    _assert_eq(read(NAILONG_KEY), 1, "purchased skin key should be written as owned")
    _assert_eq(read(EQUIPPED_KEY), NAILONG, "equipped key should store the purchased product_id")
  end)

  it("test_gift_unlock_persists_ownership_like_purchase", function()
    local read = _install_archives()
    local state = _state()
    transaction.handle_skin_transaction(state, 1, { type = "open" })

    transaction.handle_skin_transaction(state, 1, { type = "gift", slot_index = 2 })

    _assert_eq(read(CAPYBARA_KEY), 1, "gift unlock should persist ownership regardless of source")
  end)

  it("test_purchase_is_refused_when_archives_are_disabled", function()
    _install_archives({ enabled = false })
    local state = _state()
    transaction.handle_skin_transaction(state, 1, { type = "open" })

    local captured = _with_paid_gateway(function()
      local result = transaction.handle_skin_transaction(state, 1, { type = "equip_slot", slot_index = 1 })
      _assert_eq(result.accepted, false, "purchase should be refused without archives")
      _assert_eq(result.reason, "archive_unavailable", "refusal reason should be stable")
      luassert.truthy(result.notification ~= nil, "refusal should tell the player why")
    end)

    _assert_eq(captured.entry, nil, "no paid purchase should be started")
    _assert_eq(state.ui.skin_panel.pending_skin_purchase_by_role["1"], nil, "refusal should leave nothing pending")
  end)

  it("test_purchase_is_refused_for_a_skin_without_archive_key", function()
    _install_archives()
    transaction.configure_catalog_for_tests({
      { product_id = 7001, name = "无存档皮", unlock = "purchase", currency = "金豆", price = 68 },
    })
    local state = _state()
    transaction.handle_skin_transaction(state, 1, { type = "open" })

    local captured = _with_paid_gateway(function()
      local result = transaction.handle_skin_transaction(state, 1, { type = "equip_slot", slot_index = 1 })
      _assert_eq(result.reason, "archive_unavailable", "skin without archive_key should not be sold")
    end)

    _assert_eq(captured.entry, nil, "no paid purchase should be started")
  end)

  it("test_failed_archive_write_still_grants_and_equips_with_warn", function()
    _install_archives({ write_ok = false })
    local equipped = _capture_equips()
    local state = _state()
    transaction.handle_skin_transaction(state, 1, { type = "open" })

    local warns = _with_warns(function()
      _with_paid_gateway(function(captured)
        transaction.handle_skin_transaction(state, 1, { type = "equip_slot", slot_index = 1 })
        _assert_eq(captured.entry.on_purchase(), true, "payment callback should still fulfil")
      end)
    end)

    _assert_eq(state.ui.skin_panel.owned_by_role["1"][NAILONG], true, "skin should be owned this session")
    _assert_eq(equipped[#equipped].product_id, NAILONG, "skin should be equipped this session")
    local found = false
    for _, line in ipairs(warns) do
      found = found or (line:find("archive", 1, true) ~= nil and line:find(tostring(NAILONG), 1, true) ~= nil)
    end
    luassert.truthy(found, "failed ownership write should leave a warn naming the product")
  end)

  it("test_failed_equipped_write_keeps_skin_on_with_warn", function()
    _install_archives({ seed = { [NAILONG_KEY] = 1 }, write_ok = false })
    local equipped = _capture_equips()
    local state = _state()
    transaction.handle_skin_transaction(state, 1, { type = "open" })

    local warns = _with_warns(function()
      transaction.handle_skin_transaction(state, 1, { type = "equip_slot", slot_index = 1 })
    end)

    _assert_eq(equipped[#equipped].product_id, NAILONG, "owned skin should still be put on")
    local found = false
    for _, line in ipairs(warns) do
      found = found or (line:find("equipped", 1, true) ~= nil and line:find(tostring(NAILONG), 1, true) ~= nil)
    end
    luassert.truthy(found, "failed equipped write should leave a warn naming the product")
  end)

  it("test_open_reads_archived_ownership", function()
    _install_archives({ seed = { [CAPYBARA_KEY] = 1 } })
    local state = _state()

    transaction.handle_skin_transaction(state, 1, { type = "open" })

    _assert_eq(state.ui.skin_panel.owned_by_role["1"][CAPYBARA], true, "archived ownership should load on open")
    _assert_eq(state.ui.skin_panel.owned_by_role["1"][NAILONG], nil, "unowned keys should stay unowned")
  end)

  it("test_open_backfills_session_ownership_missing_from_archive", function()
    local read = _install_archives()
    local state = _state()
    state.ui.skin_panel = {
      open = false,
      page_index = 1,
      owned_by_role = { ["1"] = { [NAILONG] = true } },
      selected_by_role = {},
    }

    transaction.handle_skin_transaction(state, 1, { type = "open" })

    _assert_eq(read(NAILONG_KEY), 1, "open should idempotently write session ownership back")
    _assert_eq(read(CAPYBARA_KEY), 0, "backfill should not invent ownership")
  end)

  it("test_restore_role_loads_ownership_and_reequips_saved_skin", function()
    _install_archives({ seed = { [CAPYBARA_KEY] = 1, [EQUIPPED_KEY] = CAPYBARA } })
    local equipped = _capture_equips()
    local state = _state()

    local restored = transaction.restore_role(state, 1)

    _assert_eq(restored, CAPYBARA, "restore should report the re-equipped product")
    _assert_eq(equipped[1] and equipped[1].product_id, CAPYBARA, "saved skin should be put on via the host")
    _assert_eq(state.ui.skin_panel.open, false, "restoring should not open the shop")
  end)

  it("test_restore_role_ignores_saved_skin_that_is_not_owned", function()
    _install_archives({ seed = { [EQUIPPED_KEY] = CAPYBARA } })
    local equipped = _capture_equips()

    local restored = transaction.restore_role(_state(), 1)

    _assert_eq(restored, nil, "unowned saved skin should not be equipped")
    _assert_eq(#equipped, 0, "no host equip should happen")
  end)

  -- #198:礼包码等非商店来源经「授予归属」入口发放,与购买共用写档路径。
  it("test_grant_ownership_persists_and_is_seen_this_session_and_after_reentry", function()
    local read = _install_archives()
    local state = _state()

    local result = transaction.grant_ownership(state, 1, CAPYBARA)

    _assert_eq(result.accepted, true, "grant should be accepted")
    _assert_eq(result.persisted, true, "grant should report the archive write landed")
    _assert_eq(read(CAPYBARA_KEY), 1, "grant should write the same ownership key as purchase")
    _assert_eq(transaction.owns_product(state, 1, CAPYBARA), true, "granted skin should be owned this session")
    _assert_eq(transaction.owns_product(state, 1, NAILONG), false, "grant should not invent other ownership")

    local reentered = _state()
    transaction.restore_role(reentered, 1)
    _assert_eq(transaction.owns_product(reentered, 1, CAPYBARA), true, "granted skin should survive re-entry")
  end)

  it("test_grant_ownership_failed_write_keeps_session_ownership_with_warn", function()
    _install_archives({ write_ok = false })
    local state = _state()

    local result
    local warns = _with_warns(function()
      result = transaction.grant_ownership(state, 1, NAILONG)
    end)

    _assert_eq(result.accepted, true, "grant should still be accepted for the session")
    _assert_eq(result.persisted, false, "grant should report the archive write did not land")
    _assert_eq(transaction.owns_product(state, 1, NAILONG), true, "session ownership should not be revoked")
    local found = false
    for _, line in ipairs(warns) do
      found = found or (line:find("archive", 1, true) ~= nil and line:find(tostring(NAILONG), 1, true) ~= nil)
    end
    luassert.truthy(found, "failed grant write should leave a warn naming the product")
  end)

  it("test_grant_ownership_rejects_unknown_product", function()
    _install_archives()
    local state = _state()

    local result = transaction.grant_ownership(state, 1, 9999)

    _assert_eq(result.accepted, false, "unknown product should be rejected")
    _assert_eq(result.reason, "missing_product", "rejection reason should be stable")
  end)

  -- #195 review:owns_product 是纯查询,查询不能把 ui.skin_panel 建出来(副作用)。
  it("test_owns_product_is_a_pure_query_without_creating_the_panel", function()
    _install_archives({ seed = { [NAILONG_KEY] = 1 } })
    local state = _state()

    _assert_eq(transaction.owns_product(state, 1, NAILONG), false,
      "before refresh_ownership the session cache is empty")
    luassert.is_nil(state.ui.skin_panel,
      "a pure ownership query must not create the skin panel")
  end)

  it("test_refresh_ownership_reports_archived_skins_or_nil_when_disabled", function()
    _install_archives({ seed = { [CAPYBARA_KEY] = 1 } })
    local state = _state()

    local owned = transaction.refresh_ownership(state, 1)

    _assert_eq(owned[CAPYBARA], true, "archived skin should be reported")
    _assert_eq(owned[NAILONG], nil, "unarchived skin should not be reported")
    _assert_eq(transaction.owns_product(state, 1, CAPYBARA), true, "refresh should load archive into the session")

    _install_archives({ enabled = false })
    _assert_eq(transaction.refresh_ownership(_state(), 1), nil, "disabled archives should report nil")
  end)

  it("test_unequip_clears_saved_skin", function()
    local read = _install_archives({ seed = { [NAILONG_KEY] = 1, [EQUIPPED_KEY] = NAILONG } })
    local state = _state()
    transaction.handle_skin_transaction(state, 1, { type = "open" })

    transaction.handle_skin_transaction(state, 1, { type = "unequip" })

    _assert_eq(read(EQUIPPED_KEY), 0, "unequip should store 0 as not wearing")
  end)
end)
