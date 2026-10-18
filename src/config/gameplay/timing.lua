-- Coupling invariants:
--   auto_decision_delay_seconds < scope_timeouts.choice  (AI 自动确认必须能赶上 timeout)
--   deadline_warning_thresholds 必须降序：[1] > [2] > 0
--   现金浮字总窗口 = panel_cash_delta_show_delay_seconds + panel_cash_delta_visible_seconds (加性)
--   pass_start_hold_seconds_per_step 必须与 ui walk_speed × tile_length 节奏对齐
local timing = {
  auto_decision_delay_seconds = 2.0,
  popup_auto_close_seconds = 2.0,
  popup_dwell_default_seconds = 1.0,
  action_anim_default_seconds = 1.0,
  remote_dice_wait_seconds = 1.5,
  event_tip_default_seconds = 2.0,
  event_tip_fast_seconds = 0.5,
  event_tip_fast_backlog_threshold = 3,
  detained_turn_wait_seconds = 1.0,
  inter_turn_wait_seconds = 0.5,
  panel_cash_delta_visible_seconds = 2.0,
  panel_cash_delta_show_delay_seconds = 0.0,
  landing_visual_hold_seconds = 0.2,
  item_get_reveal_seconds = 3.0,
  demolish_effect_start_delay_seconds = 0.2,
  demolish_effect_followup_delay_seconds = 0.35,
  dice_spin_seconds = 1.0,
  dice_face_hold_seconds = 1.0,
  loading_to_game_transition_seconds = 1.0,
  move_anim_tail_padding_seconds = 0.5,
  pass_start_hold_seconds_per_step = 0.54,
  pass_start_hold_max_seconds = 6.0,
  pass_start_hold_tail_seconds = 0.4,
  roadblock_destroy_hold_seconds = 0.5,
  teleport_effect_camera_hold_seconds = 1.0,
  -- 倒计时由宿主侧展示,此值单方面对齐宿主配置;改宿主时长需同步改这里
  game_time_limit_seconds = 3000,
  turn_limit = 1000,
  item_phase_queue = { "pre_action", "pre_move", "post_action" },
  afk = {
    -- Two consecutive input-window fallbacks avoid classifying one missed click as AFK.
    consecutive_timeout_count = 2,
  },
  scope_timeouts = {
    choice          = 15,
    market_buy      = 60,
    target_select   = 15,
  },
  deadline_warning_thresholds = { 5, 3 },
}

return timing

