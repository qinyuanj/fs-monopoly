local path_planner = require("src.computer.agent.path")
local action_selector = require("src.computer.agent.action")
local decision_engine = require("src.computer.agent.decision")

local agent = {}

agent.pick_remote_dice_value = path_planner.pick_remote_dice_value
agent.pick_target_player = action_selector.pick_target_player
agent.pick_roadblock_target = action_selector.pick_roadblock_target
agent.pick_demolish_target = action_selector.pick_demolish_target
agent.auto_action_for_choice = decision_engine.build(agent)

return agent

