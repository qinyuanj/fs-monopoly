local luassert = assert
local choice_builder = require("src.ui.view.choice_builder")

describe("TestChoiceBuilder", function()

it("test_builds_phase_title_and_option_fields", function()
  local view = choice_builder.build_choice_view({
    id = 7,
    kind = "item_phase_passive",
    title = "请选择",
    body_lines = { "第一行", "第二行" },
    options = {
      {
        id = 2001,
        label = "路障卡",
        can_buy = true,
        can_buy_with_free_slot = true,
        requires_pre_confirm = true,
        pre_confirm_kind = "secondary_confirm",
        confirm_title = "确认使用",
        confirm_body = "确认文案",
      },
    },
    allow_cancel = false,
    cancel_label = "返回",
    route_key = "base_inline",
  }, {
    game = {
      turn = {
        item_phase_active = "pre_action",
      },
    },
  })

  luassert.is.equal("请选择", view.title, "choice view should return base title without phase label")
  luassert.is.equal("第一行\n第二行", view.body, "choice view should join body_lines")
  luassert.is.equal(false, view.allow_cancel, "choice view should preserve explicit allow_cancel")
  luassert.is.equal("返回", view.cancel_label, "choice view should preserve cancel label")
  luassert.is.equal("base_inline", view.route_key, "choice view should copy explicit fields")
  luassert.is.equal(true, view.options[1].requires_pre_confirm, "choice view should copy pre-confirm marker")
  luassert.is.equal("确认使用", view.options[1].confirm_title, "choice view should copy confirm title")
  luassert.is.equal(true, view.options[1].can_buy_with_free_slot, "choice view should copy the confirm button flag")
end)

it("test_defaults_body_and_option_labels", function()
  local view = choice_builder.build_choice_view({
    id = 8,
    kind = "remote",
    body = "正文",
    options = {
      { id = 3 },
    },
  }, {
    game = {
      turn = {},
    },
    body_lines_only = true,
  })

  luassert.is.equal("请选择", view.title, "choice view should default missing title")
  luassert.is.equal("", view.body, "body_lines_only should ignore pending.body")
  luassert.is.equal("取消", view.cancel_label, "choice view should default cancel label")
  luassert.is.equal(true, view.allow_cancel, "choice view should allow cancel by default")
  luassert.is.equal("3", view.options[1].label, "choice view should default option label from raw option")
  luassert.is.equal(3, view.options[1].id, "choice view should preserve option id")
end)

it("test_defaults_label_from_plain_string_option", function()
  -- kills _default_option_label 的 "nil" 字符串/type(id)/tostring(opt) 位点:
  -- 无 id 的裸字符串 option 必须以其自身为 label(变异体会产出 "nil" 或 nil)。
  local view = choice_builder.build_choice_view({
    id = 9,
    kind = "remote",
    options = { "路障卡" },
  }, {
    game = {
      turn = {},
    },
  })

  luassert.is.equal("路障卡", view.options[1].label, "a plain string option should be its own label")
  luassert.is.equal("路障卡", view.options[1].id, "a plain string option should carry itself as id")
end)

end)
