local constants = require("src.config.content.constants")
local number_utils = require("src.foundation.number")

-- 运行资产目录校验器由装配侧注入(#328):config_sanity 只声明「需要一份目录校验
-- 结果」,不反向依赖 config.runtime_assets——拆 config.gameplay ↔ runtime_assets
-- 投影环,依赖方向单一化(config → runtime_assets)。注入的校验器返回
-- validate_catalog 同款结果表 {ok=bool, errors={...}};未注入时跳过目录校验
-- (目录校验是装配侧职责)。
local runtime_asset_validator = nil

local config_sanity = {}

local validated = false

function config_sanity.configure_runtime_asset_validator(validator)
  runtime_asset_validator = validator
end

-- 税率的取值域是配置的不变量,不是结算代码的:tax_rules 依赖 (0, 1] 才能保证
-- floor(cash * rate) 不超过余额,进而让「本次税额」与实际扣款一致。
-- 把这条约束钉在配置边界上,结算侧就不必再写不可达的兜底钳制。
local function _validate_tax_rate()
  local rate = constants.tax_rate
  if number_utils.is_numeric(rate) and rate > 0 and rate <= 1 then
    return
  end
  error("tax_rate must be a number in (0, 1]; got " .. tostring(rate), 0)
end

-- 取校验结果的第一个错误消息:无 errors 表或无消息时回落通用文案。
local function _first_error_message(result)
  local first = result.errors and result.errors[1] or nil
  return (first and first.message) or "runtime asset catalog invalid"
end

local function _validate_runtime_assets()
  if runtime_asset_validator == nil then
    return
  end
  local result = runtime_asset_validator()
  if result.ok == true then
    return
  end
  error(_first_error_message(result), 0)
end

function config_sanity.validate()
  if validated then
    return true
  end
  _validate_tax_rate()
  _validate_runtime_assets()
  validated = true
  return true
end

function config_sanity.reset_for_tests()
  validated = false
end

return config_sanity

