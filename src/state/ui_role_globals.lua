local role_globals = {}

function role_globals.install(roles)
  local resolved = roles
  if type(resolved) ~= "table" then
    resolved = {}
  end
  _G["ALLROLES"] = resolved
  _G["all_roles"] = resolved
  return resolved
end

return role_globals

