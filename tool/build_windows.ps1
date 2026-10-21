# 在 Windows 上构建 sidecar + Flutter release。
# 未在 CI/虚拟机外验证；签名（Authenticode）与安装器不在本脚本内。
param(
  [string]$CoreRepo = "",
  [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($CoreRepo)) {
  $CoreRepo = Join-Path $Root "third_party\encry-immortals"
}
if (-not (Test-Path $CoreRepo)) {
  throw "找不到核心仓库：$CoreRepo；设置 -CoreRepo 或放到 third_party\encry-immortals"
}

$OutDir = Join-Path $Root "build\core\windows"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$Version = (& git -C $CoreRepo describe --tags --always --dirty 2>$null)
if ([string]::IsNullOrWhiteSpace($Version)) { $Version = "0.0.0-dev" }
$Version = $Version.Trim()

Push-Location $CoreRepo
try {
  $env:CGO_ENABLED = "0"
  $env:GOOS = "windows"
  $env:GOARCH = "amd64"
  go build -trimpath -ldflags "-s -w -X main.version=$Version" `
    -o (Join-Path $OutDir "eimmortal.exe") ./cmd/eimmortal
  go build -trimpath -ldflags "-s -w -H windowsgui -X main.version=$Version" `
    -o (Join-Path $OutDir "eimmortal-gui.exe") ./cmd/eimmortal
} finally {
  Pop-Location
}

# 若要对 sidecar 做 Authenticode 签名，必须在这里先签名、再计算哈希；
# 签名会改写 PE，先算哈希会导致 release 运行时校验失败。
$GuiBinary = Join-Path $OutDir "eimmortal-gui.exe"
$Hash = (Get-FileHash -Algorithm SHA256 $GuiBinary).Hash.ToLower()

Push-Location $Root
try {
  flutter --no-version-check build windows --release `
    --dart-define=EIMMORTAL_CORE_SHA256=$Hash
} finally {
  Pop-Location
}

$AppDir = Join-Path $Root "build\windows\x64\runner\$Configuration"
$BinDir = Join-Path $AppDir "bin"
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
Copy-Item $GuiBinary (Join-Path $BinDir "eimmortal-gui.exe") -Force
Copy-Item (Join-Path $OutDir "eimmortal.exe") (Join-Path $BinDir "eimmortal.exe") -Force
Set-Content -Path (Join-Path $AppDir "core-build.txt") -Value "$Version`n$Hash"

Write-Host "app: $AppDir"
Write-Host "core version: $Version"
Write-Host "core sha256: $Hash"
Write-Host "提示：发布前需对 exe 与安装器做 Authenticode 签名，并在 Windows 上实测 GUI 子系统 stdio。"
