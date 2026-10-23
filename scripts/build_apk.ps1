# 在 Windows 上打包 Android APK。
#
# 背景：Flutter 的 AOT 快照器（gen_snapshot）无法处理含非 ASCII 字符的工程路径，
# 而本工程位于 C:\Users\王\... 下，直接在原地 `flutter build apk --release` 会报
# “Unable to read file: ...app.dill”。因此这里先把源码镜像到一个纯 ASCII 的
# 路径（默认 C:\DevTools\pk_sim_build）再打包，最后把 APK 拷回本工程的 build 目录。

param(
  [string]$Mirror = 'C:\DevTools\pk_sim_build'
)

$ErrorActionPreference = 'Stop'
$src = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$apkSrc = Join-Path $Mirror 'build\app\outputs\flutter-apk\app-release.apk'
$apkDstDir = Join-Path $src 'build\app\outputs\flutter-apk'

Write-Host "镜像源码: $src -> $Mirror"
if (Test-Path $Mirror) { Remove-Item $Mirror -Recurse -Force }
& robocopy $src $Mirror /E /XD build .dart_tool .git .idea /NFL /NDL /NJH /NJS /NP | Out-Null

Push-Location $Mirror
try {
  & flutter build apk --release
  if ($LASTEXITCODE -ne 0) { throw "flutter build apk 失败，退出码 $LASTEXITCODE" }
} finally {
  Pop-Location
}

New-Item -ItemType Directory -Force $apkDstDir | Out-Null
Copy-Item $apkSrc (Join-Path $apkDstDir 'app-release.apk') -Force
Write-Host "APK: $(Join-Path $apkDstDir 'app-release.apk')"
