local nodes = {
  canvas = "基础屏",
  action_button = "基础_行动按钮",
  end_button = "基础_结束按钮",
  cancel_button = "基础_取消按钮",
  countdown = "基础_倒计时",
  countdown_line = "基础_倒计时横线",
  action_hint = "基础_行动提示",
  action_hint_effect = "基础_行动提示特效",
  other_player_hint = "基础_其他玩家行动提示",
  player_name = "基础_玩家%s名字",
  player_cash = "基础_玩家%s现金",
  player_cash_delta = "基础-玩家%s消耗金币显示",
  player_land_count = "基础_玩家%s地块数量",
  player_total_assets = "基础_玩家%s总资产",
  player_crown = "基础_玩家%s皇冠",
  player_avatar = "基础_玩家%s头像",
  player_color = "基础_玩家%s底板颜色",
  auto_button = "基础_托管按钮",
  auto_effect = "基础_托管按钮特效",
  auto_label = "基础_托管文本",
  action_log_button = "基础_行动日志图标",
  skin_button = "基础_皮肤图标",
  skin_label = "基础_皮肤文本",
  skin_effect_nodes = {
    "基础_皮肤动效1",
    "基础_皮肤动效2",
  },
  gallery_button = "基础_图鉴图标",
  share_button = "基础_分享图标",
  -- 礼包码屏入口(#199);其文本/图标/环/动效装饰节点不加逻辑。
  gift_code_button = "基础_礼包码",
  -- 入口关闭(gift_codes.entry_enabled = false)时与按钮一并压灭;「基础_礼包码动效」
  -- 同名两个,走全量命中。
  gift_code_decor_nodes = {
    "基础_礼包码文本",
    "基础_礼包码图标",
    "基础_礼包码环",
    "基础_礼包码环_1",
    "基础_礼包码动效",
  },
  -- 分享按钮的装饰子节点（Eggy 覆盖节点默认吸触摸，先例 auto_effect/skin_label）：
  -- 运行时统一压触摸，否则子节点盖住按钮吞掉点击。「基础_分享动效」同名两个，
  -- 必须走 set_touch_enabled_all 全量命中。
  share_decor_nodes = {
    "基础_分享环",
    "基础_分享动效",
    "基础_分享文本",
  },
  player_action_effects = {
    "基础_玩家1行动动效", "基础_玩家2行动动效",
    "基础_玩家3行动动效", "基础_玩家4行动动效",
  },
}

return nodes

