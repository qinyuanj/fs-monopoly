-- choice 超时 deadline scope 分类:唯一归宿。
-- pending choice 按 kind 落到一个 deadline scope 桶:market_buy → "market_buy",
-- 其余(含 nil / 无 kind)→ "choice"。scope 名即 deadlines.start/peek/cancel 的
-- scope 键。原先 waits/choice_tracking._scope_for_choice 与
-- deadlines/choice_resolution._choice_timeout_scope 各写了一份字节级重复的
-- 同一分类,二者收敛到此。
local choice_scope = {}

function choice_scope.for_choice(choice)
  if choice and choice.kind == "market_buy" then
    return "market_buy"
  end
  return "choice"
end

return choice_scope

