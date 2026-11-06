-- 选择屏触摸门禁规则,判定口径见 test/guards/lib/choice_touch_guard.lua。
--
-- exempt:节点确实不会吸触摸,理由写清是哪条路径保证的。
-- pending_device_check:9e9ae37 之后扫出的存量节点,代码里没人关触摸,是否压住按钮要
-- 真机确认。只许减不许增:新节点进 passthrough 或 exempt,不往这里塞。确认后要么进
-- passthrough(target / secondary_confirm 开屏不走 _option_screen,要先接上才生效),
-- 要么挪到 exempt 并写实测结论。

local _SLOT_REASON = "fill_option_nodes 的 _sync_option_slot 开屏时已关触摸,test_choice_openers 钉住"
local _UNCHECKED = "代码里没人关触摸,尚未真机确认是否压住按钮"

local function _target_slot_exemptions()
  local exempt = {}
  for index = 1, 7 do
    exempt["位置-槽位" .. index .. "文本"] = _SLOT_REASON
    exempt["位置-槽位" .. index .. "投影"] = _SLOT_REASON
  end
  return exempt
end

return {
  screens = {
    remote = { prefixes = { "遥控骰子_" }, exempt = {}, pending_device_check = {} },
    player = {
      prefixes = { "玩家选择_" },
      exempt = {},
      pending_device_check = {
        ["玩家选择_标题"] = _UNCHECKED,
      },
    },
    target = {
      prefixes = { "位置_", "位置-" },
      exempt = _target_slot_exemptions(),
      pending_device_check = {
        ["位置_副标题"] = _UNCHECKED,
        ["位置_放置文本"] = _UNCHECKED,
      },
    },
    secondary_confirm = {
      prefixes = { "通用二次确认_" },
      exempt = {},
      pending_device_check = {
        ["通用二次确认_标题"] = _UNCHECKED,
        ["通用二次确认_文本"] = _UNCHECKED,
        ["通用二次确认_标题背景"] = _UNCHECKED,
        ["通用二次确认_弹窗背景"] = _UNCHECKED,
        ["通用二次确认_灰底"] = "schema 未声明 underlay," .. _UNCHECKED .. ";它可能是有意挡住下层的模态遮罩",
      },
    },
  },
}
