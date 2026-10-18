-- Static routing table for view/game commands (non-button intents) consumed
-- by command_definitions. Split out of command_definitions.lua to keep each
-- data module under the mutation-site split threshold.

local COMMANDS = {
  -- 道具槽点击：行动者就是点击者（actor_source = "local"，与实现一致；早先它挂在
  -- ui_button 上写 actor_source = "turn"，而解析器实际返回点击者，命名撒谎导致
  -- 他人回合的点击被回合绑定校验静默拒掉）。裁定归 turn，UI 侧不做阶段判断。
  item_slot_click = {
    reason = "item_slot",
    game_handler = "basic",
    requires_event_actor = true,
    actor_source = "local",
    item_slot = true,
  },
  toggle_action_log = {
    reason = "toggle_action_log",
    dispatch_before_game = true,
    panel_id = "action_log",
    requires_event_actor = true,
    actor_source = "local",
    port_handler = "toggle_action_log",
  },
  open_skin_panel = {
    reason = "open_skin_panel",
    dispatch_before_game = true,
    panel_id = "skin",
    requires_event_actor = true,
    actor_source = "local",
    optional_event_actor = true,
    port_handler = "open_skin_panel",
  },
  open_gallery_panel = {
    reason = "open_gallery_panel",
    dispatch_before_game = true,
    panel_id = "gallery",
    requires_event_actor = true,
    actor_source = "local",
    optional_event_actor = true,
    port_handler = "open_gallery_panel",
  },
  -- 分享按钮：唤起宿主分享面板（与回合、面板态全部无关），actor 取本机角色。
  -- 不开 panel_id——宿主面板在 Lua 面板体系之外，不参与面板中断/回屏。
  open_share_panel = {
    reason = "open_share_panel",
    dispatch_before_game = true,
    requires_event_actor = true,
    actor_source = "local",
    port_handler = "open_share_panel",
  },
  skin_panel_action = {
    reason = "skin_panel_action",
    dispatch_before_game = true,
    requires_event_actor = true,
    actor_source = "local",
    port_handler = "skin_panel_action",
  },
  item_atlas_action = {
    reason = "item_atlas_action",
    dispatch_before_game = true,
    requires_event_actor = true,
    actor_source = "local",
    port_handler = "item_atlas_action",
  },
  skin_gallery_action = {
    reason = "skin_gallery_action",
    dispatch_before_game = true,
    requires_event_actor = true,
    actor_source = "local",
    port_handler = "skin_gallery_action",
  },
  market_select = {
    reason = "market_select",
    port_handler = "market_select",
  },
  popup_confirm = {
    reason = "popup_confirm",
    -- 广播弹窗按点击者判关闭权,必须带上事件里的操作者;缺 role 上下文时
    -- 不拒绝(optional),非广播弹窗维持谁点谁关。
    requires_event_actor = true,
    actor_source = "local",
    optional_event_actor = true,
    port_handler = "popup_confirm",
  },
  choice_select = {
    reason = "choice_select",
    game_handler = "basic",
    requires_event_actor = true,
    actor_source = "turn",
  },
  choice_cancel = {
    reason = "choice_cancel",
    game_handler = "basic",
    requires_event_actor = true,
    actor_source = "turn",
  },
  complete_optional_action_phase = {
    reason = "complete_optional_action_phase",
    game_handler = "basic",
    requires_event_actor = true,
    actor_source = "turn",
  },
  market_confirm = {
    reason = "market_confirm",
    game_handler = "market_confirm",
    requires_event_actor = true,
    actor_source = "turn",
  },
  market_page_prev = {
    reason = "market_page_prev",
    game_handler = "market_page_prev",
    requires_event_actor = true,
    actor_source = "turn",
  },
  market_page_next = {
    reason = "market_page_next",
    game_handler = "market_page_next",
    requires_event_actor = true,
    actor_source = "turn",
  },
  market_tab_select = {
    reason = "market_tab_select",
    game_handler = "market_tab_select",
    requires_event_actor = true,
    actor_source = "turn",
  },
}

return COMMANDS

--[[ mutate4lua-manifest
version=4
projectHash=ded095e5534d01e7
scope.0.id=chunk:src/ui/input/command_definitions_commands.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=139
scope.0.semanticHash=4a24abe09e8545ef
]]
