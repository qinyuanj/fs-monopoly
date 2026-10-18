local bankruptcy = {}
local contract_helper = require("src.rules.ports.contract_helper")

function bankruptcy.eliminate(game, player, opts)
  return contract_helper.call_required_method(game, "bankruptcy_port", "bankruptcy_port", "eliminate", game, player, opts)
end

return bankruptcy

