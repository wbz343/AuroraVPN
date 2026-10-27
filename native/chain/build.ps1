# Builds the chain core into one shared library per ABI/Platform.
#
# Usage:
#   Android: pwsh -File native/chain/build.ps1 -Platform android -Abi arm64-v8a,x86_64,armeabi-v7a
#   Windows: pwsh -File native/chain/build.ps1 -Platform windows
#
# ONE Go library in the process, and that is a requirement rather than a
# simplification. Two -buildmode=c-shared libraries are two Go runtimes exporting
# the same runtime symbols into one linker namespace; a call binding to the wrong
# copy enters a runtime that has never heard of the calling goroutine.

param(
    [string]$Platform = 'android',
    [string[]]$Abi = @('arm64-v8a', 'x86_64', 'armeabi-v7a')
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$core = Join-Path $here 'third_party/flclash/core' # 保持你原有的路径
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
            Write-Host "  download failed, retrying ($attempt/3) ..." -ForegroundColor Yellow
            Start-Sleep -Seconds (5 * $attempt)
        }
    } finally {
        Pop-Location
        if ($flags) { Remove-Item Env:GOFLAGS -ErrorAction SilentlyContinue }
    }
}

Get-GoModules $core 'the exit chain engine' ''

# ==========================================================
# WINDOWS BUILD PATH
# ==========================================================
if ($Platform -eq 'windows') {
    Write-Host "Building for Windows (amd64)..." -ForegroundColor Cyan
    
    $dir = Join-Path $out 'windows' 'amd64'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $dll = Join-Path $dir 'whiteaestherchain.dll'

    $env:CGO_ENABLED = '1'
    $env:GOOS   = 'windows'
    $env:GOARCH = 'amd64'
    # Windows 下 CGO 默认使用 gcc (MinGW-w64)。确保 CI 或本地环境已安装 mingw。
    $env:CC     = 'gcc' 

    Push-Location $core
    try {
        Write-Host "building windows/amd64 ..." -ForegroundColor Cyan
        # 注意：移除了 Android 特有的 -Wl,-z,max-page-size=16384，这在 Windows 链接器中无效
        go build -tags=with_gvisor -buildmode=c-shared -trimpath -ldflags="-w -s" -o $dll .
        if ($LASTEXITCODE -ne 0) { throw "go build failed for windows" }
        
        $mb = [math]::Round((Get-Item $dll).Length / 1MB, 1)
        Write-Host "  -> $dll  ($mb MB)" -ForegroundColor Green
    } finally {
        Pop-Location
        Remove-Item Env:CGO_ENABLED, Env:GOOS, Env:GOARCH, Env:CC -ErrorAction SilentlyContinue
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

Write-Host "Building for Android..." -ForegroundColor Cyan

$sdk = $env:ANDROID_HOME
if (-not $sdk) { $sdk = $env:ANDROID_SDK_ROOT }
if (-not $sdk) {
    $props = Join-Path (Split-Path -Parent (Split-Path -Parent $here)) 'local.properties'
    if (Test-Path $props) {
        $match = Select-String -Path $props -Pattern 'sdk\.dir\s*=\s*(.+)' | Select-Object -First 1
        if ($match) {
            $sdk = $match.Matches[0].Groups[1].Value.Trim()
            $sdk = $sdk.Replace('\', '\').Replace('\:', ':')
        }
    }
}
if (-not $sdk) { $sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk' }

$ndkRoot = Join-Path $sdk 'ndk'
if (-not (Test-Path $ndkRoot)) {
    throw "Android NDK not found under $sdk. Set ANDROID_HOME, or sdk.dir in local.properties."
}
$ndk = (Get-ChildItem $ndkRoot -Directory | Sort-Object Name -Descending)[0].FullName

$
