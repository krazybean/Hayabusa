[CmdletBinding()]
param(
    [string]$CollectorRoot = "$env:ProgramData\HayabusaCollector",
    [string]$NatsUrl,
    [string]$NatsSubject = "security.events",
    [string]$CollectorName = $env:COMPUTERNAME,
    [string]$EnvironmentTag = "lab",
    [string]$NatsToken,
    [string]$VectorExePath
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
        $VectorExePath,
        (Join-Path $CollectorRootPath "bin\vector.exe"),
        (Get-Command vector.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
        "$env:ProgramFiles\Vector\bin\vector.exe",
        "$env:ProgramFiles\Vector\vector.exe"
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    return $candidates | Select-Object -First 1
}

if ($PSVersionTable.PSVersion.Major -lt 5) {
    throw "PowerShell 5.1 or newer is required."
}

$isAdmin = Test-IsAdministrator
if ($isAdmin) {
    Write-Step "Administrator privileges detected."
} else {
    Write-Warning "PowerShell is not elevated. Security log checks and some validation steps may fail."
}

$bundleRoot = Split-Path -Parent $PSScriptRoot
$configDir = Join-Path $CollectorRoot "config"
$stateDir = Join-Path $CollectorRoot "state"
$logDir = Join-Path $CollectorRoot "logs"
$binDir = Join-Path $CollectorRoot "bin"
$scriptsDir = Join-Path $CollectorRoot "scripts"

Write-Step "Creating Hayabusa collector working directories."
foreach ($path in @($CollectorRoot, $configDir, $stateDir, $logDir, $binDir, $scriptsDir)) {
    New-Item -ItemType Directory -Force -Path $path | Out-Null
}

if (-not [string]::IsNullOrWhiteSpace($VectorExePath)) {
    if (-not (Test-Path -LiteralPath $VectorExePath)) {
        throw "VectorExePath does not exist: $VectorExePath"
    }

    $bundledVectorPath = Join-Path $binDir "vector.exe"
    Copy-Item -LiteralPath $VectorExePath -Destination $bundledVectorPath -Force
    Write-Step "Copied vector.exe into the local Hayabusa collector bundle."
}

$vectorExe = Find-VectorExe -CollectorRootPath $CollectorRoot
if ($vectorExe) {
    Write-Step "Detected Vector binary: $vectorExe"
} else {
    Write-Warning "Vector was not found on this machine."
    Write-Host "Provide -VectorExePath to stage a vector.exe file into the bundle, or install Vector separately."
    Write-Host "Official Vector install docs: https://vector.dev/docs/setup/installation/operating-systems/windows/"
}

$bundleReadmeSource = Join-Path $bundleRoot "bundle\README.md"
if (Test-Path -LiteralPath $bundleReadmeSource) {
    Copy-Item -LiteralPath $bundleReadmeSource -Destination (Join-Path $CollectorRoot "README.md") -Force
}

$bundleEnvSource = Join-Path $bundleRoot "bundle\env.example"
if (Test-Path -LiteralPath $bundleEnvSource) {
    Copy-Item -LiteralPath $bundleEnvSource -Destination (Join-Path $CollectorRoot "env.example") -Force
}

$emitScriptSource = Join-Path $PSScriptRoot "emit-security-events.ps1"
if (Test-Path -LiteralPath $emitScriptSource) {
    Copy-Item -LiteralPath $emitScriptSource -Destination (Join-Path $scriptsDir "emit-security-events.ps1") -Force
}

if (-not [string]::IsNullOrWhiteSpace($NatsUrl)) {
    Write-Step "Rendering collector config into ProgramData."
    $configureScript = Join-Path $PSScriptRoot "configure.ps1"
    & $configureScript `
        -NatsUrl $NatsUrl `
        -NatsSubject $NatsSubject `
        -CollectorName $CollectorName `
        -EnvironmentTag $EnvironmentTag `
        -CollectorRoot $CollectorRoot `
        -NatsToken $NatsToken
} else {
    Write-Step "NATS URL not provided. Config was not rendered yet."
}

$installNote = @"
Hayabusa Collector for Windows

Collector root : $CollectorRoot
Config path    : $configDir\vector.toml
State dir      : $stateDir
Log dir        : $logDir
Vector bin dir : $binDir

Next steps:
1. Run configure.ps1 if vector.toml is not present yet.
2. Run validate.ps1 to confirm Security log access, config presence, and NATS reachability.
3. Start the collector in the background:
   .\start.ps1 -CollectorRoot "$CollectorRoot"
4. Or run Vector interactively first:
   vector --config "$configDir\vector.toml"
5. The collector reads Security events through a bundled PowerShell helper:
   $scriptsDir\emit-security-events.ps1
6. Use collect-sample-events.ps1 to generate or inspect Windows logon events.

This is a real-host validation bundle, not a production installer.
TODO: add optional service wrapping only after the first-host path is validated.
"@
Set-Content -LiteralPath (Join-Path $CollectorRoot "INSTALL.txt") -Value $installNote -Encoding UTF8

Write-Step "Collector install staging complete."
Write-Host "  Collector root : $CollectorRoot"
Write-Host "  Config path    : $configDir\vector.toml"
Write-Host "  Validation     : .\collector\windows\scripts\validate.ps1 -CollectorRoot `"$CollectorRoot`""
Write-Host "  Start          : .\collector\windows\scripts\start.ps1 -CollectorRoot `"$CollectorRoot`""
