# Builds the pluggable transports as executables.
# Usage:
#   Android: pwsh -File native/tor/build.ps1 -Platform android -Abi arm64-v8a,x86_64,armeabi-v7a
#   Windows: pwsh -File native/tor/build.ps1 -Platform windows

param(
    [string]$Platform = 'android',
    [string[]]$Abi = @('arm64-v8a', 'x86_64', 'armeabi-v7a')
)

$ErrorActionPreference = 'Stop'
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

    $dir = Join-Path $out 'windows' 'amd64'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null

    $gcc = Get-Command gcc -ErrorAction Stop
    $env:CC = $gcc.Source
    $env:CGO_ENABLED = '1'
    $env:GOOS = 'windows'
    $env:GOARCH = 'amd64'

    Write-Host "Using gcc: $env:CC"

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
        } finally {
            Pop-Location
            Remove-Item Env:GOFLAGS, Env:CGO_ENABLED, Env:GOOS, Env:GOARCH, Env:CC -ErrorAction SilentlyContinue
        }

        $mb = [math]::Round((Get-Item $exe).Length / 1MB, 1)
        Write-Host "  -> $exe  ($mb MB)" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "built: windows/amd64" -ForegroundColor Green
    return
}
