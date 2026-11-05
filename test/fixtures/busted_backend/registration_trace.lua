-- 注册 describe / it 时不构造完整 traceback(性能契约:它曾占 behavior 车道 ~85% CPU);
-- 失败用例仍按注册位置报 `# <文件> @ <行>`,错误路径的 traceback 照常可用。
local real_traceback = debug.traceback
local during_registration = 0
rawset(debug, "traceback", function(...)
  during_registration = during_registration + 1
  return real_traceback(...)
end)
describe("registration trace", function()
  for i = 1, 20 do
    it("registered case " .. i, function() end)
  end
  it("registration builds no traceback", function()
    rawset(debug, "traceback", real_traceback)
    assert.equal(0, during_registration)
  end)
  it("failure keeps its registration line", function()
    assert.equal(1, 2)
  end)
end)
