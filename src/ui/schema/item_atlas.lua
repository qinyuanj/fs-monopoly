local nodes = {
  page_size = 8,
  canvas = "道具图鉴",
  close_button = "图鉴_关闭图鉴",
  close_blank = "图鉴_点击空白关闭",
  page_prev = "图鉴_上一页",
  page_next = "图鉴_下一页",
  close_hint_label = "图鉴_点击关闭提示",
  enlarged_card = "图鉴_放大卡牌",
  card_images = {},
}

for i = 1, nodes.page_size do
  nodes.card_images[i] = "图鉴_卡牌" .. tostring(i)
end

return nodes

