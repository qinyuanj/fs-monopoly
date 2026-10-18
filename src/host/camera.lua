local camera_helper = {}

function camera_helper.new(env, deps)
  local helper = {
    _env = env,
    target_role_id = nil,
  }

  function helper.set_target(role_id)
    helper.target_role_id = role_id
    return role_id
  end

  function helper.get_target()
    return helper.target_role_id
  end

  function helper.follow(role_id)
    if role_id == nil then
      return false
    end
    helper.set_target(role_id)
    return true
  end

  return helper
end

return camera_helper

