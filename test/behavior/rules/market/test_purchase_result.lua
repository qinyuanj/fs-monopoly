require("test.bootstrap").install_package_paths()
local luassert = require("luassert")
-- purchase_result 构造器与 canonicalize 直测。
-- purchase.execute 的 4 种历史 raw 形状逐一钉死,不依赖活流量。
local purchase_result = require("src.rules.market.purchase_result")

local function _eq(actual, expected, msg)
  luassert.truthy(actual == expected, tostring(msg) .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end


describe("TestPurchaseResult", function()
  it("test_builds fulfilled results with fulfilled_now forced true", function()
    local r = purchase_result.fulfilled({ kind = "item", product_id = 101, inventory_full_after = true })
    _eq(purchase_result.is_result(r), true, "fulfilled is a result")
    _eq(r.status, "fulfilled", "status")
    _eq(r.fulfilled_now, true, "fulfilled_now forced true")
    _eq(r.inventory_full_after, true, "carries inventory_full_after")
    _eq(r.product_id, 101, "carries product_id")
  end)

  it("test_builds deferred and residual results", function()
    _eq(purchase_result.deferred({ kind = "item", product_id = 9 }).status, "deferred", "deferred status")
    _eq(purchase_result.residual(false).status, "residual", "residual status")
    _eq(purchase_result.residual("x").raw, "x", "residual carries raw")
  end)

  it("test_requires a stable reason for rejected", function()
    _eq(purchase_result.rejected("disabled").status, "rejected", "rejected status")
    _eq(purchase_result.rejected("disabled").reason, "disabled", "rejected reason")
    luassert.truthy(not pcall(purchase_result.rejected), "missing reason must error")
    luassert.truthy(not pcall(purchase_result.rejected, ""), "empty reason must error")
  end)

  it("test_canonicalizes non-table raw as residual (NOT rejected)", function()
    _eq(purchase_result.canonicalize(false).status, "residual", "bare false is residual")
    _eq(purchase_result.canonicalize(nil).status, "residual", "nil is residual")
    _eq(purchase_result.canonicalize("s").status, "residual", "string is residual")
  end)

  it("test_canonicalizes ok=false as rejected preserving reason with fallback", function()
    _eq(purchase_result.canonicalize({ ok = false, reason = "charge_failed" }).reason, "charge_failed", "explicit reason wins")
    _eq(purchase_result.canonicalize({ ok = false }, "insufficient").reason, "insufficient", "bare failure takes fallback")
    _eq(purchase_result.canonicalize({ ok = false }).reason, "purchase_rejected", "default reason when no fallback")
  end)

  it("test_canonicalizes deferred and fulfilled success shapes", function()
    local deferred = purchase_result.canonicalize({ ok = true, kind = "item", product_id = 7, deferred_fulfillment = true })
    _eq(deferred.status, "deferred", "deferred_fulfillment maps to deferred")
    _eq(deferred.product_id, 7, "deferred carries product_id")

    local fulfilled = purchase_result.canonicalize({ ok = true, kind = "item", product_id = 5, fulfilled_now = true, inventory_full_after = true })
    _eq(fulfilled.status, "fulfilled", "fulfilled_now maps to fulfilled")
    _eq(fulfilled.inventory_full_after, true, "fulfilled carries inventory_full_after")
  end)

  it("test_canonicalizes ok=nil tables and bare ok=true as residual", function()
    _eq(purchase_result.canonicalize({ ok = nil, intent = { kind = "need_choice" } }).status, "residual",
      "intent-carrier without terminal markers is residual")
    _eq(purchase_result.canonicalize({ ok = true }).status, "residual", "ok=true without fulfilled_now/deferred is residual")
  end)

  it("test_is idempotent on existing results", function()
    local original = purchase_result.deferred({ product_id = 1 })
    _eq(purchase_result.canonicalize(original), original, "canonicalize passes through results")
  end)


end)
