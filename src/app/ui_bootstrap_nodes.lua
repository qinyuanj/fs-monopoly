local base_nodes = require("src.ui.schema.base")
local base_contract = require("src.ui.schema.base_contract")
local player_choice_nodes = require("src.ui.schema.player_choice")
local target_choice_nodes = require("src.ui.schema.target_choice")
local remote_choice_nodes = require("src.ui.schema.remote_choice")
local secondary_confirm_nodes = require("src.ui.schema.secondary_confirm")
local market_nodes = require("src.ui.schema.market")
local skin_nodes = require("src.ui.schema.skin")
local item_atlas_nodes = require("src.ui.schema.item_atlas")

local bootstrap_nodes = {}

local function _required_click_nodes()
  local required = {
    base_nodes.action_button,
    base_nodes.end_button,
    -- 道具使用后续选择的唯一取消出口:节点缺失必须开局 fail-fast,
    -- 否则取消链全断且只弹一次 tip、日志无痕。
    base_nodes.cancel_button,
    base_nodes.auto_button,
    base_nodes.share_button,
    target_choice_nodes.confirm,
    target_choice_nodes.cancel,
    secondary_confirm_nodes.confirm,
    secondary_confirm_nodes.cancel,
    -- #178 点背景关闭:背景节点改名/缺失会让点背景关闭静默失效,开局 fail-fast。
    market_nodes.background,
    skin_nodes.activity_background,
    item_atlas_nodes.background,
  }
  return required
end

local function _append_click_nodes(required, names)
  for _, name in ipairs(names or {}) do
    required[#required + 1] = name
  end
end

local function _extra_nodes(opts)
  local extra = opts and opts.extra or nil
  return type(extra) == "table" and extra or nil
end

function bootstrap_nodes.build_required_click_nodes(opts)
  local required = _required_click_nodes()
  for _, name in ipairs(player_choice_nodes.slots) do
    required[#required + 1] = name
  end
  for _, name in ipairs(remote_choice_nodes.options) do
    required[#required + 1] = name
  end
  -- 遥控骰子灰底是点背景关闭出口(#177),节点缺失必须开局 fail-fast。
  required[#required + 1] = remote_choice_nodes.underlay
  _append_click_nodes(required, base_contract.action_log.toggle_targets)
  _append_click_nodes(required, _extra_nodes(opts))
  return required
end

local function _node_name_from_entry(entry)
  if type(entry) ~= "table" then
    return nil
  end
  local name = entry[1]
  if type(name) ~= "string" then
    return nil
  end
  return name
end

local function _index_known_nodes(ui_manager_nodes)
  local known = {}
  for _, entry in pairs(ui_manager_nodes) do
    local name = _node_name_from_entry(entry)
    if name ~= nil then
      known[name] = true
    end
  end
  return known
end

local function _missing_node(name, known, seen)
  return type(name) == "string" and name ~= "" and not known[name] and not seen[name]
end

local function _missing_required(required_nodes, known)
  local missing = {}
  local seen = {}
  for _, name in ipairs(required_nodes or {}) do
    if _missing_node(name, known, seen) then
      missing[#missing + 1] = name
      seen[name] = true
    end
  end
  return missing
end

function bootstrap_nodes.validate_required_nodes(ui_manager_nodes, required_nodes)
  if type(ui_manager_nodes.validate) == "function" then
    return ui_manager_nodes.validate(required_nodes)
  end
  return _missing_required(required_nodes, _index_known_nodes(ui_manager_nodes))
end

function bootstrap_nodes.assert_required_nodes(ui_manager_nodes, opts)
  local required_nodes = bootstrap_nodes.build_required_click_nodes(opts)
  local missing = bootstrap_nodes.validate_required_nodes(ui_manager_nodes, required_nodes)
  if #missing > 0 then
    error("UI 节点缺失: " .. table.concat(missing, ", "))
  end
end

return bootstrap_nodes

