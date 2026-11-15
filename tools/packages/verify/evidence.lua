-- verify 的测量证据(#130):每条车道的完整输出 + 整体报告一起落盘。
-- spec-lane 车道另外经 --evidence-dir 拿到自己的原始 TAP / COUNTS(见
-- lane_builders),可用 `spec-lane --recount <dir>/<profile>` 重算;这里保存的是
-- verify 视角的车道结果与汇总,lint / encoding 等非 spec-lane 车道也因此
-- 在证据目录里留下完整输出。
local fs_lib = require("foundation.fs")

local M = {}

local function _safe(label)
  return (tostring(label or "lane"):gsub("[^%w_.%-]", "_"))
end

function M.write(dir, results, report)
  local ok, err = fs_lib.ensure_dir(dir)
  if not ok then return nil, err end
  local lines = {}
  for _, r in ipairs(results or {}) do
    local written, write_err = fs_lib.write_file(dir .. "/" .. _safe(r.label) .. ".out", tostring(r.output or ""))
    if not written then return nil, write_err end
    lines[#lines + 1] = string.format("lane=%s exit_code=%s ok=%s",
      tostring(r.label), tostring(r.exit_code), tostring(r.ok))
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = tostring(report or "")
  return fs_lib.write_file(dir .. "/summary.txt", table.concat(lines, "\n"))
end

return M
