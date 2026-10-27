# Builds the chain core.
# Android: c-shared library (.so) via flclash wrapper
# Windows: standalone executable (.exe) via native mihomo

param(
    [string]$Platform = 'android',
    [string[]]$Abi = @('arm64-v8a', 'x86_64', 'armeabi-v7a')
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$core = Join-Path $here 'third_party/flclash/core'
$out  = Join-Path $here 'build'

if (-not (Test-Path (Join-Path $core 'go.mod'))) {
    throw "core missing. Run native/chain/setup.ps1 first."
}

# ==========================================================
# WINDOWS BUILD PATH: Compile standalone mihomo executable
# ==========================================================
if ($Platform -eq 'windows') {
    Write-Host "Building Core for Windows (amd64 standalone exe)..." -ForegroundColor Cyan

    $metaDir = Join-Path $core 'Clash.Meta'
    if (-not (Test-Path (Join-Path $metaDir 'go.mod'))) {
        throw "Clash.Meta (mihomo) source missing. Run setup.ps1 first."
    }

    $dir = Join-Path $out 'windows' 'amd64'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $exe = Join-Path $dir 'auroravpn-core.exe'

    $gcc = Get-Command gcc -ErrorAction Stop
    $env:CC = $gcc.Source
    $env:CGO_ENABLED = '1'
    $env:GOOS = 'windows'
    $env:GOARCH = 'amd64'

    Write-Host "Using gcc: $env:CC"

    Push-Location $metaDir
    try {
        go build -tags="with_gvisor" -trimpath -ldflags="-s -w -X 'github.com/metacubex/mihomo/constant.Version=AuroraVPN'" -o $exe .
        if ($LASTEXITCODE -ne 0) { throw "go build failed for windows" }

        $mb = [math]::Round((Get-Item $exe).Length / 1MB, 1)
        Write-Host "  -> $exe  ($mb MB)" -ForegroundColor Green
    } finally {
        Pop-Location
        Remove-Item Env:CGO_ENABLED, Env:GOOS, Env:GOARCH, Env:CC -ErrorAction SilentlyContinue
    }

    Write-Host ""
    Write-Host "built: windows/amd64 (auroravpn-core.exe)" -ForegroundColor Green
    return
}
