-- 皮肤归属接口测试的宿主替身(#204 / #205):只替换现有 seam——runtime_ports(玩家
-- 存档 Int/Str、墙钟、换模型端口)、付费购买 port、成就进度 port。
-- 存档按 role|key 存值;opts.int_write_ok / str_write_ok = false 模拟宿主不报错但
-- 值没落下;opts.str_unreadable 模拟 Str 读档降级为 nil;opts.enabled = false 模拟
-- 存档未开启;opts.now 为墙钟秒。换模型端口记录到 model_calls,默认成功;
-- opts.set_model_ok / reset_model_ok = false 模拟端口报失败(宿主侧缺对象/方法或抛错)。
-- 调用方 teardown 须调 shared_support.restore_runtime_services() 与
-- achievement_progress_port.reset_for_tests() 装回基线。
require("test.bootstrap").install_package_paths()
local runtime_ports = require("src.foundation.ports.runtime_ports")
local paid_purchase_port = require("src.rules.ports.paid_purchase")
local achievement_progress_port = require("src.rules.ports.achievement_progress")

local M = {}

local function _store_key(role_id, key)
  return tostring(role_id) .. "|" .. tostring(key)
end

-- 换模型端口替身:按调用顺序记录 { op, args },op 为 set_model / reset_model。
local function _model_ports(opts, model_calls)
  return {
    set_role_model = function(role_id, creature_key)
      model_calls[#model_calls + 1] = { op = "set_model", role_id = role_id, args = { creature_key } }
      return opts.set_model_ok ~= false
    end,
    reset_role_model = function(role_id)
      model_calls[#model_calls + 1] = { op = "reset_model", role_id = role_id, args = {} }
      return opts.reset_model_ok ~= false
    end,
  }
end

local function _archive_ports(opts, store, reads)
  return {
    archives_enabled = function()
      return opts.enabled ~= false
    end,
    get_archive_int = function(role_id, key)
      reads[#reads + 1] = _store_key(role_id, key)
      return store[_store_key(role_id, key)] or 0
    end,
    set_archive_int = function(role_id, key, value)
      if opts.int_write_ok ~= false then
        store[_store_key(role_id, key)] = value
      end
      return true
    end,
    get_archive_str = function(role_id, key)
      reads[#reads + 1] = _store_key(role_id, key)
      if opts.str_unreadable then
        return nil
      end
      return store[_store_key(role_id, key)] or ""
    end,
    set_archive_str = function(role_id, key, value)
      if opts.str_write_ok ~= false then
        store[_store_key(role_id, key)] = value
      end
      return true
    end,
  }
end

function M.install(opts)
  opts = opts or {}
  local store = {}
  for key, value in pairs(opts.seed or {}) do
    store[key] = value
  end
  local reads = {}
  local model_calls = {}
  local ports = _archive_ports(opts, store, reads)
  for name, port in pairs(_model_ports(opts, model_calls)) do
    ports[name] = port
  end
  ports.wall_now_seconds = function()
    return opts.now
  end
  runtime_ports.configure(ports)
  return {
    opts = opts,
    model_calls = model_calls,
    read = function(role_id, key)
      return store[_store_key(role_id, key)]
    end,
    write = function(role_id, key, value)
      store[_store_key(role_id, key)] = value
    end,
    reads = function()
      return #reads
    end,
  }
end

-- seed 表的 key 写法与替身一致:seed_key(role_id, archive_key)。
M.seed_key = _store_key

-- 假付费网关:接住购买条目,不自动完成;测试手动调 entry.on_purchase() 模拟宿主
-- 异步完成。opts.start 可覆盖 start 的返回(默认 true)。
function M.install_paid_gateway(opts)
  opts = opts or {}
  local gateway = { entries = {} }
  paid_purchase_port.configure({
    setup_for_game = function()
      return true
    end,
    can_start = function()
      return true
    end,
    start = function(game, player, entry)
      gateway.entries[#gateway.entries + 1] = { game = game, player = player, entry = entry }
      if opts.start ~= nil then
        return opts.start(game, player, entry)
      end
      return true
    end,
  })
  function gateway.last_entry()
    local last = gateway.entries[#gateway.entries]
    return last and last.entry or nil
  end
  return gateway
end

-- 成就进度替身:记录 skin_equipped 上报。
function M.install_achievements()
  local reports = {}
  achievement_progress_port.configure({
    skin_equipped = function(_, role_id, skin)
      reports[#reports + 1] = { role_id = role_id, product_id = skin and skin.product_id }
      return true
    end,
  })
  return reports
end

-- 付费购买路径按 state.game:find_player_by_id(role_id) 解析买家。
function M.state()
  return {
    ui = {},
    game = {
      find_player_by_id = function(_, role_id)
        return { id = role_id }
      end,
    },
  }
end

return M
