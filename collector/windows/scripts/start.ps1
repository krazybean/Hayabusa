[CmdletBinding()]
param(
    [string]$CollectorRoot = "$env:ProgramData\HayabusaCollector",
    [string]$VectorConfigPath,
    [string]$VectorExePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "[hayabusa-collector] $Message"
}

function Find-VectorExe {
    param([string]$CollectorRootPath)

    $candidates = @(
        $VectorExePath,
        (Join-Path $CollectorRootPath "bin\vector.exe"),
        (Get-Command vector.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
        "$env:ProgramFiles\Vector\bin\vector.exe",
        "$env:ProgramFiles\Vector\vector.exe"
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    return $candidates | Select-Object -First 1
}

if ([string]::IsNullOrWhiteSpace($VectorConfigPath)) {
    $VectorConfigPath = Join-Path (Join-Path $CollectorRoot "config") "vector.toml"
}

if (-not (Test-Path -LiteralPath $VectorConfigPath)) {
    throw "Vector config not found: $VectorConfigPath"
}

$vectorExe = Find-VectorExe -CollectorRootPath $CollectorRoot
if (-not $vectorExe) {
    throw "vector.exe not found. Install Vector or place vector.exe in $CollectorRoot\bin."
}

$logDir = Join-Path $CollectorRoot "logs"
$runDir = Join-Path $CollectorRoot "run"
$pidPath = Join-Path $runDir "vector.pid"
$stdoutPath = Join-Path $logDir "vector.stdout.log"
$stderrPath = Join-Path $logDir "vector.stderr.log"
$debugPath = Join-Path $logDir "windows-auth-normalized.jsonl"

foreach ($path in @($logDir, $runDir)) {
    New-Item -ItemType Directory -Force -Path $path | Out-Null
}

if (Test-Path -LiteralPath $pidPath) {
    $existingPid = Get-Content -LiteralPath $pidPath -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($existingPid) {
        $existingProcess = Get-Process -Id $existingPid -ErrorAction SilentlyContinue
        if ($existingProcess) {
            Write-Warning "Vector already appears to be running with PID $existingPid."
            Write-Host "Use stop.ps1 first if you want to restart it."
            return
        }
    }
}

Write-Step "Starting Vector in the background."
$process = Start-Process `
    -FilePath $vectorExe `
    -ArgumentList @("--config", $VectorConfigPath) `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath `
    -PassThru

Set-Content -LiteralPath $pidPath -Value $process.Id -Encoding ASCII

Write-Host "  PID         : $($process.Id)"
Write-Host "  Config      : $VectorConfigPath"
Write-Host "  Stdout log  : $stdoutPath"
Write-Host "  Stderr log  : $stderrPath"
Write-Host "  Debug events: $debugPath"
Write-Host "  Stop with   : .\stop.ps1 -CollectorRoot `"$CollectorRoot`""
