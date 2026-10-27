# Builds the chain core.
# Android: c-shared library (.so) via flclash wrapper
# Windows: standalone executable (.exe) via native mihomo

param(
    [string]$Platform = 'android',
    [string[]]$Abi = @('arm64-v8a', 'x86_64', 'armeabi-v7a')
)

$ErrorActionPreference = 'Stop'

function Get-MinGWToolchain {
    $candidateDirs = @(
        'C:\ProgramData\chocolatey\bin',
        'C:\ProgramData\chocolatey\lib\mingw\tools\install\mingw64\bin',
        'C:\ProgramData\mingw64\mingw64\bin',
        'C:\tools\mingw64\bin',
        'C:\msys64\mingw64\bin',
        'C:\msys64\usr\bin',
        'C:\mingw64\bin',
        'C:\mingw\bin'
    )

    foreach ($dir in $candidateDirs) {
        if (-not $dir -or -not (Test-Path $dir)) { continue }

        $gcc = Join-Path $dir 'x86_64-w64-mingw32-gcc.exe'
        if (Test-Path $gcc) {
            $gpp = Join-Path $dir 'x86_64-w64-mingw32-g++.exe'
            $ar  = Join-Path $dir 'ar.exe'
            return @{
                BinDir = $dir
                CC     = $gcc
                CXX    = if (Test-Path $gpp) { $gpp } else { $null }
                AR     = if (Test-Path $ar) { $ar } else { $null }
            }
        }

        $gcc = Join-Path $dir 'gcc.exe'
        if (Test-Path $gcc) {
            return @{
                BinDir = $dir
                CC     = $gcc
                CXX    = $null
                AR     = $null
            }
        }
    }

    throw "No usable MinGW toolchain found for windows/amd64 build."
}

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

    $toolchain = Get-MinGWToolchain
    $env:PATH = "$($toolchain.BinDir);$env:PATH"

    $env:CC = $toolchain.CC
    if ($toolchain.CXX) { $env:CXX = $toolchain.CXX }
    if ($toolchain.AR)  { $env:AR = $toolchain.AR }

    $env:CGO_ENABLED = '1'
    $env:GOOS = 'windows'
    $env:GOARCH = 'amd64'

    Write-Host "Using compiler: $env:CC" -ForegroundColor Green
    & $env:CC --version

    $dir = Join-Path $out 'windows' 'amd64'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $exe = Join-Path $dir 'auroravpn-core.exe'

    Push-Location $metaDir
    try {
        Write-Host "Running: go build -tags='with_gvisor' -trimpath -ldflags='-s -w -X github.com/metacubex/mihomo/constant.Version=AuroraVPN' -o $exe ." -ForegroundColor Cyan
        go build -tags="with_gvisor" -trimpath -ldflags="-s -w -X 'github.com/metacubex/mihomo/constant.Version=AuroraVPN'" -o $exe .
        if ($LASTEXITCODE -ne 0) { throw "go build failed for windows" }

        $mb = [math]::Round((Get-Item $exe).Length / 1MB, 1)
        Write-Host "  -> $exe  ($mb MB)" -ForegroundColor Green
    }
    finally {
        Pop-Location
        Remove-Item Env:GOFLAGS, Env:CGO_ENABLED, Env:GOOS, Env:GOARCH, Env:CC, Env:CXX, Env:AR -ErrorAction SilentlyContinue
    }

    Write-Host ""
    Write-Host "built: windows/amd64 (auroravpn-core.exe)" -ForegroundColor Green
    return
}

# Android stub retained for compatibility.
Write-Host "Platform not set to windows; no-op for this script." -ForegroundColor Yellow
