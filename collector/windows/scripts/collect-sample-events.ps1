[CmdletBinding()]
param(
    [int]$LookbackHours = 12,
    [switch]$ShowRecent
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "[hayabusa-collector] $Message"
}

$startTime = (Get-Date).AddHours(-$LookbackHours)

Write-Step "This helper does not fabricate Windows Security events."
Write-Host "It shows recent 4624/4625 activity and suggests practical ways to generate test logons."
Write-Host ""
Write-Host "Recommended high-signal test paths:"
Write-Host "  1. Remote SMB auth from another machine using a real username and wrong password."
Write-Host "  2. RDP login or failed RDP login where available."
Write-Host "  3. Then check for Event IDs 4624 and 4625 with logon type 3 or 10."
Write-Host ""
Write-Host "Local lock/unlock, cached logons, and service logons often produce logon types 5, 7, or 11."
Write-Host "Those are intentionally low-value for this validation path and may be dropped by the collector."

Write-Step "Recent Windows auth events"
try {
    $events = Get-WinEvent -FilterHashtable @{
        LogName   = "Security"
        Id        = 4624, 4625
        StartTime = $startTime
    } -MaxEvents 20 -ErrorAction Stop

    if (-not $events) {
        Write-Warning "No recent 4624/4625 events were found in the last $LookbackHours hour(s)."
    } else {
        $events |
            Select-Object TimeCreated, Id, MachineName, ProviderName |
            Format-Table -AutoSize
    }
} catch {
    Write-Warning "Could not query Windows Security events. Run as Administrator."
}

Write-Host ""
Write-Step "Tips"
Write-Host "  - Logon type 3 (network) and 10 (RDP) usually give the best remote-login signal."
Write-Host "  - Local console logons may not include a useful source IP."
Write-Host "  - Events with TargetUserName '-' are dropped because they are not useful for account-focused detections."
Write-Host "  - If events exist locally but Hayabusa sees nothing, run vector interactively and watch its logs."
