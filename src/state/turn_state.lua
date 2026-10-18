local dirty_tracker = require("src.state.dirty_tracker")

local game_state_turn = {}

function game_state_turn.queue_action_anim(self, payload)
  assert(payload ~= nil, "missing action anim payload")
  local seq = (self.turn.action_anim_seq or 0) + 1
  payload.seq = seq
  self.turn.action_anim_seq = seq
  local queue = self.turn.action_anim_queue
  if type(queue) ~= "table" then
    queue = {}
    self.turn.action_anim_queue = queue
  end
  queue[#queue + 1] = payload
  if not self.turn.action_anim then
    self.turn.action_anim = table.remove(queue, 1)
  end
  dirty_tracker.mark(self.dirty, "turn")
  return payload
end

function game_state_turn.queue_move_anim(self, payload)
  assert(payload ~= nil, "missing move anim payload")
  local seq = (self.turn.move_anim_seq or 0) + 1
  payload.seq = seq
  self.turn.move_anim_seq = seq
  self.turn.move_anim = payload
  dirty_tracker.mark(self.dirty, "turn")
  return payload
end

function game_state_turn.pending_choice(self)
  return self.turn.pending_choice
end

return game_state_turn

