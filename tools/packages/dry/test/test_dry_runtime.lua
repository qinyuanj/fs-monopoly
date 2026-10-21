---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/packages/dry/test/test_dry_runtime.lua") end
require("test.bootstrap").install_package_paths()

-- dry 车道对邻接 dryer 检出的纯演算面(#148):路径约定、不可用分类与有效结果判据。
local check = require("luassert")
local dryer = require("packages.dry.dryer")

local ROOT = "/repo"

describe("dry dryer runtime", function()

it("addresses the adjacent checkout and its venv python without the sh launcher", function()
  check.equal("/repo/.uml-viewer/dryer", dryer.checkout_dir("/repo/"))
  check.equal("/repo/.uml-viewer/dryer/.venv/bin/python", dryer.python_path(ROOT))
end)

-- 缺检出 / 缺 venv 是「不可用」(不启动工具),不是「没有重复」。
it("classifies a missing checkout or venv as unavailable, checkout first", function()
  check.same({ step = "checkout", detail = "/repo/.uml-viewer/dryer 缺失" },
    dryer.availability(ROOT, { checkout = false, python = false }))
  local venv = dryer.availability(ROOT, { checkout = true, python = false })
  check.equal("venv", venv.step)
  check.truthy(venv.detail:find("/.venv/bin/python", 1, true) ~= nil, venv.detail)
  check.is_nil(dryer.availability(ROOT, { checkout = true, python = true }))
end)

it("defaults the metrics root to the repo and honours --root", function()
  check.equal(ROOT, dryer.metrics_root({ "src" }, ROOT))
  check.equal("/tmp/x", dryer.metrics_root({ "--root", "/tmp/x", "src" }, ROOT))
  check.equal("/repo/sub", dryer.metrics_root({ "--root", "sub" }, ROOT))
  check.is_nil(dryer.metrics_root({ "--root" }, ROOT))
  check.is_nil(dryer.metrics_root({ "--root", "--edn" }, ROOT))
end)

describe("effective result", function()

it("accepts exit 0 with a freshly written metrics file", function()
  check.is_true(dryer.judge(0, "DUPLICATE score=1.00\n", true).ok)
end)

-- 重复项只提示、不致失败;没有重复但新写出了文件同样有效。
it("does not depend on whether duplicates were reported", function()
  check.is_true(dryer.judge(0, "No duplicate candidates found.\n", true).ok)
end)

it("rejects zero candidate files even though dryer exits 0", function()
  local verdict = dryer.judge(0, dryer.NO_SOURCE_MESSAGE .. "\n", true)
  check.is_false(verdict.ok)
  check.truthy(verdict.reason:find("候选文件数为 0", 1, true) ~= nil, verdict.reason)
end)

it("rejects a run that did not write the metrics file", function()
  local verdict = dryer.judge(0, "DUPLICATE score=1.00\n", false)
  check.is_false(verdict.ok)
  check.truthy(verdict.reason:find(".metrics/dry.edn", 1, true) ~= nil, verdict.reason)
end)

it("rejects a nonzero dryer exit and names the code", function()
  local verdict = dryer.judge(1, "", true)
  check.is_false(verdict.ok)
  check.truthy(verdict.reason:find("退出码 1", 1, true) ~= nil, verdict.reason)
end)

end)

end)
