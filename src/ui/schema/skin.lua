local nodes = {
  page_size = 6,
  canvas = "皮肤商店",
  close_button = "皮肤商店-关闭",
  activity_background = "皮肤商店-活动背景",
  title_label = "皮肤_皮肤商店文本",
  panel_frames = {
    "皮肤_皮肤商店底框",
    "皮肤_皮肤商店底框2",
  },
  card_images = {},
  card_frames = {},
  card_outlines = {},
  price_icons = {},
  action_buttons = {},
}

-- activity_background 不在此表:#178 点背景关闭要求它可点,由渲染单独开触摸。
nodes.static_visual_nodes = {
  nodes.title_label,
  nodes.panel_frames[1],
  nodes.panel_frames[2],
}

-- #178:叠在背景/关闭按钮上的纯展示文字,运行时关闭触摸让点击穿透。
nodes.passthrough_nodes = {
  "皮肤_关闭皮肤文本",
  "皮肤_关闭皮肤文本提示",
}

for i = 1, nodes.page_size do
  local idx = tostring(i)
  nodes.card_images[i] = "皮肤_卡牌" .. idx
  nodes.card_frames[i] = "皮肤_卡牌底框" .. idx
  nodes.card_outlines[i] = "皮肤_卡牌底框描边" .. idx
  nodes.price_icons[i] = "皮肤_卡牌金额图标" .. idx
  nodes.action_buttons[i] = "皮肤_穿上按钮" .. idx
end

return nodes

