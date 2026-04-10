[CmdletBinding()]
param(
    [string]$StatePath,
    [int]$LookbackMinutes = 30,
    [int]$MaxEvents = 200,
    [switch]$DebugSummary
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-EventDataMap {
    param([System.Diagnostics.Eventing.Reader.EventRecord]$EventRecord)

    $map = @{}
    $xml = [xml]$EventRecord.ToXml()
    foreach ($node in @($xml.Event.EventData.Data)) {
        $name = [string]$node.Name
        if ([string]::IsNullOrWhiteSpace($name) -and $node.Attributes -and $node.Attributes["Name"]) {
            $name = [string]$node.Attributes["Name"].Value
        }

        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $value = [string]$node.InnerText
            if ([string]::IsNullOrWhiteSpace($value)) {
                $value = [string]$node.'#text'
            }
            $map[$name] = $value
        }
    }

    return $map
}

function Get-LastRecordId {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return 0L
    }

    try {
        $rawValue = (Get-Content -LiteralPath $Path -ErrorAction Stop | Select-Object -First 1)
        if ($rawValue -match '^v2:(\d+)$') {
            return [int64]$Matches[1]
        }

        # Ignore legacy numeric cursors from earlier test builds. Those builds
        # could advance past records that were dropped because parsing failed.
        return 0L
    } catch {
        return 0L
    }
}

function Save-LastRecordId {
    param(
        [string]$Path,
        [long]$RecordId
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    $directory = Split-Path -Parent $Path
    if ($directory) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }

    Set-Content -LiteralPath $Path -Value "v2:$RecordId" -Encoding ASCII
}

$startTime = (Get-Date).AddMinutes(-1 * $LookbackMinutes)
$lastRecordId = Get-LastRecordId -Path $StatePath
$maxEmittedRecordId = $lastRecordId
$scannedCount = 0
$skippedCursorCount = 0
$droppedLogonTypeCount = 0
$droppedUsernameCount = 0
$emittedCount = 0
$supportedLogonTypes = @("2", "3", "10")

$events = Get-WinEvent -FilterHashtable @{
    LogName = "Security"
    Id      = 4624, 4625
    StartTime = $startTime
} -MaxEvents $MaxEvents -ErrorAction Stop | Sort-Object RecordId

foreach ($event in $events) {
    $scannedCount++

    if ($event.RecordId -le $lastRecordId) {
        $skippedCursorCount++
        continue
    }

    $eventData = Get-EventDataMap -EventRecord $event

    $user = $eventData["TargetUserName"]
    if ([string]::IsNullOrWhiteSpace($user)) {
        $user = $eventData["SubjectUserName"]
    }

    $domain = $eventData["TargetDomainName"]
    if ([string]::IsNullOrWhiteSpace($domain)) {
        $domain = $eventData["SubjectDomainName"]
    }

    $authMethod = $eventData["AuthenticationPackageName"]
    if ([string]::IsNullOrWhiteSpace($authMethod)) {
        $authMethod = $eventData["LogonProcessName"]
    }

    $logonType = $eventData["LogonType"]
    if (-not [string]::IsNullOrWhiteSpace($logonType) -and $supportedLogonTypes -notcontains $logonType) {
        $droppedLogonTypeCount++
        continue
    }

    if ([string]::IsNullOrWhiteSpace($user) -or $user -eq "-") {
        $droppedUsernameCount++
        continue
    }

    $record = [ordered]@{
        timestamp     = $event.TimeCreated.ToUniversalTime().ToString("o")
        event_id      = [string]$event.Id
        user          = $user
        domain        = $domain
        src_ip        = $eventData["IpAddress"]
        host          = $event.MachineName
        logon_type    = $logonType
        auth_method   = $authMethod
        provider_name = $event.ProviderName
        raw_message   = ($event.Message -replace "`r?`n", " ").Trim()
        record_id     = [string]$event.RecordId
    }

    $record | ConvertTo-Json -Compress
    $emittedCount++

    if ($event.RecordId -gt $maxEmittedRecordId) {
        $maxEmittedRecordId = $event.RecordId
    }
}

if ($maxEmittedRecordId -gt $lastRecordId) {
    Save-LastRecordId -Path $StatePath -RecordId $maxEmittedRecordId
}

if ($DebugSummary) {
    [Console]::Error.WriteLine("[hayabusa-collector] scanned_4624_4625={0}" -f $scannedCount)
    [Console]::Error.WriteLine("[hayabusa-collector] skipped_already_seen={0}" -f $skippedCursorCount)
    [Console]::Error.WriteLine("[hayabusa-collector] dropped_unsupported_logon_type={0}" -f $droppedLogonTypeCount)
    [Console]::Error.WriteLine("[hayabusa-collector] dropped_missing_or_invalid_username={0}" -f $droppedUsernameCount)
    [Console]::Error.WriteLine("[hayabusa-collector] emitted_records={0}" -f $emittedCount)
    [Console]::Error.WriteLine("[hayabusa-collector] supported_logon_types=2,3,10")
}
