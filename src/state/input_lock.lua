-- 锁输入回合相位集合的唯一真源(#211 / #206 C):纯局面谓词,无宿主、无 turn/ui
-- 依赖。回合推进(turn)与选择门控/开屏判定(ui)都向内依赖本模块读同一份集合。
local input_lock = {}

local _INPUT_BLOCKED_PHASES = {
  wait_move_anim = true,
  wait_action_anim = true,
  wait_landing_visual = true,
  detained_wait = true,
  inter_turn_wait = true,
}

function input_lock.is_phase_input_blocked(phase)
  return _INPUT_BLOCKED_PHASES[phase] == true
end

-- 从 game 取当前回合相位判输入锁;缺 game/turn 视作不锁。
function input_lock.is_game_input_blocked(game)
  local phase = game and game.turn and game.turn.phase or nil
  return input_lock.is_phase_input_blocked(phase)
end

return input_lock
