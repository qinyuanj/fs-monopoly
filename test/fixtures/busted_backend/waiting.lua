-- 测试体等待子进程而不占 CPU:durations-out 记的是墙钟,应不少于等待时长。
describe("real busted execution", function()
  it("waits on a child process", function()
    assert.is_true(os.execute("sleep 1"))
  end)
end)
