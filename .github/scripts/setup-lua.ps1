param([Parameter(Mandatory)][string]$Prefix)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
# 原生 Windows CI 工具链(#126):MSVC 源码构建 Lua 5.4,配 LuaRocks 官方 Windows 二进制。
# 产出 <Prefix>\bin(lua.exe/lua54.dll/luarocks.exe)、include\、lib\lua54.lib,
# 供本脚本预装 rock 时定位 Lua 解释器、头文件与链接库。
# 下载不可达退 3(不可用,重跑),校验/构建失败退 1。
$luaVer = '5.4.7'
$luaSha256 = '9fbf5e28ef86c69858f6d3d34eccc32e911c1a28b4120ff3e84aaa70cfbf1e30'
$rocksVer = '3.12.2'
$rocksSha256 = 'd3f4ddda6926618cadf560170a7c18a5ceead5997ba10832cd0e3b624c7de886'

function Stop-Setup([int]$code, [string]$message) {
  $title = if ($code -eq 3) { "setup UNAVAILABLE (exit 3)" } else { "setup FAILED (exit $code)" }
  if ($env:GITHUB_ACTIONS) { Write-Output "::error title=$title::$message" }
  [Console]::Error.WriteLine("setup-lua: $message")
  exit $code
}

# 网络不可达退 3(重跑可恢复);拿到 HTTP 响应的错(404 等)重跑无用,按真实失败退 1。
function Get-Artifact([string]$url, [string]$out, [string]$sha256) {
  try {
    Invoke-WebRequest -Uri $url -OutFile $out -MaximumRetryCount 3 -RetryIntervalSec 5
  } catch {
    $code = if ($null -ne $_.Exception.Response) { 1 } else { 3 }
    Stop-Setup $code "下载失败:$url ($($_.Exception.Message))"
  }
  if ((Get-FileHash $out -Algorithm SHA256).Hash -ne $sha256) {
    Stop-Setup 1 "sha256 不符:$url"
  }
}

function Invoke-NativeCommand([string]$exe, [string[]]$argv) {
  & $exe @argv
  if ($LASTEXITCODE -ne 0) { Stop-Setup 1 "$exe 退 $LASTEXITCODE" }
}

$Prefix = [IO.Path]::GetFullPath($Prefix)
$work = Join-Path ([IO.Path]::GetTempPath()) "setup-lua-$PID"
foreach ($dir in $work, "$Prefix\bin", "$Prefix\include", "$Prefix\lib") {
  New-Item -ItemType Directory -Force $dir | Out-Null
}
. (Join-Path $PSScriptRoot 'msvc.ps1')

try {
  Get-Artifact "https://www.lua.org/ftp/lua-$luaVer.tar.gz" "$work\lua.tar.gz" $luaSha256
  Get-Artifact "https://luarocks.github.io/luarocks/releases/luarocks-$rocksVer-windows-64.zip" "$work\luarocks.zip" $rocksSha256
  # 钉 Windows 自带 bsdtar:PATH/DevShell 里的 GNU tar 会把 -C 的盘符当远程主机,也解不了 zip。
  $tar = "$env:SystemRoot\System32\tar.exe"
  Invoke-NativeCommand $tar @('-xzf', "$work\lua.tar.gz", '-C', $work)
  Invoke-NativeCommand $tar @('-xf', "$work\luarocks.zip", '-C', $work)

  # 标准 MSVC DLL 构建:lua.c/luac.c 各带 main,先改名避开 *.obj 链进 DLL。
  Push-Location "$work\lua-$luaVer\src"
  try {
    Invoke-NativeCommand cl (@('/nologo', '/MD', '/O2', '/W3', '/c', '/DLUA_BUILD_AS_DLL') + (Get-ChildItem *.c).Name)
    Rename-Item lua.obj lua.o
    Rename-Item luac.obj luac.o
    Invoke-NativeCommand link (@('/nologo', '/DLL', '/IMPLIB:lua54.lib', '/OUT:lua54.dll') + (Get-ChildItem *.obj).Name)
    Invoke-NativeCommand link @('/nologo', '/OUT:lua.exe', 'lua.o', 'lua54.lib')
    Copy-Item lua.exe, lua54.dll "$Prefix\bin"
    Copy-Item lua54.lib "$Prefix\lib"
    Copy-Item lua.h, luaconf.h, lualib.h, lauxlib.h, lua.hpp "$Prefix\include"
  } finally {
    Pop-Location
  }
  Copy-Item "$work\luarocks-$rocksVer-windows-64\*.exe" "$Prefix\bin"
  Invoke-NativeCommand "$Prefix\bin\lua.exe" @('-v')
} finally {
  Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}

# runner 的 PATH 上有 MinGW gcc,luarocks 会探测到它而与 MSVC 构建的 lua54.lib 混用;
# 显式钉 MSVC 工具链,由 LUAROCKS_CONFIG 指向。
$config = "$Prefix\luarocks-config.lua"
Set-Content -Encoding ascii $config @'
variables = { CC = "cl", LD = "link", AR = "lib", RC = "rc", MT = "mt" }
'@
# 受控 Lua 环境(#151):测试与质量工具只从机器 LuaRocks tree 解析、仓内不再自举安装,
# 所以 CI 在这里把五个钉定 rock 预装进默认 tree。失败分类沿用本脚本口径:
# 下载 / 清单不可达退 3(重跑可恢复),编译或其他错误退 1。
$rockPins = @(
  'busted 2.3.0-1',
  'luassert 1.9.0-1',
  'luacov 0.17.0-1',
  'luacov-reporter-lcov 0.2-0',
  'luacheck 1.2.0-1'
)
$env:LUAROCKS_CONFIG = $config
$env:PATH = "$Prefix\bin;$env:PATH"
foreach ($pin in $rockPins) {
  $name, $ver = $pin -split ' '
  $out = & "$Prefix\bin\luarocks.exe" --lua-version 5.4 install $name $ver 2>&1
  if ($LASTEXITCODE -ne 0) {
    $text = ($out | Out-String)
    $code = if ($text -match 'Failed downloading|Failed searching manifest|timed out|Could not connect') { 3 } else { 1 }
    Stop-Setup $code "安装 $name $ver 失败: $text"
  }
}

if ($env:GITHUB_PATH -and $env:GITHUB_ENV) {
  Add-Content -Encoding utf8 $env:GITHUB_PATH "$Prefix\bin"
  Add-Content -Encoding utf8 $env:GITHUB_ENV "LUAROCKS_CONFIG=$config"
}
exit 0
