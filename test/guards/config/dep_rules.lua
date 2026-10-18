-- 出生类配置(#176):dep_rules 七层规则表与行级白名单,归项目所有。
-- 引擎住 test/guards/lib/dep_rules.lua 与 test_dep_rules.lua 的扫描壳;规则内容一律在本文件维护。

local rules = {
  {
    roots = { "tools/foundation" },
    forbidden_patterns = {
      "%f[%w_]require%s*%(?%s*[\"']packages%.",
    },
    forbidden_call_paths = {
      run_command = "tools[/\\]+packages[/\\]+",
      dofile = "tools[/\\]+packages[/\\]+",
      loadfile = "tools[/\\]+packages[/\\]+",
    },
    description = "tools/foundation must not depend on packages.* modules or execute tools/packages scripts directly",
  },
  {
    roots = { "src/host/entity_pool.lua" },
    forbidden_patterns = {
      'require%("src%.ui%.',
      "require%('src%.ui%.",
      'require%("src%.rules%.',
      "require%('src%.rules%.",
    },
    description = "src/host/entity_pool.lua must not depend on src.ui.* or src.rules.*",
  },
  {
    roots = { "src/foundation" },
    forbidden_patterns = {
      'require%("src%.state"',
      'require%("src%.state%.',
      "require%('src%.state'",
      "require%('src%.state%.",
    },
    description = "foundation must not require any src.state module (ADR 0002 invariant)",
  },
  {
    roots = { "src/state", "src/player", "src/computer", "src/rules" },
    forbidden_patterns = {
      "%f[%w_]GameAPI%f[^%w_]",
      "%f[%w_]GlobalAPI%f[^%w_]",
      "%f[%w_]SetTimeOut%f[^%w_]",
      "%f[%w_]RegisterTriggerEvent%f[^%w_]",
      "%f[%w_]RegisterCustomEvent%f[^%w_]",
    },
    description = "game core must not use runtime global APIs directly",
  },
  {
    roots = { "src", "test/support/tooling_suites/architecture" },
    forbidden_patterns = {
      "%f[%w_]invalidate_ui%f[^%w_]",
      "compatibility%s+alias",
      "compatibility%s+contract",
      "legacy%s+alias",
      "alias%s+entry",
      "alias%s+fallback",
      "shim%s+entry",
      "shim%s+fallback",
      "pre_move.-window",
      "pre_move.-窗口",
    },
    description = "business layers must not reintroduce retired invalidate_ui / alias / shim / compat wording or active-window pre_move phrasing",
  },
  {
    roots = { "src/rules" },
    forbidden_patterns = {
      "ui_port%.wait_action_anim",
      "game%.ui_port%.wait_action_anim",
    },
    description = "systems layer must use ActionAnimPort instead of direct ui_port.wait_action_anim checks",
  },
  {
    roots = { "src/rules" },
    forbidden_patterns = {
      "game%.gameplay_loop_ports",
      "self%.gameplay_loop_ports",
    },
    description = "rules layer must not read gameplay loop runtime object fields directly",
  },
  {
    roots = { "src/turn" },
    forbidden_patterns = {
      "state%.ui%.",
      "state%.ui_[A-Za-z0-9_]+%s*=",
    },
    description = "turn flow must route UI reads and writes through output/ui_sync ports",
  },
  {
    roots = { "src/state" },
    forbidden_patterns = {
      "require%(\"src%.turn%.output%..+\"%)",
      "require%('src%.turn%.output%..+'%)",
    },
    description = "state must not depend on turn output adapters directly",
  },
  {
    roots = { "src/rules/market" },
    forbidden_patterns = {
      "require%(\"src%.rules%.land%.choice_specs\"%)",
      "require%('src%.rules%.land%.choice_specs'%)",
    },
    description = "market subsystem must not depend on land choice specs",
  },
  {
    roots = { "src/rules/items" },
    forbidden_patterns = {
      "require%(\"src%.rules%.land%.board_utils\"%)",
      "require%('src%.rules%.land%.board_utils'%)",
      "require%(\"src%.rules%.land%.rent_resolver\"%)",
      "require%('src%.rules%.land%.rent_resolver'%)",
    },
    description = "items subsystem must use neutral board/property helpers instead of land internals",
  },
  {
    roots = { "src/rules/market" },
    forbidden_patterns = {
      "%f[%w_]GameAPI%f[^%w_]",
      "%f[%w_]RegisterTriggerEvent%f[^%w_]",
      "%f[%w_]EVENT%f[^%w_]",
    },
    description = "market service layer must not call host purchase globals directly",
  },
  {
    roots = { "src/turn", "src/ui", "src/player", "src/computer", "src/rules" },
    forbidden_patterns = {
      "%f[%w_]all_roles%f[^%w_]",
      "%f[%w_]ALLROLES%f[^%w_]",
      "%f[%w_]camera_helper%f[^%w_]",
    },
    description = "game/presentation layers must not read legacy runtime globals directly",
  },
  {
    roots = { "src/turn/actions", "src/turn/policies", "src/ui" },
    forbidden_patterns = {
      "cfg%.timing%s*==",
      "cfg%.timing%s*~=",
      "item%.timing%s*==",
      "item%.timing%s*~=",
    },
    description = "turn/ui layers must not read item timing config directly; use rules/items availability use-case",
  },
  {
    roots = { "test" },
    forbidden_patterns = {
      'require%(%s*"support%.',
      "require%(%s*'support%.",
      'require%(%s*"fixtures%.',
      "require%(%s*'fixtures%.",
    },
    description = "test requires must use canonical test.support.* / test.fixtures.* paths",
  },
  {
    roots = { "src" },
    forbidden_patterns = {
      "%f[%w_]control_mode%f[^%w_]",
    },
    description = "player.control_mode is owned exclusively by src/player/control.lua; no other production module may read or write it",
  },
  {
    roots = { "src" },
    forbidden_patterns = {
      "%.auto%f[^%w_%.]",
      "%f[%w_]auto_source%f[^%w_]",
      "%.ai%f[^%w_%.]",
      "%f[%w_]is_auto_player%f[^%w_]",
      "%f[%w_]by_ai%f[^%w_]",
    },
    description = "retired player delegation fields (auto/auto_source), ghost ai fields, and old is_auto_player/by_ai identifiers must not reappear in production code",
  },
  {
    roots = { "src" },
    forbidden_patterns = {
      "%f[%w_]popup_queue%f[^%w_]",
    },
    description = "popup display session backlog (ui.popup_queue) is owned exclusively by src/ui/coord/popup_presenter.lua; other modules must go through the session public interface (push_popup/close_popup/dismiss_popup) instead of touching internal entry/backlog tables (#600)",
  },
  {
    roots = { "src" },
    forbidden_patterns = {
      "%f[%w_]owner_only%f[^%w_]",
      "%f[%w_]gained_item_display%f[^%w_]",
      "%f[%w_]play_item_get_reveal%f[^%w_]",
      'require%(%s*"src%.ui%.render%.anim%.item_get_reveal"',
      "require%(%s*'src%.ui%.render%.anim%.item_get_reveal'",
      "[\"']item_get_reveal[\"']",
    },
    description = "retired owner-only / enlarged-card private reveal model (flat popup fields, gained_item_display record, item_get_reveal chain) must not reappear in production code (#543/#599/#600)",
  },
}

local whitelist = {}

whitelist["src/host/global_aliases.lua"] = {
  ["bridge exception, not a business compatibility alias layer."] = true,
}

whitelist["src/player/control.lua"] = {
  ["control_mode"] = true,
}

-- 弹窗展示会话 backlog 的唯一属主(#600);其余模块一律走会话公开接口。
whitelist["src/ui/coord/popup_presenter.lua"] = {
  ["popup_queue"] = true,
}

-- roster/debug 的「哪些席位是补位电脑」配置键;不是玩家对象上的幽灵字段。
whitelist["src/app/game_factory.lua"] = {
  ["opts.ai"] = true,
}

-- auto-play 能力模块的模块路径,不是玩家对象上的旧 auto 字段。
whitelist["src/rules/market/init.lua"] = {
  ["market.auto"] = true,
}

return {
  rules = rules,
  whitelist = whitelist,
}
