-- 道具槽点击路由：只报事实——谁点了第几个槽——不做任何「在不在道具阶段」的判断。
-- 裁定与用户反馈全部归 turn 层（src.turn.actions.item_slot_click）。
-- 这里唯一保留的本地门是遮挡：弹层盖住时点击属于误触，静默；这是纯展示语义，
-- turn 层看不见谁的屏幕上有弹层。
local nodes = require("src.ui.schema.permanent")
local slot_overlay = require("src.ui.input.item_slot_overlay")
local local_actor_resolver = require("src.ui.seams.local_actor_resolver")

local intents = {}

local function _slot_intent_builder(state, index)
  return function(data)
    local actor_role_id = local_actor_resolver.resolve_from_event(state, data)
    if slot_overlay.blocks_click(state, actor_role_id) then
      return nil
    end
    return { type = "item_slot_click", slot_index = index, actor_role_id = actor_role_id }
  end
end

local function _screen_nodes(state, field, fallback)
  return (state.ui and state.ui[field]) or fallback or {}
end

function intents.build(state)
  local specs = {}
  local item_slots = _screen_nodes(state, "item_slots", nodes.item_slots)
  for index, node_name in ipairs(item_slots) do
    specs[#specs + 1] = { name = node_name, build_intent = _slot_intent_builder(state, index) }
  end
  return specs
end

return intents

