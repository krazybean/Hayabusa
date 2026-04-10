[CmdletBinding()]
param(
    [string]$CollectorRoot = "$env:ProgramData\HayabusaCollector"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "[hayabusa-collector] $Message"
}

$pidPath = Join-Path (Join-Path $CollectorRoot "run") "vector.pid"

if (-not (Test-Path -LiteralPath $pidPath)) {
    Write-Warning "No PID file found at $pidPath"
    Write-Host "If Vector is running manually in another terminal, stop it there."
    return
}

$pidValue = Get-Content -LiteralPath $pidPath -ErrorAction Stop | Select-Object -First 1
if (-not $pidValue) {
    Write-Warning "PID file is empty: $pidPath"
    Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
    return
}

$process = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
if (-not $process) {
    Write-Warning "No running process found for PID $pidValue"
    Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
    return
}

Write-Step "Stopping Vector process $pidValue"
$process | Stop-Process -Force
Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
Write-Host "  OK: Vector stopped."
