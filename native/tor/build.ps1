# Builds the pluggable transports as executables.
#
# Usage:
#   Android: pwsh -File native/tor/build.ps1 -Platform android -Abi arm64-v8a,x86_64,armeabi-v7a
#   Windows: pwsh -File native/tor/build.ps1 -Platform windows
#
# Android Note: They are executables, not libraries, but named lib*.so anyway.
# That is not a disguise: Android only extracts and marks executable the files 
# under lib/<abi>/ that end in .so.
#
# Windows Note: Outputs standard .exe files, no .so disguise needed.

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

function Get-GoModules([string]$dir, [string]$label, [string]$flags) {
    Push-Location $dir
    try {
        if ($flags) { $env:GOFLAGS = $flags }
        foreach ($attempt in 1..3) {
            Write-Host "fetching modules for $label ..." -ForegroundColor Cyan
            go mod download
            if ($LASTEXITCODE -eq 0) { return }
            if ($attempt -eq 3) { throw "go mod download failed for $label" }
            Write-Host "  download failed, retrying ($attempt/3) ..." -ForegroundColor Yellow
            Start-Sleep -Seconds (5 * $attempt)
        }
    } finally {
        Pop-Location
        if ($flags) { Remove-Item Env:GOFLAGS -ErrorAction SilentlyContinue }
    }
}

foreach ($transport in $Transports) {
    Get-GoModules (Join-Path $here "third_party/$($transport.Source)") $transport.Name '-mod=mod'
}

# ==========================================================
# WINDOWS BUILD PATH
# ==========================================================
if ($Platform -eq 'windows') {
    Write-Host "Building Pluggable Transports for Windows (amd64)..." -ForegroundColor Cyan
    
    $dir = Join-Path $out 'windows' 'amd64'
    New-Item -ItemType Directory -Force -Path $
