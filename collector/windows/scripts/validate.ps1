[CmdletBinding()]
param(
    [string]$CollectorRoot = "$env:ProgramData\HayabusaCollector",
    [string]$VectorConfigPath,
    [int]$LookbackHours = 24
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "[hayabusa-collector] $Message"
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Find-VectorExe {
    param([string]$CollectorRootPath)

    $candidates = @(
        (Join-Path $CollectorRootPath "bin\vector.exe"),
        (Get-Command vector.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
        "$env:ProgramFiles\Vector\bin\vector.exe",
        "$env:ProgramFiles\Vector\vector.exe"
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    return $candidates | Select-Object -First 1
}

function Get-SettingFromConfig {
    param(
        [string]$Path,
        [string]$Prefix
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $line = Get-Content -LiteralPath $Path | Where-Object { $_ -match "^\s*$([regex]::Escape($Prefix))\s*=" } | Select-Object -First 1
    if (-not $line) {
        return $null
    }

    return (($line -split "=", 2)[1]).Trim().Trim('"')
}

if ([string]::IsNullOrWhiteSpace($VectorConfigPath)) {
    $VectorConfigPath = Join-Path (Join-Path $CollectorRoot "config") "vector.toml"
}

if (Test-IsAdministrator) {
    Write-Step "Administrator privileges detected."
} else {
    Write-Warning "Not running as Administrator. Security log access may fail."
}

Write-Step "Checking required collector paths."
foreach ($path in @(
    $CollectorRoot,
    (Join-Path $CollectorRoot "config"),
    (Join-Path $CollectorRoot "state"),
    (Join-Path $CollectorRoot "logs"),
    (Join-Path $CollectorRoot "scripts")
)) {
    if (Test-Path -LiteralPath $path) {
        Write-Host "  OK: $path"
    } else {
        Write-Warning "Missing: $path"
    }
}

Write-Step "Checking rendered Vector config."
if (Test-Path -LiteralPath $VectorConfigPath) {
    Write-Host "  OK: Config present at $VectorConfigPath"
} else {
    Write-Warning "Config missing at $VectorConfigPath"
}

$emitterScriptPath = Join-Path (Join-Path $CollectorRoot "scripts") "emit-security-events.ps1"
if (Test-Path -LiteralPath $emitterScriptPath) {
    Write-Host "  OK: Event export helper present at $emitterScriptPath"
} else {
    Write-Warning "Event export helper missing at $emitterScriptPath"
}

$vectorExe = Find-VectorExe -CollectorRootPath $CollectorRoot
if ($vectorExe) {
    Write-Step "Detected Vector binary."
    Write-Host "  OK: $vectorExe"
    if (Test-Path -LiteralPath $VectorConfigPath) {
        Write-Step "Validating Vector config."
        try {
            & $vectorExe validate --no-environment $VectorConfigPath
            Write-Host "  OK: vector validate completed."
        } catch {
            Write-Warning "Vector validation failed. Check vector.toml and rerun."
        }
    }
} else {
    Write-Warning "Vector binary not found. Install Vector or copy vector.exe into $CollectorRoot\bin."
}

Write-Step "Checking Windows Security log access."
try {
    $securityLog = Get-WinEvent -ListLog Security -ErrorAction Stop
    Write-Host "  OK: Security log is readable."
    Write-Host "  Record count: $($securityLog.RecordCount)"
} catch {
    Write-Warning "Could not read the Security log. Run PowerShell as Administrator."
}

Write-Step "Checking recent auth-related Windows events."
try {
    $recentEvents = Get-WinEvent -FilterHashtable @{
        LogName   = "Security"
        Id        = 4624, 4625
        StartTime = (Get-Date).AddHours(-$LookbackHours)
    } -MaxEvents 12 -ErrorAction Stop

    Write-Host "  OK: Found $($recentEvents.Count) recent 4624/4625 event(s)."
    $recentEvents |
        Select-Object TimeCreated, Id, MachineName, ProviderName |
        Format-Table -AutoSize
} catch {
    Write-Warning "Could not read recent 4624/4625 events."
}

Write-Step "Collection method"
Write-Host "  This bundle uses Vector's supported exec source to run:"
Write-Host "    $emitterScriptPath"
Write-Host "  That helper reads the Windows Security log with Get-WinEvent and emits JSON lines to Vector."
if (Test-Path -LiteralPath $emitterScriptPath) {
    Write-Host "  Debug no-output cases with:"
    Write-Host "    powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$emitterScriptPath`" -LookbackMinutes 60 -MaxEvents 200 -DebugSummary"
}

$natsUrl = Get-SettingFromConfig -Path $VectorConfigPath -Prefix "url"
if ($natsUrl) {
    try {
        $uri = [uri]$natsUrl
        $port = if ($uri.Port -gt 0) { $uri.Port } else { 4222 }
        Write-Step "Checking NATS connectivity."
        $connection = Test-NetConnection -ComputerName $uri.Host -Port $port -WarningAction SilentlyContinue
        if ($connection.TcpTestSucceeded) {
            Write-Host "  OK: TCP reachability to $($uri.Host):$port confirmed."
        } else {
            Write-Warning "Could not reach $($uri.Host):$port. Check firewall, DNS, or the Hayabusa host listener."
        }
    } catch {
        Write-Warning "Could not parse NATS URL from config: $natsUrl"
    }
} else {
    Write-Warning "No NATS URL found in the rendered config."
}

Write-Step "Local guidance"
Write-Host "  Inspect recent auth events:"
Write-Host "    .\collector\windows\scripts\collect-sample-events.ps1 -ShowRecent"
Write-Host "  Start the collector:"
Write-Host "    .\collector\windows\scripts\start.ps1 -CollectorRoot `"$CollectorRoot`""
Write-Host "  Or run it interactively:"
Write-Host "    vector --config `"$VectorConfigPath`""
Write-Host "  Validate on the Hayabusa host:"
Write-Host "    ./scripts/windows-endpoint-check.sh --computer $env:COMPUTERNAME"
