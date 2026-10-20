local market_layout = {
  container = "黑市屏",
  confirm_button = "黑市_购买按钮",
  cancel_button = "黑市_关闭",
  cancel_button_alt = "黑市_取消按钮",
  page_prev = "黑市-上一页箭头",
  page_next = "黑市-下一页箭头",
  page_prev_label = "黑市-上一页按钮",
  page_next_label = "黑市-下一页按钮",
  page_prev_text = "上一页",
  page_next_text = "下一页",
  tab_item = "黑市-道具商店按钮",
  tab_item_gray = "黑市-道具商店灰底",
  tab_item_gray_label = "黑市-道具商店灰底文本",
  price_label = "黑市_售价",
  selected_card = "黑市_选中卡牌",
  cash_amount_label = "黑市_现金数额",
  cash_text_label = "黑市_现金文本",
  cash_icon = "黑市_现金图标",
  cash_background = "黑市_现金显示底框",
  cash_shadow = "黑市_现金显示底框投影",
  countdown = "黑市_倒计时",
  countdown_line = "黑市_倒计时横线",
  -- #178 点背景关闭:背景随黑市开关切换触摸;叠在背景/关闭按钮上的
  -- 纯展示节点一律关闭触摸,点击落到下方背景或按钮。
  background = "黑市_背景矩形",
  passthrough_nodes = {
    "黑市_关闭黑市文本",
    "黑市_关闭黑市文本提示",
    "黑市_关闭黑市按钮底图",
  },
  item_buttons = {},
  item_labels = {},
  item_frames = {},
  item_selection_frames = {},
  sold_out_badges = {},
  sold_out_labels = {},
  empty_ref_key = "Empty",
}

market_layout.cancel_buttons = {
  market_layout.cancel_button,
  market_layout.cancel_button_alt,
}

for i = 1, 10 do
  local idx = tostring(i)
  market_layout.item_buttons[i] = "黑市_购买项" .. idx
  market_layout.item_labels[i] = "黑市_道具名称" .. idx
  market_layout.item_frames[i] = "黑市_底框" .. idx
  market_layout.item_selection_frames[i] = "黑市-选中边框" .. idx
  market_layout.sold_out_badges[i] = "黑市-售罄" .. idx
  market_layout.sold_out_labels[i] = "黑市-售罄" .. idx .. "文本"
end

return market_layout

