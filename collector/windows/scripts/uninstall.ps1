[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$CollectorRoot = "$env:ProgramData\HayabusaCollector",
    [switch]$StopRunningVector
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "[hayabusa-collector] $Message"
}

$vectorProcesses = Get-Process -Name "vector" -ErrorAction SilentlyContinue
if ($vectorProcesses -and -not $StopRunningVector) {
    Write-Warning "vector.exe appears to be running. Re-run with -StopRunningVector if you want this script to stop it first."
}

if ($vectorProcesses -and $StopRunningVector) {
    Write-Step "Stopping running Vector processes."
    $vectorProcesses | Stop-Process -Force
}

if (-not (Test-Path -LiteralPath $CollectorRoot)) {
    Write-Step "Nothing to remove. Collector root not found: $CollectorRoot"
    return
}

if ($PSCmdlet.ShouldProcess($CollectorRoot, "Remove Hayabusa collector files")) {
    Remove-Item -LiteralPath $CollectorRoot -Recurse -Force
    Write-Step "Removed $CollectorRoot"
}

Write-Host "Vector itself was not uninstalled. This script only removes Hayabusa collector files."
