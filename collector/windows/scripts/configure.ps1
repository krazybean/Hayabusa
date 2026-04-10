[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$NatsUrl,

    [Alias("Subject")]
    [string]$NatsSubject = "security.events",
    [string]$CollectorName = $env:COMPUTERNAME,
    [string]$EnvironmentTag = "lab",
    [string]$CollectorRoot = "$env:ProgramData\HayabusaCollector",
    [string]$TemplatePath,
    [string]$VectorConfigPath,
    [string]$NatsToken
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "[hayabusa-collector] $Message"
}

function Fail {
    param([string]$Message)
    throw $Message
}

function Resolve-TemplatePath {
    param([string]$ProvidedPath)

    if (-not [string]::IsNullOrWhiteSpace($ProvidedPath)) {
        return [System.IO.Path]::GetFullPath($ProvidedPath)
    }

    $candidates = @(
        (Join-Path $PSScriptRoot "..\vector\vector.toml.tpl"),
        (Join-Path $PSScriptRoot "vector\vector.toml.tpl")
    )

    foreach ($candidate in $candidates) {
        $fullPath = [System.IO.Path]::GetFullPath($candidate)
        if (Test-Path -LiteralPath $fullPath) {
            return $fullPath
        }
    }

    return $null
}

function Resolve-EmitterScriptPath {
    param([string]$CollectorRootPath)

    $stagedScript = Join-Path $CollectorRootPath "scripts\emit-security-events.ps1"
    if (Test-Path -LiteralPath $stagedScript) {
        return [System.IO.Path]::GetFullPath($stagedScript)
    }

    $candidates = @(
        (Join-Path $PSScriptRoot "emit-security-events.ps1"),
        (Join-Path $PSScriptRoot "..\scripts\emit-security-events.ps1")
    )

    foreach ($candidate in $candidates) {
        $fullPath = [System.IO.Path]::GetFullPath($candidate)
        if (Test-Path -LiteralPath $fullPath) {
            return $fullPath
        }
    }

    return $null
}

foreach ($required in @(
    @{ Name = "NatsUrl"; Value = $NatsUrl },
    @{ Name = "NatsSubject"; Value = $NatsSubject },
    @{ Name = "CollectorName"; Value = $CollectorName }
)) {
    if ([string]::IsNullOrWhiteSpace($required.Value)) {
        Fail "$($required.Name) is required."
    }
}

$resolvedTemplatePath = Resolve-TemplatePath -ProvidedPath $TemplatePath
if ([string]::IsNullOrWhiteSpace($resolvedTemplatePath) -or -not (Test-Path -LiteralPath $resolvedTemplatePath)) {
    Fail "Template not found. Expected vector.toml.tpl beside the bundle or under collector/windows/vector."
}

$configDir = Join-Path $CollectorRoot "config"
$stateDir = Join-Path $CollectorRoot "state"
$logDir = Join-Path $CollectorRoot "logs"
$scriptsDir = Join-Path $CollectorRoot "scripts"
$debugOutputPath = Join-Path $logDir "windows-auth-normalized.jsonl"

foreach ($path in @($CollectorRoot, $configDir, $stateDir, $logDir, $scriptsDir)) {
    New-Item -ItemType Directory -Force -Path $path | Out-Null
}

if ([string]::IsNullOrWhiteSpace($VectorConfigPath)) {
    $VectorConfigPath = Join-Path $configDir "vector.toml"
}

$resolvedEmitterScriptPath = Resolve-EmitterScriptPath -CollectorRootPath $CollectorRoot
if ([string]::IsNullOrWhiteSpace($resolvedEmitterScriptPath) -or -not (Test-Path -LiteralPath $resolvedEmitterScriptPath)) {
    Fail "emit-security-events.ps1 not found. Expected it in the bundle or under $scriptsDir."
}

$stagedEmitterScriptPath = Join-Path $scriptsDir "emit-security-events.ps1"
if ([System.IO.Path]::GetFullPath($resolvedEmitterScriptPath) -ne [System.IO.Path]::GetFullPath($stagedEmitterScriptPath)) {
    Copy-Item -LiteralPath $resolvedEmitterScriptPath -Destination $stagedEmitterScriptPath -Force
}

$template = Get-Content -LiteralPath $resolvedTemplatePath -Raw
$rendered = $template

$authBlock = "# Current Hayabusa MVP usually runs NATS without auth."
if (-not [string]::IsNullOrWhiteSpace($NatsToken)) {
    $authBlock = @"
auth.strategy = "token"
auth.token.value = "$NatsToken"
"@
}

$rendered = $rendered.Replace("__NATS_URL__", $NatsUrl)
$rendered = $rendered.Replace("__NATS_SUBJECT__", $NatsSubject)
$rendered = $rendered.Replace("__SUBJECT__", $NatsSubject)
$rendered = $rendered.Replace("__COLLECTOR_NAME__", $CollectorName)
$rendered = $rendered.Replace("__ENVIRONMENT_TAG__", $EnvironmentTag)
$rendered = $rendered.Replace("__STATE_DIR__", ($stateDir -replace '\\', '/'))
$rendered = $rendered.Replace("__EVENT_EXPORT_SCRIPT__", ($stagedEmitterScriptPath -replace '\\', '/'))
$rendered = $rendered.Replace("__EVENT_EXPORT_STATE__", ((Join-Path $stateDir "windows-event-log.cursor") -replace '\\', '/'))
$rendered = $rendered.Replace("__DEBUG_OUTPUT_PATH__", ($debugOutputPath -replace '\\', '/'))
$rendered = $rendered.Replace("__NATS_AUTH_BLOCK__", $authBlock)

try {
    Set-Content -LiteralPath $VectorConfigPath -Value $rendered -Encoding UTF8
} catch {
    Fail "Could not write rendered config to $VectorConfigPath. $($_.Exception.Message)"
}

$settingsPath = Join-Path $configDir "collector-settings.txt"
$settingsText = @"
NATS_URL=$NatsUrl
NATS_SUBJECT=$NatsSubject
COLLECTOR_NAME=$CollectorName
ENVIRONMENT_TAG=$EnvironmentTag
CONFIG_PATH=$VectorConfigPath
"@
Set-Content -LiteralPath $settingsPath -Value $settingsText -Encoding UTF8

Write-Step "Rendered collector config."
Write-Host "  Config path      : $VectorConfigPath"
Write-Host "  Settings file    : $settingsPath"
Write-Host "  Debug output     : $debugOutputPath"
Write-Host "  Collector name   : $CollectorName"
Write-Host "  Environment tag  : $EnvironmentTag"
Write-Host "  NATS URL         : $NatsUrl"
Write-Host "  Subject          : $NatsSubject"
Write-Host ""
Write-Host "Start options:"
Write-Host "  .\collector\windows\scripts\start.ps1 -CollectorRoot `"$CollectorRoot`""
Write-Host "  vector --config `"$VectorConfigPath`""
