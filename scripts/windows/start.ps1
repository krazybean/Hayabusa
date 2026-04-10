[CmdletBinding()]
param(
    [string]$CollectorRoot = "$env:ProgramData\HayabusaCollector"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Fail {
    param([string]$Message)
    throw $Message
}

$binDir = Join-Path $CollectorRoot "bin"
$configPath = Join-Path (Join-Path $CollectorRoot "config") "vector.toml"
$logsDir = Join-Path $CollectorRoot "logs"
$runDir = Join-Path $CollectorRoot "run"
$vectorExe = Join-Path $binDir "vector.exe"
$pidPath = Join-Path $runDir "vector.pid"
$stdoutPath = Join-Path $logsDir "vector.stdout.log"
$stderrPath = Join-Path $logsDir "vector.stderr.log"

foreach ($dir in @($logsDir, $runDir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

if (-not (Test-Path -LiteralPath $vectorExe)) {
    Fail "vector.exe not found at $vectorExe"
}

if (-not (Test-Path -LiteralPath $configPath)) {
    Fail "Vector config not found at $configPath"
}

Set-Content -LiteralPath $pidPath -Value $PID -Encoding ASCII
Write-Host "Hayabusa Collector started successfully"
Write-Host "Config: $configPath"
Write-Host "Stdout: $stdoutPath"
Write-Host "Stderr: $stderrPath"

$process = Start-Process `
    -FilePath $vectorExe `
    -ArgumentList @("--config", $configPath) `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath `
    -PassThru `
    -Wait

exit $process.ExitCode
