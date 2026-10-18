# CI 入口(#126):载入 MSVC 后跑 `lua tools/cli.lua verify @args`,按退出码出 annotation。
# 0 通过;3 = 平台或工具不可用(status=unavailable),先查环境再重跑;
# 其余(1 真实失败 / 2 用法错误)为真实红灯。退出码原样透传,job 结论与 verify 一致。
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
. (Join-Path $PSScriptRoot 'msvc.ps1')
$label = (@('verify') + $args) -join ' '
lua tools/cli.lua verify @args
$rc = $LASTEXITCODE
switch ($rc) {
  0 { $line = "${label}:通过" }
  3 {
    Write-Output "::error title=$label UNAVAILABLE (exit 3)::平台或工具不可用(status=unavailable),不是测试回归;请检查环境后重跑 job。"
    $line = "${label}:**UNAVAILABLE**(exit 3)— 平台或工具不可用,请检查环境后重跑 job,不要当测试回归排查。"
  }
  default {
    Write-Output "::error title=$label FAILED (exit $rc)::真实失败;按日志里的 [verify] FAIL <lane> 行下钻。"
    $line = "${label}:**FAILED**(exit $rc)— 真实失败,按 ``[verify] FAIL <lane>`` 行下钻。"
  }
}
if ($env:GITHUB_STEP_SUMMARY) { Add-Content -Encoding utf8 $env:GITHUB_STEP_SUMMARY $line }
exit $rc
