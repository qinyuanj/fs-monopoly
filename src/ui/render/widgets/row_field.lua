local number_utils = require("src.foundation.number")

local row_field = {}

function row_field.to_integer(row, key)
  if not row then
    return nil
  end
  return number_utils.to_integer(row[key])
end

return row_field

