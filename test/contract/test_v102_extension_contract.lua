local luassert = assert

local support = require("test.support.shared_support")
local _with_patches = support.with_patches
local transaction = require("src.app.cosmetics.transaction")

describe("TestV102ExtensionContract", function()
  after_each(function()
    require("src.ui.screens.skin_panel").reset_for_tests()
    require("src.ui.screens.item_atlas").reset_for_tests()
    support.restore_runtime_services()
  end)

  it("test_publishes_reveal_constants", function()
  local event_kinds = require("src.config.gameplay.event_kinds")
  local timing = require("src.config.gameplay.timing")

  -- #543:item_get_reveal 图鉴放大卡私有展示链整条拆除,获得展示统一
  -- item_gain_popup;展示时长常量沿用原 3 秒口径不变。
  luassert.is.equal(nil, event_kinds.item_get_reveal, "retired item_get_reveal kind should stay removed")
  luassert.is.equal("item_gain_popup", event_kinds.item_gain_popup, "gain popup event kind should be stable")
  luassert.is.equal(3.0, timing.item_get_reveal_seconds, "item reveal duration should be fixed at 3s")
  end)

  it("test_retires_global_visibility_variants", function()
  local node_ops = require("src.ui.render.support.node_ops")

  -- #544:#512 时代的 set_visible_global/set_touch_enabled_global 广播 workaround
  -- 经真机原型实证过期(覆盖层节点住图鉴 canvas,per-role 可查、canvas 门控兜底),
  -- 全仓消费者清零后整条退役;重新引入即打破此钉(旁观者泄漏由广播变体造成)。
  luassert.is.equal(nil, node_ops.set_visible_global, "retired set_visible_global should stay removed")
  luassert.is.equal(nil, node_ops.set_touch_enabled_global, "retired set_touch_enabled_global should stay removed")
  end)

  it("test_splits_skin_and_item_atlas_schema", function()
  local skin_schema = require("src.ui.schema.skin")
  local item_atlas_schema = require("src.ui.schema.item_atlas")
  local market_schema = require("src.ui.schema.market")
  local market_layout = require("src.ui.schema.market_layout")

  luassert.is.equal(6, #skin_schema.action_buttons, "skin schema should expose six action buttons")
  luassert.is.equal(8, #item_atlas_schema.card_images, "item atlas schema should expose eight card images")
  luassert.is.equal("皮肤商店", skin_schema.canvas, "skin schema canvas should match exported node")
  luassert.is.equal("道具图鉴", item_atlas_schema.canvas, "item atlas canvas should match exported node")
  luassert.truthy(market_schema.tab_skin == nil, "market schema should not expose retired skin tab")
  luassert.truthy(market_layout.tab_skin == nil, "market layout should not expose retired skin tab")
  end)

  it("test_item_atlas_catalog_is_derived_from_items", function()
  local items = require("src.config.content.items")
  local item_atlas = require("src.config.content.item_atlas")

  luassert.is.equal(#items, #item_atlas, "atlas should mirror visible item catalog size")
  luassert.is.equal(items[1].id, item_atlas[1].id, "atlas should preserve item id")
  luassert.is.equal(items[1].description, item_atlas[1].description, "atlas should reuse item description")
  end)

  it("test_coordinators_keep_skin_and_atlas_state_separate", function()
  local skin_panel = require("src.ui.screens.skin_panel")
  local item_atlas = require("src.ui.screens.item_atlas")
  -- 装载时预绑已删(#262):catalog 字段由注入路径维护,读前先 reset。
  item_atlas.reset_for_tests()
  local state = { ui = {} }

  skin_panel.open(state, 1)
  skin_panel.handle_action(state, "buy", 1)
  skin_panel.handle_action(state, "equip", 1)
  item_atlas.open(state, 1)
  item_atlas.handle_action(state, { type = "select", slot_index = 2 }, 1)

  luassert.is.equal(false, state.ui.skin_panel.open, "skin panel should auto-close after owned equip (design 336)")
  luassert.is.equal(transaction.catalog[1].product_id, state.ui.skin_panel.selected_by_role["1"],
    "skin panel should keep selected skin by role")
  luassert.is.equal(true, state.ui.item_atlas.open, "item atlas should open independently")
  luassert.is.equal(item_atlas.catalog[2].id, state.ui.item_atlas.selected_item_id,
    "item atlas should select catalog items by slot")
  end)

  it("test_view_command_dispatches_v102_extension_intents", function()
  local view_command = require("src.ui.ports.view_command").build()
  local skin_panel = require("src.ui.screens.skin_panel")
  local state = { ui = {} }
  local equipped = nil

  skin_panel.reset_for_tests()
  skin_panel.configure_equip(function(role_id, skin)
    equipped = { role_id = role_id, skin = skin }
    return true
  end)

  luassert.truthy(view_command.dispatch(state, { type = "open_skin_panel", actor_role_id = 7 }) == true,
    "skin open intent should be handled")
  luassert.truthy(view_command.dispatch(state, { type = "skin_panel_action", action = { type = "buy", slot_index = 2 }, actor_role_id = 7 }) == true,
    "skin action intent should be handled")
  luassert.truthy(view_command.dispatch(state, { type = "skin_panel_action", action = { type = "equip", slot_index = 2 }, actor_role_id = 7 }) == true,
    "skin equip intent should be handled")
  luassert.truthy(view_command.dispatch(state, { type = "open_gallery_panel", actor_role_id = 7 }) == true,
    "gallery open intent should be handled")
  luassert.truthy(view_command.dispatch(state, { type = "item_atlas_action", action = { type = "select", slot_index = 1 }, actor_role_id = 7 }) == true,
    "atlas action intent should be handled")

  luassert.is.equal(true, state.ui.skin_panel.owned_by_role["7"][transaction.catalog[2].product_id],
    "skin action should update selected slot")
  luassert.is.equal(7, equipped and equipped.role_id, "skin equip callback should receive actor role")
  luassert.is.equal(transaction.catalog[2], equipped and equipped.skin, "skin equip callback should receive selected skin")
  luassert.is.equal(require("src.ui.screens.item_atlas").catalog[1].id, state.ui.item_atlas.selected_item_id,
    "atlas action should update item atlas")

  skin_panel.reset_for_tests()
  end)

  it("test_host_install_wires_skin_panel_to_skin_equip", function()
  local host_install = require("src.app.host_install")
  local skin_panel = require("src.ui.screens.skin_panel")
  local skin_equip = require("src.rules.cosmetics")
  local runtime_refs = require("src.config.content.runtime_refs")
  local captured = nil

  skin_panel.reset_for_tests()
  _with_patches({
    {
      target = skin_equip,
      key = "equip",
      value = function(role_id, creature_key)
        captured = { role_id = role_id, creature_key = creature_key }
        return true
      end,
    },
  }, function()
    host_install.install({ skip_context_install = true })
    local state = { ui = {} }
    skin_panel.open(state, 9)
    skin_panel.handle_action(state, { type = "buy", slot_index = 3 }, 9)
    skin_panel.handle_action(state, { type = "equip", slot_index = 3 }, 9)
  end)

  luassert.is.equal(9, captured and captured.role_id, "host install should pass role id to skin equip")
  luassert.is.equal(runtime_refs.skins[tostring(transaction.catalog[3].product_id)],
    captured and captured.creature_key,
    "host install should map selected skin to the numeric resource id from refs.skins")
  skin_panel.reset_for_tests()
  end)

  it("test_host_install_wires_purchase_skins_to_paid_goods", function()
  local host_install = require("src.app.host_install")
  local paid_purchase_port = require("src.rules.ports.paid_purchase")
  local skin_panel = require("src.ui.screens.skin_panel")
  local skin_equip = require("src.rules.cosmetics")
  local player = { id = 9, name = "玩家9" }
  local state = {
    ui = {},
    game = {
      find_player_by_id = function(_, role_id)
        return tostring(role_id) == "9" and player or nil
      end,
    },
  }
  local captured = nil

  skin_panel.reset_for_tests()
  _with_patches({
    {
      target = paid_purchase_port,
      key = "start",
      value = function(game, start_player, entry)
        captured = {
          game = game,
          player = start_player,
          entry = entry,
        }
        return true
      end,
    },
    {
      target = skin_equip,
      key = "equip",
      value = function()
        return true
      end,
    },
  }, function()
    host_install.install({ skip_context_install = true })
    skin_panel.open(state, 9)
    skin_panel.handle_action(state, { type = "equip", slot_index = 1 }, 9)
    luassert.truthy(captured ~= nil, "skin purchase should start paid purchase")
    captured.entry.on_purchase(state.game, player, captured.entry, {})
  end)

  local skin = transaction.catalog[1]
  luassert.is.equal(state.game, captured and captured.game, "skin purchase should use current game")
  luassert.is.equal(player, captured and captured.player, "skin purchase should resolve player by role id")
  luassert.is.equal(skin.product_id, captured and captured.entry.product_id,
    "skin purchase should pass selected skin product")
  luassert.is.equal("skin", captured and captured.entry.kind, "skin purchase entry should be tagged as skin")
  luassert.truthy(type(captured.entry.on_purchase) == "function", "skin purchase should carry fulfillment callback")
  luassert.is.equal(true, state.ui.skin_panel.owned_by_role["9"][skin.product_id],
    "paid skin callback should unlock skin")
  luassert.is.equal(skin.product_id, state.ui.skin_panel.selected_by_role["9"],
    "paid skin callback should equip skin")
  skin_panel.reset_for_tests()
  end)

  it("test_achievement_integration_is_implemented", function()
  local achievement = require("src.app.host_integrations.achievement")

  luassert.is.equal("function", type(achievement.record_gameplay_event), "achievement should expose gameplay event routing")
  luassert.is.equal("function", type(achievement.add_progress), "achievement should expose progress routing")
  luassert.is.equal("function", type(achievement.current_progress), "achievement should expose host progress reads")
  luassert.is.equal(1, achievement.mapped_ids_for_event("游戏胜利")[1], "win event should map to the win achievements")
  end)

  it("test_sign_in_integration_is_implemented", function()
  local sign_in = require("src.app.host_integrations.sign_in")

  luassert.truthy(sign_in.host_pending ~= true, "sign_in should no longer be a host-pending noop")
  luassert.is.equal("function", type(sign_in.grant), "sign_in should expose reward grant")
  luassert.is.equal(500, sign_in.amount_for_day(1), "sign_in day 1 should grant 500 coins")
  luassert.is.equal(10000, sign_in.amount_for_day(7), "sign_in day 7 should grant 10000 coins")
  luassert.is.equal(3, sign_in.day_from_event("RewardDay3"), "sign_in should map host event to day")
  end)

  it("test_leaderboard_integration_is_implemented", function()
  local leaderboard = require("src.app.host_integrations.leaderboard")

  luassert.truthy(leaderboard.host_pending ~= true, "leaderboard should no longer be a host-pending noop")
  luassert.is.equal("function", type(leaderboard.settle), "leaderboard should expose game-end settlement")
  luassert.is.equal(1001, leaderboard.win_count_archive_key, "leaderboard should target the win-count archive key")
  luassert.is.equal(1002, leaderboard.total_assets_archive_key, "leaderboard should target the total-assets archive key")
  end)

  it("test_skin_equip_contract_loads_without_ui_dependency", function()
  local skin_equip = require("src.rules.cosmetics")

  luassert.is.equal("function", type(skin_equip.equip), "skin equip should expose equip")
  luassert.is.equal("function", type(skin_equip.unequip), "skin equip should expose unequip")
  end)

  it("test_skin_equip_applies_creature_key_to_role_unit", function()
  local runtime_ports = require("src.foundation.ports.runtime_ports")
  local skin_equip = require("src.rules.cosmetics")
  local calls = {}

  _with_patches({
    {
      target = runtime_ports,
      key = "resolve_role",
      value = function(role_id)
        luassert.is.equal(11, role_id, "skin equip should resolve target role")
        return {
          get_ctrl_unit = function()
            return {
              set_model_by_creature_key = function(...)
                calls[#calls + 1] = { ... }
                return true
              end,
            }
          end,
        }
      end,
    },
  }, function()
    luassert.is.equal(true, skin_equip.equip(11, "skin_key"), "skin equip should report model change success")
  end)

  luassert.is.equal(1, #calls, "skin equip should call unit model setter")
  luassert.is.equal("skin_key", calls[1][1], "skin equip should pass creature key")
  end)
end)

