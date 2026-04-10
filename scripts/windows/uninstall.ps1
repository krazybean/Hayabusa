[CmdletBinding()]
param(
    [string]$CollectorRoot = "$env:ProgramData\HayabusaCollector",
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$serviceName = "HayabusaCollector"
$taskName = "HayabusaCollector"
$nssmExe = Join-Path (Join-Path $CollectorRoot "bin") "nssm.exe"

function Write-Step {
    param([string]$Message)
    Write-Host "[hayabusa-uninstall] $Message"
}

if (-not $Force) {
    $answer = Read-Host "Are you sure you want to remove $CollectorRoot? (y/n)"
    if ($answer -ne "y" -and $answer -ne "Y") {
        Write-Host "Uninstall cancelled."
        return
    }
}

$stopScript = Join-Path (Join-Path $CollectorRoot "scripts") "stop.ps1"
if (Test-Path -LiteralPath $stopScript) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $stopScript -CollectorRoot $CollectorRoot
}

$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($service) {
    Write-Step "Removing service $serviceName"
    if (Test-Path -LiteralPath $nssmExe) {
        & $nssmExe remove $serviceName confirm | Out-Null
    } else {
        & sc.exe delete $serviceName | Out-Null
    }
}

$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
    Write-Step "Removing scheduled task $taskName"
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

if (Test-Path -LiteralPath $CollectorRoot) {
    Write-Step "Removing $CollectorRoot"
    Remove-Item -LiteralPath $CollectorRoot -Recurse -Force
}

Write-Host "Hayabusa Collector uninstalled."
