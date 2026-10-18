-- 道具使用结果的全量构造器与唯一成功判定器。
-- applier 的合法结果只有三种终态表达:applied / rejected / await_choice;
-- 历史多态形状(true/false/{ok=...}/{waiting=...}/无 ok 表)
-- 一律经 canonicalize 收敛——它是全模块唯一的成功/等待裁决点,
-- waiting 按「非成功、非失败」处理(不广播、不遥测、不消耗)。
local use_result = {}

local RESULT_MT = {}

local function _new(status, fields)
  local value = {
    status = status,
    reason = fields.reason,
    action_anim = fields.action_anim,
    after_action_anim = fields.after_action_anim,
    consumed_by_applier = fields.consumed_by_applier == true,
    choice_spec = fields.choice_spec,
    raw = fields.raw,
  }
  return setmetatable(value, RESULT_MT)
end

local _APPLIED_FIELDS = {
  action_anim = true,
  after_action_anim = true,
  consumed_by_applier = true,
  raw = true,
}

local function _assert_fields(fields, allowed, label)
  for key in pairs(fields) do
    assert(allowed[key] == true, "unexpected " .. label .. " field: " .. tostring(key))
  end
end

function use_result.applied(fields)
  fields = fields or {}
  _assert_fields(fields, _APPLIED_FIELDS, "applied")
  return _new("applied", fields)
end

local _REJECTED_FIELDS = {
  consumed_by_applier = true,
  raw = true,
}

function use_result.rejected(reason, fields)
  assert(type(reason) == "string" and reason ~= "", "rejected requires a stable reason")
  fields = fields or {}
  _assert_fields(fields, _REJECTED_FIELDS, "rejected")
  return _new("rejected", {
    reason = reason,
    consumed_by_applier = fields.consumed_by_applier,
    raw = fields.raw,
  })
end

function use_result.await_choice(choice_spec, fields)
  assert(type(choice_spec) == "table", "await_choice requires a choice_spec table")
  fields = fields or {}
  _assert_fields(fields, { raw = true }, "await_choice")
  return _new("await_choice", {
    choice_spec = choice_spec,
    raw = fields.raw,
  })
end

function use_result.is_result(value)
  return getmetatable(value) == RESULT_MT
end

local function _table_reason(raw, fallback_reason)
  if raw.reason ~= nil then
    return raw.reason
  end
  return fallback_reason or "effect_rejected"
end

-- 非表 raw:唯一的成功字面量是 true,其余(false / nil / 标量)一律 rejected。
local function _canonicalize_scalar(raw, fallback_reason)
  if raw == true then
    return use_result.applied({ raw = raw })
  end
  return use_result.rejected(fallback_reason or "effect_rejected", { raw = raw })
end

local function _canonicalize_waiting(raw)
  local intent = type(raw.intent) == "table" and raw.intent or {}
  local choice_spec = type(intent.choice_spec) == "table" and intent.choice_spec or {}
  return use_result.await_choice(choice_spec, { raw = raw })
end

local function _canonicalize_rejected_table(raw, fallback_reason)
  return use_result.rejected(_table_reason(raw, fallback_reason), {
    consumed_by_applier = raw.item_consumed == true,
    raw = raw,
  })
end

local function _canonicalize_applied_table(raw)
  return use_result.applied({
    action_anim = raw.action_anim,
    after_action_anim = raw.after_action_anim,
    consumed_by_applier = raw.item_consumed == true,
    raw = raw,
  })
end

-- 六种历史 raw 形状的唯一解码点。settlement 只认 canonicalize 的产出;
-- executor/handlers/use_flow_result 里互相矛盾的三个判定器由此取代。
function use_result.canonicalize(raw, fallback_reason)
  if use_result.is_result(raw) then
    return raw
  end
  if type(raw) ~= "table" then
    return _canonicalize_scalar(raw, fallback_reason)
  end
  if raw.waiting == true then
    return _canonicalize_waiting(raw)
  end
  if raw.ok == false then
    return _canonicalize_rejected_table(raw, fallback_reason)
  end
  return _canonicalize_applied_table(raw)
end

return use_result

