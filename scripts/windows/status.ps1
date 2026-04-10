[CmdletBinding()]
param(
    [string]$CollectorRoot = "$env:ProgramData\HayabusaCollector"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$serviceName = "HayabusaCollector"
$taskName = "HayabusaCollector"
$configPath = Join-Path (Join-Path $CollectorRoot "config") "vector.toml"
$logsDir = Join-Path $CollectorRoot "logs"
$stdoutPath = Join-Path $logsDir "vector.stdout.log"
$stderrPath = Join-Path $logsDir "vector.stderr.log"
$debugPath = Join-Path $logsDir "windows-auth-normalized.jsonl"

Write-Host "Hayabusa Collector status"
Write-Host "=========================="

$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($service) {
    Write-Host "Service      : $($service.Status)"
} else {
    Write-Host "Service      : not installed"
}

$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
    Write-Host "Startup task : $($task.State)"
} else {
    Write-Host "Startup task : not installed"
}

$vectorProcesses = Get-Process -Name "vector" -ErrorAction SilentlyContinue
if ($vectorProcesses) {
    $ids = ($vectorProcesses | Select-Object -ExpandProperty Id) -join ", "
    Write-Host "Vector       : running (PID $ids)"
} else {
    Write-Host "Vector       : not running"
}

Write-Host "Config       : $configPath"
Write-Host "Config exists: $(Test-Path -LiteralPath $configPath)"
Write-Host "Logs         : $logsDir"

if (Test-Path -LiteralPath $debugPath) {
    $lastLine = Get-Content -LiteralPath $debugPath -Tail 1 -ErrorAction SilentlyContinue
    if ($lastLine) {
        try {
            $lastEvent = $lastLine | ConvertFrom-Json
            Write-Host "Last event ts: $($lastEvent.ts)"
        } catch {
            Write-Host "Last event ts: unable to parse latest debug event"
        }
    } else {
        Write-Host "Last event ts: debug file exists but is empty"
    }
} else {
    Write-Host "Last event ts: no normalized event debug file yet"
}

Write-Host ""
Write-Host "Last stdout lines:"
if (Test-Path -LiteralPath $stdoutPath) {
    Get-Content -LiteralPath $stdoutPath -Tail 10 -ErrorAction SilentlyContinue
} else {
    Write-Host "(no stdout log yet)"
}

Write-Host ""
Write-Host "Last stderr lines:"
if (Test-Path -LiteralPath $stderrPath) {
    Get-Content -LiteralPath $stderrPath -Tail 10 -ErrorAction SilentlyContinue
} else {
    Write-Host "(no stderr log yet)"
}
