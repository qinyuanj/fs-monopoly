-- luacheck: ignore 143
require("test.bootstrap").install_package_paths()
local luassert = assert
-- Pins the roadblock-stop main-button timeline (acceptance main_turn_buttons_015).
--
-- A roadblock stops the mover mid-move, plays a trigger animation, and then opens
-- whatever forced landing choice the tile demands (买地 / 加盖). Across that whole
-- stretch the base screen must keep 行动 / 结束 / 取消 down, and 结束 may only come
-- back once the last forced landing choice is resolvable.
--
-- The two halves are pinned separately elsewhere: `panel_action_controls` owns the
-- choice -> button decision table, `panel_controls` owns the base-visible gate.
-- What is new here is the composition over the *real* roadblock animation data:
-- the hit queues a `roadblock_trigger` action anim, that anim runs in a phase the
-- UI treats as input-blocked, and an input-blocked base screen shows no buttons.

local function _assert_eq(actual, expected, message)
  luassert.is.equal(expected, actual, message)
end
local compose_game = require("src.app.compose_game")
local default_ports = require("src.turn.output.default_ports")
local movement_events = require("src.rules.movement_events")
local input_lock = require("src.state.input_lock")
local panel_controls = require("src.ui.render.widgets.panel_controls")
local base_nodes = require("src.ui.schema.base")
local map_cfg = require("src.config.content.default_map")
local tiles_cfg = require("src.config.content.tiles")

-- An animated host: the Eggy runtime builds this gate from its own wait flags, and
-- only an enabled gate lets the rules queue an action anim at all.
local function _new_animated_game()
  local game = compose_game.new_game(default_ports.resolve_game_opts({
    players = { "P1", "P2" },
    ai = {},
    auto_all = false,
    map = map_cfg,
    tiles = tiles_cfg,
  }))
  game.anim_gate_port = { wait_move_anim = true, wait_action_anim = true }
  return game
end

-- Renders the three base buttons for one moment of the timeline and reports which
-- ones are live as an "action/end/cancel" signature. `ui` carries the gate flags
-- the real render state carries (input_blocked / popup_active).
local function _buttons(ui_flags, choice)
  local visible, touch = {}, {}
  local ui = {
    input_blocked = ui_flags.input_blocked == true,
    popup_active = ui_flags.popup_active == true,
    set_visible = function(_, name, value) visible[name] = value end,
    set_touch_enabled = function(_, name, value) touch[name] = value end,
  }
  local ctx = { can_operate = true, is_player_role = true, role_id = 1, display_player_id = 1 }
  local base_visible = panel_controls.is_base_non_player_visible(ui, ctx)
  panel_controls.apply_base_action_controls(ui, { choice = choice }, base_visible)

  local names = { action = base_nodes.action_button, ["end"] = base_nodes.end_button, cancel = base_nodes.cancel_button }
  local shown = {}
  for _, key in ipairs({ "action", "end", "cancel" }) do
    local name = names[key]
    _assert_eq(touch[name], visible[name], key .. " 按钮显隐与可点必须一致")
    shown[#shown + 1] = visible[name] and key or "-"
  end
  return table.concat(shown, "/")
end

-- The forced landing choice the roadblock stop drops the player into: a cancelable
-- landing optional effect, which is what 买地 / 加盖 resolve through.
local function _landing_choice()
  return { id = 9001, kind = "landing_optional_effect", allow_cancel = true, owner_role_id = 1,
    route_key = "base_inline", meta = { optional_action = "落地选择" } }
end

describe("TestMainTurnRoadblockButton", function()

it("test_a_roadblock_hit_queues_a_roadblock_trigger_action_anim", function()
  local game = _new_animated_game()
  local player = game:current_player()

  movement_events.emit_roadblock_hit(game, player, 7, { name = "测试地块" })

  local anim = game.turn.action_anim
  luassert.truthy(anim ~= nil, "路障截停应排入一条行动动画")
  _assert_eq(anim.kind, "roadblock_trigger", "路障截停动画类型")
  _assert_eq(anim.player_id, player.id, "路障截停动画归属玩家")
  _assert_eq(anim.tile_index, 7, "路障截停动画落点")
end)

it("test_the_action_anim_phase_is_an_input_blocked_phase", function()
  _assert_eq(input_lock.is_phase_input_blocked("wait_action_anim"), true,
    "路障触发动画播放期间输入应被锁住(输入锁相位集真源在 state.input_lock)")
end)

it("test_hides_all_three_buttons_while_the_roadblock_trigger_animation_plays", function()
  -- Input-blocked outranks the pending landing choice: no button is offered
  -- while the trigger animation is still on screen.
  _assert_eq(_buttons({ input_blocked = true }, _landing_choice()), "-/-/-",
    "路障触发动画期间三个主按钮都不出")
end)

it("test_hides_all_three_buttons_while_the_landing_choice_popup_is_up", function()
  -- 买地 / 加盖 弹窗 raises popup_active, which reads as a settlement overlay.
  _assert_eq(_buttons({ popup_active = true }, _landing_choice()), "-/-/-",
    "落地选择弹窗期间三个主按钮都不出")
end)

it("test_brings_结束_back_once_the_forced_landing_choices_are_resolved", function()
  -- Animation done, popup closed, the landing optional action left to close out.
  _assert_eq(_buttons({}, _landing_choice()), "-/end/-",
    "落地选择处理完毕后由结束按钮收尾")
end)


end)
