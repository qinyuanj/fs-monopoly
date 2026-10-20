return {
  canvas = "破产展示屏",
  text = "破产_文字",
  avatar = "破产玩家头像",
  -- #178:破产屏不做点背景关闭(仅约 2 秒自动关闭),提示文字在运行时隐藏;
  -- 灰底只登记节点名,不注册点击。
  close_hint = "破产_关闭破产文本提示",
  -- #176 review 决定:underlay 保持「仅登记、不接线」——不进 ui_state 弹窗面、
  -- 不进 _option_screen/touch 触摸链、不进 ui_bootstrap_nodes 必需点击节点。
  -- 消费方是全量 schema 节点存在性校验(test/behavior/ui/schema/
  -- test_all_schema_nodes.lua):编辑器改名事故在此处 fail-fast,而不是让
  -- 将来的接线方按名扑空。
  underlay = "破产_灰底",
}
