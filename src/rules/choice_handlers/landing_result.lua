local landing_result = {}

function landing_result.settle(finish_choice, game, result)
  if result and result.stay then
    return result
  end
  return finish_choice(game, false)
end

return landing_result

