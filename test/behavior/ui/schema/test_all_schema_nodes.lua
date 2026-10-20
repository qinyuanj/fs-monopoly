-- #176 Testing Decisions:schema 中引用的节点名都存在于 UI 节点表。
-- 早前只有 remote_choice 一个 schema 有该校验(#177 编辑器改名事故驱动);
-- 本文件把同一校验推广为全 schema 覆盖,schema 节点名漂移在此即判红。

-- luacheck: ignore 143 (genuine busted injects luassert)
local luassert = assert

-- 非节点值白名单(按 schema 与字段登记,注明原因;其余 string 值一律视为节点名):
local WHITELIST = {
  base = {
    -- "%s" 是玩家序号占位符,消费方 string.format 出 1..4 后才按名查节点;
    -- 裸模板不是节点名,校验改写为对四个实例逐一核对。
    player_name = "玩家序号 %s 占位模板,实例化后校验",
    player_cash = "玩家序号 %s 占位模板,实例化后校验",
    player_cash_delta = "玩家序号 %s 占位模板,实例化后校验",
    player_land_count = "玩家序号 %s 占位模板,实例化后校验",
    player_total_assets = "玩家序号 %s 占位模板,实例化后校验",
    player_crown = "玩家序号 %s 占位模板,实例化后校验",
    player_avatar = "玩家序号 %s 占位模板,实例化后校验",
    player_color = "玩家序号 %s 占位模板,实例化后校验",
  },
  base_contract = {
    key = "schema 标识键,不是节点名",
  },
  item_atlas = {
    page_size = "数字配置,遍历已跳过;登记仅防改回 string 时漏网",
  },
  market_layout = {
    page_prev_text = "翻页按钮上的纯文案,不是节点名",
    page_next_text = "翻页按钮上的纯文案,不是节点名",
    empty_ref_key = "资源引用键(宿主素材侧),不是节点名",
  },
  skin = {
    page_size = "数字配置,遍历已跳过;登记仅防改回 string 时漏网",
  },
}

-- 节点表按 entry[1] 为节点名(与 test_remote_choice 同口径,数据源 Data.UIManagerNodes)。
local known = {}
for _, entry in pairs(require("Data.UIManagerNodes")) do
  if type(entry) == "table" then
    known[entry[1]] = true
  end
end

local function _assert_known(name, origin)
  luassert.is_true(known[name] == true,
    "schema node missing from UI node table: " .. tostring(name) .. " (" .. origin .. ")")
end

local function _is_whitelisted(schema_key, field_key)
  local rules = WHITELIST[schema_key]
  return rules ~= nil and rules[field_key] ~= nil
end

-- 递归收集 schema 里的节点名字符串;嵌套表(如 base_contract.action_log)一并展开。
local function _check_value(schema_key, path, value)
  if type(value) == "string" then
    local field_key = path[#path]
    if not _is_whitelisted(schema_key, field_key) then
      _assert_known(value, schema_key .. "." .. table.concat(path, "."))
    end
  elseif type(value) == "table" then
    for key, child in pairs(value) do
      local child_path = { table.unpack(path) }
      child_path[#child_path + 1] = tostring(key)
      _check_value(schema_key, child_path, child)
    end
  end
  -- 函数(skin_request 的归一化方法)与数字(page_size)不是节点名,跳过。
end

local function _check_schema(schema_key, schema)
  for key, value in pairs(schema) do
    _check_value(schema_key, { tostring(key) }, value)
  end
end

describe("TestAllSchemaNodes", function()

it("test_every_schema_string_node_name_exists_in_the_ui_node_table", function()
  _check_schema("bankruptcy", require("src.ui.schema.bankruptcy"))
  _check_schema("base", require("src.ui.schema.base"))
  _check_schema("base_contract", require("src.ui.schema.base_contract"))
  _check_schema("debug", require("src.ui.schema.debug"))
  _check_schema("dice", require("src.ui.schema.dice"))
  _check_schema("item_atlas", require("src.ui.schema.item_atlas"))
  _check_schema("market", require("src.ui.schema.market"))
  _check_schema("market_layout", require("src.ui.schema.market_layout"))
  _check_schema("permanent", require("src.ui.schema.permanent"))
  _check_schema("player_choice", require("src.ui.schema.player_choice"))
  _check_schema("popup", require("src.ui.schema.popup"))
  _check_schema("remote_choice", require("src.ui.schema.remote_choice"))
  _check_schema("secondary_confirm", require("src.ui.schema.secondary_confirm"))
  _check_schema("skin", require("src.ui.schema.skin"))
  _check_schema("skin_request", require("src.ui.schema.skin_request"))
  _check_schema("status3d", require("src.ui.schema.status3d"))
  _check_schema("target_choice", require("src.ui.schema.target_choice"))
end)

it("test_base_player_templates_instantiate_to_known_nodes_for_slots_1_to_4", function()
  -- "%s" 占位模板的校验面:四个玩家槽实例化后的名字都必须在节点表里。
  local base = require("src.ui.schema.base")
  local templates = {
    base.player_name, base.player_cash, base.player_cash_delta,
    base.player_land_count, base.player_total_assets, base.player_crown,
    base.player_avatar, base.player_color,
  }
  for slot = 1, 4 do
    for index, template in ipairs(templates) do
      _assert_known(string.format(template, slot), "base player template " .. index .. " slot " .. slot)
    end
  end
end)

it("test_whitelist_entries_still_match_their_schema_field", function()
  -- 白名单字段被删/改名时此测试判红,防止白名单静默过期变成免死金牌。
  local schemas = {
    base = require("src.ui.schema.base"),
    base_contract = require("src.ui.schema.base_contract"),
    item_atlas = require("src.ui.schema.item_atlas"),
    market_layout = require("src.ui.schema.market_layout"),
    skin = require("src.ui.schema.skin"),
  }
  for schema_key, rules in pairs(WHITELIST) do
    local schema = schemas[schema_key]
    luassert.is_not_nil(schema, "whitelist references unknown schema: " .. schema_key)
    for field_key, _reason in pairs(rules) do
      luassert.is_true(rawget(schema, field_key) ~= nil,
        "whitelist field no longer exists: " .. schema_key .. "." .. field_key ..
        " (remove the stale whitelist entry or re-justify)")
    end
  end
end)

end)
