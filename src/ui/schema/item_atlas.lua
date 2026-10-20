local nodes = {
  page_size = 8,
  canvas = "道具图鉴",
  close_button = "图鉴_关闭图鉴",
  close_blank = "图鉴_点击空白关闭",
  page_prev = "图鉴_上一页",
  page_next = "图鉴_下一页",
  close_hint_label = "图鉴_点击关闭提示",
  enlarged_card = "图鉴_放大卡牌",
  -- #178 点背景关闭:等同 close_button;放大态下关闭触摸,由 close_blank 先收起放大卡。
  background = "图鉴-背景",
  -- 叠在背景/关闭按钮上的纯展示文字,运行时关闭触摸让点击穿透。
  passthrough_nodes = {
    "图鉴_关闭图鉴文本",
    "图鉴_关闭图鉴文本提示",
  },
  card_images = {},
}

for i = 1, nodes.page_size do
  nodes.card_images[i] = "图鉴_卡牌" .. tostring(i)
end

return nodes

