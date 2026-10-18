local Class = require("src.foundation.class")
local control = require("src.player.control")
local player = Class("Player")

function player:init(attrs)
  assert(attrs ~= nil, "Player.new(attrs) requires attrs")
  local constants = attrs.constants
  assert(constants ~= nil, "Player.new(attrs) requires attrs.constants")

  self.id = attrs.id
  assert(attrs.name ~= nil, "Player.new(attrs) requires attrs.name")
  self.name = attrs.name
  self.role_id = attrs.role_id
  self.is_ai = attrs.is_ai
  control.initialize(self)
  -- 与托管状态同口径从 attrs 恢复：回放/断线重连/读档重建 player 时
  -- 不把「已弹过分享面板」静默重置回 false。
  self.auto_share_panel_shown = attrs.auto_share_panel_shown == true
  self._coin_role = attrs.coin_role
  self.position = attrs.start_index
  self.deity_duration_turns = attrs.deity_duration_turns
  self.status = {
    stay_turns = 0,
    own_turn_started_count = 0,
    deity = { type = "", remaining = 0 },
    pending_remote_dice = nil,
    pending_dice_multiplier = 1,
    pending_free_rent = false,
    pending_tax_free = false,
  }
  self.inventory = attrs.inventory
  self.properties = {}
  self.eliminated = false
end

return player

