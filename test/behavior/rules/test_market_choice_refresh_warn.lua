-- 付费回调刷新黑市弹窗失败时留下可诊断的 warn:写明玩家 id 与商品 id。
-- 观察 refresh_after_paid_callback 的返回值与 logger.warn 文本;builder 产不出
-- 规格即刷新失败,日志在系统边界(logger)替身。
require("test.bootstrap").install_package_paths()
-- luacheck: ignore 143
local luassert = assert
local support = require("test.support.shared_support")
local logger = require("src.foundation.log")
local choice = require("src.rules.market.choice")

describe("TestMarketChoiceRefreshWarn", function()
  it("test_failed_refresh_warns_with_player_and_product_ids", function()
    local warns = {}
    local pending_choice = { kind = "market_buy", owner_role_id = 7, active_tab = "item", page_index = 1 }
    local game = { dirty = {}, turn = { pending_choice = pending_choice } }
    local ok

    support.with_patches({
      { target = choice.builder, key = "build", value = function() return nil end },
      {
        target = logger,
        key = "warn",
        value = function(...)
          warns[#warns + 1] = table.concat({ ... }, " ")
        end,
      },
    }, function()
      ok = choice.session.refresh_after_paid_callback(game, { id = 7, name = "P7" }, { product_id = 2001 })
    end, { skip_runtime_context_refresh = true })

    luassert.is_false(ok, "refresh should report failure when no spec can be built")
    luassert.same({ "market paid callback refresh skipped: player_id=7 product_id=2001" }, warns,
      "warn should name the player and product")
  end)
end)
