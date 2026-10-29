require("test.bootstrap").install_package_paths()

local json_reader = require("foundation.json_reader")

local M = {}

-- 仓根 eggy.json 只允许 isSEMap(editor-cli 的 detectMode 只读这一项判 FS/SE)。
-- editor-cli code init / 地图解析自愈会写回 projectID、playerNid、mapDir 等本机信息,
-- 这里检查工作树内容,写回后本地 verify 即判红,不让它随手 git add 进库。
local _ALLOWED_KEYS = { isSEMap = true }
local _PATH = "eggy.json"

local function _prefixed(text)
  return "eggy_json_guard: " .. text
end

-- 核心判定(供 spec 注入合成文本;run 走同一逻辑):返回违规描述列表,键名按字典序。
function M.check(text)
  local ok, decoded = pcall(json_reader.decode, text)
  if not ok then
    return { _prefixed("invalid json: " .. tostring(decoded)) }
  end
  if type(decoded) ~= "table" then
    return { _prefixed("top level must be an object") }
  end
  local violations = {}
  local extra = {}
  for key in pairs(decoded) do
    if not _ALLOWED_KEYS[key] then
      extra[#extra + 1] = tostring(key)
    end
  end
  table.sort(extra)
  for _, key in ipairs(extra) do
    violations[#violations + 1] = _prefixed("disallowed key: " .. key)
  end
  if type(decoded.isSEMap) ~= "boolean" then
    violations[#violations + 1] = _prefixed("isSEMap must be a boolean")
  end
  return violations
end

function M.run()
  local file = io.open(_PATH, "rb")
  if file == nil then
    -- eggy.json 缺失时 editor-cli 回退 map ledger 判模式,不算违规。
    return { ok = true, message = "eggy_json_guard ok (no eggy.json)" }
  end
  local text = file:read("a")
  file:close()
  local violations = M.check(text)
  if #violations > 0 then
    return { ok = false, error = table.concat(violations, "\n") }
  end
  return { ok = true, message = "eggy_json_guard ok" }
end

return M
