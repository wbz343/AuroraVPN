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

function Get-GoModules([string]$dir, [string]$label, [string]$flags) {
    Push-Location $dir
    try {
        if ($flags) { $env:GOFLAGS = $flags }
        foreach ($attempt in 1..3) {
            Write-Host "fetching modules for $label ..." -ForegroundColor Cyan
            go mod download
            if ($LASTEXITCODE -eq 0) { return }
            if ($attempt -eq 3) { throw "go mod download failed for $label" }
            Start-Sleep -Seconds (5 * $attempt)
        }
    } finally {
        Pop-Location
        if ($flags) { Remove-Item Env:GOFLAGS -ErrorAction SilentlyContinue }
    }
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

    Push-Location $metaDir
    try {
        $env:CGO_ENABLED = '1'
        $env:GOOS   = 'windows'
        $env:GOARCH = 'amd64'
        $env:CC     = 'gcc'

        Write-Host "building mihomo for windows/amd64 ..." -ForegroundColor Cyan
        # 编译 mihomo 主程序，启用 TUN 和 Gvisor 支持
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

# ==========================================================
# ANDROID BUILD PATH (保持原有逻辑不变)
# ==========================================================
Write-Host "Building for Android..." -ForegroundColor Cyan
Get-GoModules $core 'the exit chain engine' ''

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
if (-not (Test-Path $ndkRoot)) { throw "Android NDK not found under $sdk." }
$ndk = (Get-ChildItem $ndkRoot -Directory | Sort-Object Name -Descending)[0].FullName

$hostTag = if ($IsLinux) { 'linux-x86_64' } elseif ($IsMacOS) { 'darwin-x86_64' } else { 'windows-x86_64' }
$bin = Join-Path $ndk "toolchains/llvm/prebuilt/$hostTag/bin"
if (-not (Test-Path $bin)) { throw "NDK toolchain not found for this host: $bin" }
$ext = if ($IsLinux -or $IsMacOS) { '' } else { '.cmd' }

$targets = @{
    'arm64-v8a'   = @{ Arch = 'arm64'; Clang = "aarch64-linux-android26-clang$ext"; Arm = $null }
    'x86_64'      = @{ Arch = 'amd64'; Clang = "x86_64-linux-android26-clang$ext";  Arm = $null }
    'armeabi-v7a' = @{ Arch = 'arm';   Clang = "armv7a-linux-androideabi26-clang$ext"; Arm = '7' }
}

Push-Location $core
try {
    foreach ($name in $Abi) {
        $spec = $targets[$name]
        $cc = Join-Path $bin $spec.Clang
        $dir = Join-Path $out $name
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $so = Join-Path $dir 'libwhiteaestherchain.so'

        $env:CGO_ENABLED = '1'
        $env:GOOS   = 'android'
        $env:GOARCH = $spec.Arch
        $env:CC     = $cc
        if ($spec.Arm) { $env:GOARM = $spec.Arm } else { Remove-Item Env:GOARM -ErrorAction SilentlyContinue }

        Write-Host "building $name ..." -ForegroundColor Cyan
        go build -tags=with_gvisor -buildmode=c-shared -trimpath -ldflags="-w -s -extldflags=-Wl,-z,max-page-size=16384" -o $so .
        if ($LASTEXITCODE -ne 0) { throw "go build failed for $name" }
        $mb = [math]::Round((Get-Item $so).Length / 1MB, 1)
        Write-Host "  -> $so  ($mb MB)" -ForegroundColor Green
    }
} finally {
    Pop-Location
    Remove-Item Env:CGO_ENABLED, Env:GOOS, Env:GOARCH, Env:CC, Env:GOARM -ErrorAction SilentlyContinue
}
Write-Host "built: android/$($Abi -join ', ')" -ForegroundColor Green
