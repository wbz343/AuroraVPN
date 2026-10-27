# Builds the pluggable transports as executables.
#
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
    New-Item -ItemType Directory -Force -Path $dir | Out-Null

    foreach ($transport in $Transports) {
        $src = Join-Path $here "third_party/$($transport.Source)"
        $exe = Join-Path $dir "$($transport.Name).exe"

        Push-Location $src
        try {
            $env:GOFLAGS = '-mod=mod'
            $env:CGO_ENABLED = '0' # 纯 Go 编译，避免 MinGW 依赖问题
            $env:GOOS = 'windows'
            $env:GOARCH = 'amd64'

            Write-Host "building $($transport.Name) for windows/amd64 ..." -ForegroundColor Cyan
            
            # 🚨 关键修复：移除了 -checklinkname=0，因为这是 Android 专属的 hack，Windows 不需要且会导致 linker 报错
            $buildOutput = go build -trimpath -ldflags="-w -s" -o $exe $transport.Package 2>&1
            
            if ($LASTEXITCODE -ne 0) { 
                Write-Host "=== Go Build Failed Output ===" -ForegroundColor Red
                Write-Host $buildOutput -ForegroundColor Red
                Write-Host "==============================" -ForegroundColor Red
                throw "go build failed for $($transport.Name) on windows. See detailed output above." 
            }
        } finally {
            Pop-Location
            Remove-Item Env:GOFLAGS, Env:CGO_ENABLED, Env:GOOS, Env:GOARCH -ErrorAction SilentlyContinue
        }

        $mb = [math]::Round((Get-Item $exe).Length / 1MB, 1)
        Write-Host "  -> $exe  ($mb MB)" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "built: windows/amd64" -ForegroundColor Green
    return # Windows 构建完成，直接退出
}

# ==========================================================
# ANDROID BUILD PATH (原有逻辑，保持不变)
# ==========================================================
if ($Platform -ne 'android') {
    throw "Unknown platform: $Platform. Use 'android' or 'windows'."
}

Write-Host "Building Pluggable Transports for Android..." -ForegroundColor Cyan

$sdk = $env:ANDROID_HOME
if (-not $sdk) { $sdk = $env:ANDROID_SDK_ROOT }
if (-not $sdk) {
    $props = Join-Path (Split-Path -Parent (Split-Path -Parent $here)) 'local.properties'
    if (Test-Path $props) {
        $match = Select-String -Path $props -Pattern 'sdk\.dir\s*=\s*(.+)' | Select-Object -First 1
        if ($match) { $sdk = $match.Matches[0].Groups[1].Value.Trim().Replace('\:', ':') }
    }
}
if (-not $sdk) { $sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk' }

$ndkRoot = Join-Path $sdk 'ndk'
if (-not (Test-Path $ndkRoot)) {
    throw "Android NDK not found under $sdk. Set ANDROID_HOME, or sdk.dir in local.properties."
}
$ndk = (Get-ChildItem $ndkRoot -Directory | Sort-Object Name -Descending)[0].FullName

$hostTag = if ($IsLinux) { 'linux-x86_64' } elseif ($IsMacOS) { 'darwin-x86_64' } else { 'windows-x86_64' }
$bin = Join-Path $ndk "toolchains/llvm/prebuilt/$hostTag/bin"
if (-not (Test-Path $bin)) { throw "NDK toolchain not found for this host: $bin" }
$ext = if ($IsLinux -or $IsMacOS) { '' } else { '.cmd' }

$targets = @{
    'arm64-v8a'   = @{ Arch = 'arm64'; Clang = "aarch64-linux-android26-clang$ext";    Arm = $null }
    'x86_64'      = @{ Arch = 'amd64'; Clang = "x86_64-linux-android26-clang$ext";     Arm = $null }
    'armeabi-v7a' = @{ Arch = 'arm';   Clang = "armv7a-linux-androideabi26-clang$ext"; Arm = '7'  }
}

foreach ($name in $Abi) {
    $spec = $targets[$name]
    if (-not $spec) { throw "unknown ABI: $name" }
    $cc = Join-Path $bin $spec.Clang
    if (-not (Test-Path $cc)) { throw "NDK clang not found: $cc" }

    $dir = Join-Path $out $name
    New-Item -ItemType Directory -Force -Path $dir | Out-Null

    foreach ($transport in $Transports) {
        $src = Join-Path $here "third_party/$($transport.Source)"
        $so = Join-Path $dir "lib$($transport.Name).so"

        Push-Location $src
        try {
            $env:GOFLAGS = '-mod=mod'
            $env:CGO_ENABLED = '1'
            $env:GOOS = 'android'
            $env:GOARCH = $spec.Arch
            $env:CC = $cc
            if ($spec.Arm) { $env:GOARM = $spec.Arm } else { Remove-Item Env:GOARM -ErrorAction SilentlyContinue }

            Write-Host "building $($transport.Name) for $name ..." -ForegroundColor Cyan
            # Android 分支保留原有的 -checklinkname=0，因为它被包裹在 -ldflags 中且针对 Android 是必需的
            go build -buildmode=pie -trimpath -ldflags="-w -s -checklinkname=0" -o $so $transport.Package
            if ($LASTEXITCODE -ne 0) { throw "go build failed for $($transport.Name) on $name" }
        } finally {
            Pop-Location
            Remove-Item Env:GOFLAGS, Env:CGO_ENABLED, Env:GOOS, Env:GOARCH, Env:CC, Env:GOARM -ErrorAction SilentlyContinue
        }

        $mb = [math]::Round((Get-Item $so).Length / 1MB, 1)
        Write-Host "  -> $so  ($mb MB)" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "built: android/$($Abi -join ', ')" -ForegroundColor Green
