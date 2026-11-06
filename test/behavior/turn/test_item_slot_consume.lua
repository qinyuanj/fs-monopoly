-- #230：点第 N 个槽位用卡，扣掉的就是第 N 个槽位的卡，其余卡位置不变。
-- 全程走真实派发：item_slot_click → 裁定 → choice_select → 道具结算 → 背包。
-- luacheck: std +busted
require("test.bootstrap").install_package_paths()
local luassert = assert
local support = require("test.support.shared_support")
local fixtures = require("test.support.gameplay_fixtures")
local action_dispatcher = require("src.turn.actions.action_dispatcher")
local item_ids = require("src.config.gameplay.item_ids")
local config_reset = require("test.support.config_reset")
local runtime_state = require("src.state.runtime")
local settlement = require("src.rules.items.settlement")
local use_flow = require("src.rules.items.use_flow")
local DeadlineService = require("src.turn.deadlines")

local EMPTY = false

local function _slots(player, count)
  local out = {}
  for index = 1, count do
    local item = player.inventory.items[index]
    out[index] = item and item.id or EMPTY
  end
  return out
end

-- 按字面槽位摆卡：先占满再挖洞，得到与真机一致的固定槽位布局。
local function _fill_bag(player, layout)
  player.inventory:clear()
  for index, item_id in ipairs(layout) do
    player.inventory.items[index] = item_id and { id = item_id } or false
  end
end

local function _open_window(layout, victim_layout, prepare)
  local game = support.new_game()
  local player = game:current_player()
  _fill_bag(player, layout)
  _fill_bag(game.players[2], victim_layout or {})
  if prepare then
    prepare(game)
  end
  game:advance_turn()
  local window = assert(game.turn.pending_choice, "item window should open")
  luassert.is.equal("item_phase_passive", window.kind)
  return game, player, fixtures.build_loop_state()
end

local function _enemy_building(game)
  local tile = game.board:get_tile(3)
  game:set_tile_owner(tile, game.players[2].id)
  game:set_tile_level(tile, 1)
end

local function _click_slot(game, state, player, slot_index)
  return action_dispatcher.dispatch_action(game, state, {
    type = "item_slot_click",
    slot_index = slot_index,
    actor_role_id = player.id,
  })
end

local function _select_first_option(game, state, player)
  local followup = assert(game.turn.pending_choice, "followup choice should open")
  luassert.is_not.equal("item_phase_passive", followup.kind)
  local option = followup.options[1]
  return action_dispatcher.dispatch_action(game, state, {
    type = "choice_select",
    choice_id = followup.id,
    option_id = type(option) == "table" and option.id or option,
    actor_role_id = player.id,
  })
end

-- 点槽位开出 followup 后，经真实写入口把卡转入托管（生产暂无调用者，见 settlement.escrow）。
local function _escrow_clicked_card(game, state, player, slot_index, item_id)
  _click_slot(game, state, player, slot_index)
  local followup = assert(game.turn.pending_choice, "followup choice should open")
  settlement.escrow(player, item_id, followup)
  return followup
end

local function _force_skip(game, followup)
  followup.options = {}
  DeadlineService.force_skip(game, runtime_state.ensure_all({}), followup, "tick_timeout")
end

describe("TestItemSlotConsume", function()

before_each(function()
  config_reset.reset_all()
end)

it("test_同种卡点第二张_扣第二张_第一张不动", function()
  local mine, angel = item_ids.mine, item_ids.angel
  local game, player, state = _open_window({ mine, angel, mine })

  _click_slot(game, state, player, 3)

  luassert.is.same({ mine, angel, EMPTY }, _slots(player, 3))
end)

it("test_不同种卡混放_点哪张扣哪张", function()
  local mine, angel, rich = item_ids.mine, item_ids.angel, item_ids.rich
  local game, player, state = _open_window({ mine, angel, rich })

  _click_slot(game, state, player, 2)

  luassert.is.same({ mine, EMPTY, rich }, _slots(player, 3))
end)

it("test_选目标后才扣的卡_扣被点击的槽位", function()
  local tax, mine = item_ids.tax, item_ids.mine
  local game, player, state = _open_window({ tax, mine, tax })

  _click_slot(game, state, player, 3)
  luassert.is.same({ tax, mine, tax }, _slots(player, 3))
  _select_first_option(game, state, player)

  luassert.is.same({ tax, mine, EMPTY }, _slots(player, 3))
end)

it("test_选目标时自耗的偷窃卡_扣被点击的槽位", function()
  local steal, angel = item_ids.steal, item_ids.angel
  local game, player, state = _open_window({ steal, angel, steal }, { item_ids.mine })

  _click_slot(game, state, player, 3)
  _select_first_option(game, state, player)

  luassert.is.same({ steal, angel, item_ids.mine }, _slots(player, 3))
end)

it("test_选点数后才扣的遥控骰子_扣被点击的槽位", function()
  local remote_dice, mine = item_ids.remote_dice, item_ids.mine
  local game, player, state = _open_window({ remote_dice, mine, remote_dice })

  _click_slot(game, state, player, 3)
  _select_first_option(game, state, player)

  luassert.is.same({ remote_dice, mine, EMPTY }, _slots(player, 3))
end)

for _, case in ipairs({
  { name = "路障卡", item = "roadblock" },
  { name = "怪兽卡", item = "monster", prepare = _enemy_building },
  { name = "导弹卡", item = "missile" },
}) do
  it("test_选目标后才扣的" .. case.name .. "_扣被点击的槽位", function()
    local item_id, angel = item_ids[case.item], item_ids.angel
    local game, player, state = _open_window({ item_id, angel, item_id }, nil, case.prepare)

    _click_slot(game, state, player, 3)
    _select_first_option(game, state, player)

    luassert.is.same({ item_id, angel, EMPTY }, _slots(player, 3))
  end)
end

it("test_取消选目标_卡留在原位_再点另一张同种卡扣那一张", function()
  local tax, mine = item_ids.tax, item_ids.mine
  local game, player, state = _open_window({ tax, mine, tax })

  _click_slot(game, state, player, 3)
  local followup = assert(game.turn.pending_choice, "followup choice should open")
  action_dispatcher.dispatch_action(game, state, {
    type = "choice_cancel",
    choice_id = followup.id,
    actor_role_id = player.id,
  })
  luassert.is.same({ tax, mine, tax }, _slots(player, 3))

  _click_slot(game, state, player, 1)
  _select_first_option(game, state, player)

  luassert.is.same({ EMPTY, mine, tax }, _slots(player, 3))
end)

it("test_预扣托管扣被点击的槽位_原槽位空着时退回原位", function()
  local steal, angel = item_ids.steal, item_ids.angel
  local game, player, state = _open_window({ EMPTY, steal, angel, steal }, { item_ids.mine })

  local followup = _escrow_clicked_card(game, state, player, 4, steal)
  luassert.is.same({ EMPTY, steal, angel, EMPTY }, _slots(player, 4))

  _force_skip(game, followup)

  luassert.is.same({ EMPTY, steal, angel, steal }, _slots(player, 4))
end)

it("test_预扣托管退还时原槽位已被占用_落最小空洞", function()
  local steal, angel, mine = item_ids.steal, item_ids.angel, item_ids.mine
  local game, player, state = _open_window({ EMPTY, angel, steal }, { mine })

  local followup = _escrow_clicked_card(game, state, player, 3, steal)
  player.inventory.items[3] = { id = mine }

  _force_skip(game, followup)

  luassert.is.same({ steal, angel, mine }, _slots(player, 3))
end)

it("test_无点击槽位的预扣托管_记住第一张匹配卡的槽位", function()
  local steal, angel = item_ids.steal, item_ids.angel
  local game, player = _open_window({ EMPTY, steal, angel }, { item_ids.mine })
  local result = use_flow.begin_item_use(game, player.id, steal, {})
  local followup = support.open_choice(game, settlement.escrow(player, steal, result.intent.choice_spec))
  luassert.is.same({ EMPTY, EMPTY, angel }, _slots(player, 3))

  _force_skip(game, followup)

  luassert.is.same({ EMPTY, steal, angel }, _slots(player, 3))
end)

it("test_无槽位的选择动作_仍按_id_扣第一张", function()
  local mine, angel = item_ids.mine, item_ids.angel
  local game, player, state = _open_window({ mine, angel, mine })
  local window = game.turn.pending_choice

  action_dispatcher.dispatch_action(game, state, {
    type = "choice_select",
    choice_id = window.id,
    option_id = mine,
    actor_role_id = player.id,
  })

  luassert.is.same({ EMPTY, angel, mine }, _slots(player, 3))
end)

it("test_无槽位的自动出牌_仍按_id_扣第一张", function()
  local tax, mine = item_ids.tax, item_ids.mine
  local game, player = _open_window({ tax, mine, tax })

  use_flow.begin_item_use(game, player.id, tax, { is_computer_controlled = true })

  luassert.is.same({ EMPTY, mine, tax }, _slots(player, 3))
end)

-- 窗口开着时切自动托管再点卡：手点的槽位走自动选目标分支，扣卡口径不变。
for _, case in ipairs({
  { name = "目标玩家卡", item = "tax" },
  { name = "遥控骰子", item = "remote_dice" },
  { name = "路障卡", item = "roadblock" },
}) do
  it("test_自动托管中点槽位_" .. case.name .. "_扣被点击的槽位", function()
    local item_id, mine = item_ids[case.item], item_ids.mine
    local game, player = _open_window({ item_id, mine, item_id })

    use_flow.begin_item_use(game, player.id, item_id, { is_computer_controlled = true, slot_index = 3 })

    luassert.is.same({ item_id, mine, EMPTY }, _slots(player, 3))
  end)
end

it("test_自动托管中点槽位_拆除卡_扣被点击的槽位", function()
  local monster, mine = item_ids.monster, item_ids.mine
  local game, player = _open_window({ monster, mine, monster }, nil, _enemy_building)

  use_flow.begin_item_use(game, player.id, monster, { is_computer_controlled = true, slot_index = 3 })

  luassert.is.same({ monster, mine, EMPTY }, _slots(player, 3))
end)

it("test_槽位与道具不符时报错_不改扣别的卡", function()
  local mine, angel = item_ids.mine, item_ids.angel
  local game, player = _open_window({ mine, angel, mine })

  luassert.has_error(function()
    use_flow.begin_item_use(game, player.id, mine, { slot_index = 2 })
  end)

  luassert.is.same({ mine, angel, mine }, _slots(player, 3))
end)

end)
