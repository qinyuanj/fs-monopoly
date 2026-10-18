# 把 MSVC x64 工具链载入当前 PowerShell 会话(#126);须 dot-source:`. .github/scripts/msvc.ps1`。
# setup-lua.ps1 构建 Lua 与预装 C rock(luafilesystem/luasystem 等)需要它;
# ci-verify.ps1 也载入同一环境,verify 只核对受控 Lua tree 并装载依赖。
$previousErrorAction = $ErrorActionPreference
try {
  $ErrorActionPreference = 'Stop'
  $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
  $vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  if (-not $vs) { throw 'MSVC x64 toolset not found via vswhere' }
  # vsdevcmd 自己按 PATH 找 vswhere。
  $env:PATH = "$env:PATH;$(Split-Path $vswhere)"
  Import-Module (Join-Path $vs 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll')
  Enter-VsDevShell -VsInstallPath $vs -SkipAutomaticLocation -DevCmdArguments '-arch=x64 -host_arch=x64' | Out-Null
} finally {
  $ErrorActionPreference = $previousErrorAction
}
