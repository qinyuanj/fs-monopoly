-- 无玩法语义的 mixin 安装：逐键复制，并以所属模块名报告首个冲突。
local mixin = {}

function mixin.install(owner, target, source, source_name)
  for key, fn in pairs(source) do
    assert(target[key] == nil, owner .. " mixin collision: " .. tostring(source_name) .. "." .. tostring(key))
    target[key] = fn
  end
end

return mixin
