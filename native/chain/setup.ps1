# Fetches the Go core that carries mihomo, and patches it.
# Supports both Android (c-shared wrapper) and Windows (standalone executable).

param([switch]$Force)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

$CoreRepo = 'https://github.com/chen08209/FlClash.git'
$CoreRev  = '62addf738a76b1a492e19af2dbabdb6d572b9e72'
$MetaRepo = 'https://github.com/chen08209/Clash.Meta.git'
$MetaRev  = '80362fc1895dcf60b79b562896653046e0687413'

$ThirdParty = Join-Path $here 'third_party'
$Clone = Join-Path $ThirdParty 'flclash'
$CoreSrc = Join-Path $Clone 'core'

if ($Force -and (Test-Path $ThirdParty)) {
    Write-Host "removing existing third_party/" -ForegroundColor Yellow
    Remove-Item $ThirdParty -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $ThirdParty | Out-Null

if (-not (Test-Path (Join-Path $CoreSrc 'go.mod'))) {
    Write-Host "fetching the core (sparse, blobless)..." -ForegroundColor Cyan
    if (Test-Path $Clone) { Remove-Item $Clone -Recurse -Force }
    git clone --filter=blob:none --sparse $CoreRepo $Clone 2>&1 | Out-Null
    Push-Location $Clone
    git sparse-checkout set core 2>&1 | Out-Null
    git checkout --quiet $CoreRev 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Pop-Location; throw "could not check out core $CoreRev" }
    Pop-Location
    Write-Host "  -> native/chain/third_party/flclash/core @ $($CoreRev.Substring(0,12))" -ForegroundColor Green
} else {
    Write-Host "core already present" -ForegroundColor Cyan
}

$Meta = Join-Path $CoreSrc 'Clash.Meta'
if (-not (Test-Path (Join-Path $Meta 'go.mod'))) {
    Write-Host "fetching Clash.Meta (mihomo)..." -ForegroundColor Cyan
    if (Test-Path $Meta) { Remove-Item $Meta -Recurse -Force }
    git clone --filter=blob:none $MetaRepo $Meta 2>&1 | Out-Null
    Push-Location $Meta
    git checkout --quiet $MetaRev 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Pop-Location; throw "could not check out Clash.Meta $MetaRev" }
    Pop-Location
    Write-Host "  -> core/Clash.Meta @ $($MetaRev.Substring(0,12))" -ForegroundColor Green
}

# Apply REALITY patch if exists
$Patch = Join-Path $here 'patches/0001-reality-client-version.patch'
if (Test-Path $Patch) {
    Push-Location $Meta
    $already = git apply --reverse --check $Patch 2>$null; $ok = $?
    if ($ok) {
        Write-Host "REALITY patch already applied" -ForegroundColor Cyan
    } else {
        git apply $Patch
        Write-Host "REALITY patch applied" -ForegroundColor Green
    }
    Pop-Location
}

Write-Host "`ncore ready." -ForegroundColor Green

# Reconcile modules for the wrapper (Android)
Write-Host "reconciling wrapper modules..." -ForegroundColor Cyan
Push-Location $CoreSrc
try {
    $env:GOFLAGS = '-mod=mod'
    go mod tidy
} finally {
    Pop-Location
    Remove-Item Env:GOFLAGS -ErrorAction SilentlyContinue
}

Write-Host "Setup complete. Use build.ps1 to compile." -ForegroundColor Green
