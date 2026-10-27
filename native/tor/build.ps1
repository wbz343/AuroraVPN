# Builds the pluggable transports as executables.
# Usage:
#   Android: pwsh -File native/tor/build.ps1 -Platform android -Abi arm64-v8a,x86_64,armeabi-v7a
#   Windows: pwsh -File native/tor/build.ps1 -Platform windows

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
$out = Join-Path $here 'build'

$Transports = @(
    @{ Name = 'lyrebird';  Source = 'lyrebird';  Package = './cmd/lyrebird' }
    @{ Name = 'snowflake'; Source = 'snowflake'; Package = './client' }
)

foreach ($transport in $Transports) {
    $src = Join-Path $here "third_party/$($transport.Source)"
    if (-not (Test-Path (Join-Path $src 'go.mod'))) {
        throw "$($transport.Source) missing. Run native/tor/setup.ps1 first."
    }
}

# ==========================================================
# WINDOWS BUILD PATH
# ==========================================================
if ($Platform -eq 'windows') {
    Write-Host "Building Pluggable Transports for Windows (amd64)..." -ForegroundColor Cyan

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

    foreach ($transport in $Transports) {
        $src = Join-Path $here "third_party/$($transport.Source)"
        $exe = Join-Path $dir "$($transport.Name).exe"

        Push-Location $src
        try {
            $env:GOFLAGS = '-mod=mod'
            Write-Host "building $($transport.Name) for windows/amd64 ..." -ForegroundColor Cyan
            $buildOutput = go build -trimpath -ldflags="-w -s" -o $exe $transport.Package 2>&1

            if ($LASTEXITCODE -ne 0) {
                Write-Host "=== Go Build Failed Output ===" -ForegroundColor Red
                Write-Host $buildOutput -ForegroundColor Red
                Write-Host "==============================" -ForegroundColor Red
                throw "go build failed for $($transport.Name) on windows. See detailed output above."
            }
        }
        finally {
            Pop-Location
            Remove-Item Env:GOFLAGS, Env:CGO_ENABLED, Env:GOOS, Env:GOARCH, Env:CC, Env:CXX, Env:AR -ErrorAction SilentlyContinue
        }

        $mb = [math]::Round((Get-Item $exe).Length / 1MB, 1)
        Write-Host "  -> $exe  ($mb MB)" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "built: windows/amd64" -ForegroundColor Green
    return
}

Write-Host "Platform not set to windows; no-op for this script." -ForegroundColor Yellow
