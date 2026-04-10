[CmdletBinding()]
param(
    [string]$CollectorRoot = "$env:ProgramData\HayabusaCollector"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$serviceName = "HayabusaCollector"
$taskName = "HayabusaCollector"

function Write-Step {
    param([string]$Message)
    Write-Host "[hayabusa-collector] $Message"
}

$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($service) {
    Write-Step "Stopping service $serviceName"
    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
}

$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
    Write-Step "Stopping scheduled task $taskName"
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
}

$escapedRoot = $CollectorRoot.Replace("\", "\\")
$vectorProcesses = Get-CimInstance Win32_Process -Filter "name = 'vector.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*$CollectorRoot*" -or $_.ExecutablePath -like "$CollectorRoot*" -or $_.CommandLine -like "*$escapedRoot*" }

foreach ($process in @($vectorProcesses)) {
    Write-Step "Stopping vector.exe PID $($process.ProcessId)"
    Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
}

Write-Host "Hayabusa Collector stopped."
