-- eimage.lua branch-dense coverage: 颜色/贴图更新的 client_role 定向分支、全角色广播分支与 reset_size 开关。
local luassert = assert
local context = require("src.ui.manager.context")
local EImage = require("src.ui.manager.eimage")
local support = require("test.support.ui_manager_nodes_support")

describe("TestEImage", function()
local role_a, role_b

before_each(function()
  support.clear_context()
  support.install_host_math()
  role_a = support.make_role(1)
  role_b = support.make_role(2)
end)

after_each(function()
  support.clear_context()
  support.restore_host_math()
end)

it("test_init_defaults_color_texture_and_transition_time", function()
  local image = EImage:new(501, "img")

  luassert.truthy(image.image_color == 0xffffff, "new image color should default to white")
  luassert.truthy(image.image_texture == -1, "new image texture should default to -1")
  luassert.truthy(image.transition_time == 0.0, "new image transition_time should default to 0.0")
end)

it("test_image_color_targets_only_the_client_role_and_carries_transition_time", function()
  context.client_role = role_a
  support.install_roles({ role_a, role_b })
  local image = EImage:new(502, "img")
  image.transition_time = 0.25

  image.image_color = 0x123456

  local calls = support.calls_of(role_a, "set_image_color")
  luassert.truthy(#calls == 1, "client role should receive set_image_color once")
  luassert.truthy(calls[1].args[1] == 502, "host call should carry the eui node id")
  luassert.truthy(calls[1].args[2] == 0x123456, "host call should carry the new color")
  luassert.truthy(calls[1].args[3] == 0.25, "host call should carry the transition time")
  luassert.truthy(#role_b.calls == 0, "other roles should not receive the color update")
  luassert.truthy(image.image_color == 0x123456, "image_color getter should report the stored value")
end)

it("test_image_color_broadcasts_to_all_roles_when_no_client_role", function()
  support.install_roles({ role_a, role_b })
  local image = EImage:new(503, "img")

  image.image_color = 0x00ff00

  for _, role in ipairs({ role_a, role_b }) do
    local calls = support.calls_of(role, "set_image_color")
    luassert.truthy(#calls == 1 and calls[1].args[2] == 0x00ff00, "every role should receive the color update")
    luassert.truthy(calls[1].args[3] == 0.0, "every role should receive the default transition time")
  end
end)

it("test_image_texture_keeps_size_for_the_client_role", function()
  context.client_role = role_a
  support.install_roles({ role_a, role_b })
  local image = EImage:new(504, "img")

  image.image_texture = 88

  local calls = support.calls_of(role_a, "set_image_texture_by_key_with_auto_resize")
  luassert.truthy(#calls == 1, "client role should receive the texture call once")
  luassert.truthy(calls[1].args[1] == 504, "host call should carry the eui node id")
  luassert.truthy(calls[1].args[2] == 88, "host call should carry the texture key")
  luassert.truthy(calls[1].args[3] == false, "setting image_texture should not reset size")
  luassert.truthy(#role_b.calls == 0, "other roles should not receive the texture update")
  luassert.truthy(image.image_texture == 88, "image_texture getter should report the stored value")
end)

it("test_image_texture_broadcasts_to_all_roles_when_no_client_role", function()
  support.install_roles({ role_a, role_b })
  local image = EImage:new(505, "img")

  image.image_texture = 9

  for _, role in ipairs({ role_a, role_b }) do
    local calls = support.calls_of(role, "set_image_texture_by_key_with_auto_resize")
    luassert.truthy(#calls == 1 and calls[1].args[2] == 9, "every role should receive the texture update")
    luassert.truthy(calls[1].args[3] == false, "broadcast texture update should not reset size")
  end
end)

it("test_set_texture_keep_size_stores_the_key_without_resetting_size", function()
  support.install_roles({ role_a })
  local image = EImage:new(506, "img")

  image:set_texture_keep_size(11)

  local calls = support.calls_of(role_a, "set_image_texture_by_key_with_auto_resize")
  luassert.truthy(#calls == 1 and calls[1].args[2] == 11, "texture key should be pushed to the host")
  luassert.truthy(calls[1].args[3] == false, "keep-size should pass reset_size=false")
  luassert.truthy(image.image_texture == 11, "texture key should be stored on the node")
end)

it("test_set_texture_native_size_resets_size", function()
  context.client_role = role_a
  support.install_roles({ role_a, role_b })
  local image = EImage:new(507, "img")

  image:set_texture_native_size(12)

  local calls = support.calls_of(role_a, "set_image_texture_by_key_with_auto_resize")
  luassert.truthy(#calls == 1 and calls[1].args[2] == 12, "texture key should be pushed to the client role")
  luassert.truthy(calls[1].args[3] == true, "native-size should pass reset_size=true")
  luassert.truthy(image.image_texture == 12, "texture key should be stored on the node")
end)

it("test_transition_time_setter_stores_the_fixed_value_without_host_calls", function()
  support.install_roles({ role_a })
  local image = EImage:new(509, "img")

  image.transition_time = 1.5

  luassert.truthy(image.transition_time == 1.5, "transition_time getter should report the stored value")
  luassert.truthy(#role_a.calls == 0, "setting transition_time alone should not touch the host")
end)


end)
