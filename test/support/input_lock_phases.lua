-- #211(#206 C)规格样例:锁输入 / 放行的回合相位字面清单,供 state 直测与 ui_sync
-- 模型/选择态测试共用。期望值按规格逐项列出,不从 src.state.input_lock 读回。
return {
  locked = {
    "wait_move_anim",
    "wait_action_anim",
    "wait_landing_visual",
    "detained_wait",
    "inter_turn_wait",
  },
  unlocked = {
    "start",
    "pre_action",
    "pre_move",
    "wait_action",
    "wait_choice",
    "post_action",
  },
}
