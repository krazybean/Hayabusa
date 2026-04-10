[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$NatsUrl,

    [string]$Subject = "security.events",
    [string]$CollectorName = $env:COMPUTERNAME,
    [string]$Environment = "lab",
    [string]$CollectorRoot = "$env:ProgramData\HayabusaCollector",
    [string]$SourceRoot,
    [string]$VectorVersion = "0.54.0",
    [string]$VectorZipUrl,
    [string]$NssmZipUrl = "https://nssm.cc/release/nssm-2.24.zip"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ServiceName = "HayabusaCollector"
$TaskName = "HayabusaCollector"

function Write-Ok {
    param([string]$Message)
    Write-Host "✔ $Message" -ForegroundColor Green
}

function Write-Step {
    param([string]$Message)
    Write-Host "[hayabusa-installer] $Message"
}

function Fail {
    param([string]$Message)
    throw $Message
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-SourceRoot {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    return (
        (Test-Path -LiteralPath (Join-Path $fullPath "collector\windows\vector\vector.toml.tpl")) -or
        (Test-Path -LiteralPath (Join-Path $fullPath "vector\vector.toml.tpl"))
    )
}

function Resolve-SourceRoot {
    if (-not [string]::IsNullOrWhiteSpace($SourceRoot)) {
        if (-not (Test-SourceRoot -Path $SourceRoot)) {
            Fail "SourceRoot does not contain collector files: $SourceRoot"
        }
        return [System.IO.Path]::GetFullPath($SourceRoot)
    }

    $candidates = @(
        $PSScriptRoot,
        (Join-Path $PSScriptRoot "..\..")
    )

    foreach ($candidate in $candidates) {
        if (Test-SourceRoot -Path $candidate) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }

    Fail "Could not locate collector source files. Run install.ps1 from the repo or extracted collector package, or pass -SourceRoot."
}

function Resolve-SourceFile {
    param(
        [string]$Root,
        [string[]]$RelativeCandidates
    )

    foreach ($relativePath in $RelativeCandidates) {
        $candidate = Join-Path $Root $relativePath
        if (Test-Path -LiteralPath $candidate) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }

    return $null
}

function Ensure-Directory {
    param([string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Download-And-Extract {
    param(
        [string]$Url,
        [string]$DestinationDirectory
    )

    Ensure-Directory -Path $DestinationDirectory
    $zipPath = Join-Path $env:TEMP ([System.IO.Path]::GetFileName($Url))
    if ([string]::IsNullOrWhiteSpace($zipPath) -or $zipPath -eq $env:TEMP) {
        $zipPath = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString() + ".zip")
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $Url -OutFile $zipPath -UseBasicParsing

    if (Test-Path -LiteralPath $DestinationDirectory) {
        Remove-Item -LiteralPath $DestinationDirectory -Recurse -Force
    }
    Ensure-Directory -Path $DestinationDirectory
    Expand-Archive -LiteralPath $zipPath -DestinationPath $DestinationDirectory -Force
    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
}

function Ensure-Vector {
    param(
        [string]$RepoRoot,
        [string]$BinDir
    )

    $target = Join-Path $BinDir "vector.exe"
    if (Test-Path -LiteralPath $target) {
        return $target
    }

    $bundledCandidates = @(
        (Join-Path $RepoRoot "collector\windows\bundle\bin\vector.exe"),
        (Join-Path $RepoRoot "bin\vector.exe"),
        (Join-Path $RepoRoot "vector.exe")
    )

    foreach ($candidate in $bundledCandidates) {
        if (Test-Path -LiteralPath $candidate) {
            Copy-Item -LiteralPath $candidate -Destination $target -Force
            return $target
        }
    }

    $existing = Get-Command vector.exe -ErrorAction SilentlyContinue
    if ($existing -and (Test-Path -LiteralPath $existing.Source)) {
        Copy-Item -LiteralPath $existing.Source -Destination $target -Force
        return $target
    }

    if ([string]::IsNullOrWhiteSpace($VectorZipUrl)) {
        $VectorZipUrl = "https://packages.timber.io/vector/$VectorVersion/vector-$VectorVersion-x86_64-pc-windows-msvc.zip"
    }

    Write-Step "Downloading Vector $VectorVersion from $VectorZipUrl"
    $extractDir = Join-Path $env:TEMP ("hayabusa-vector-" + [System.Guid]::NewGuid().ToString())
    Download-And-Extract -Url $VectorZipUrl -DestinationDirectory $extractDir

    $downloaded = Get-ChildItem -LiteralPath $extractDir -Recurse -Filter "vector.exe" | Select-Object -First 1
    if (-not $downloaded) {
        Fail "Downloaded Vector archive did not contain vector.exe."
    }

    Copy-Item -LiteralPath $downloaded.FullName -Destination $target -Force
    Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    return $target
}

function Ensure-Nssm {
    param([string]$BinDir)

    $target = Join-Path $BinDir "nssm.exe"
    if (Test-Path -LiteralPath $target) {
        return $target
    }

    Write-Step "Downloading NSSM from $NssmZipUrl"
    $extractDir = Join-Path $env:TEMP ("hayabusa-nssm-" + [System.Guid]::NewGuid().ToString())
    Download-And-Extract -Url $NssmZipUrl -DestinationDirectory $extractDir

    $candidate = Get-ChildItem -LiteralPath $extractDir -Recurse -Filter "nssm.exe" |
        Where-Object { $_.FullName -match "\\win64\\" } |
        Select-Object -First 1

    if (-not $candidate) {
        $candidate = Get-ChildItem -LiteralPath $extractDir -Recurse -Filter "nssm.exe" | Select-Object -First 1
    }

    if (-not $candidate) {
        Fail "Downloaded NSSM archive did not contain nssm.exe."
    }

    Copy-Item -LiteralPath $candidate.FullName -Destination $target -Force
    Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    return $target
}

function Copy-RequiredFiles {
    param(
        [string]$RepoRoot,
        [string]$ScriptsDir,
        [string]$ConfigDir
    )

    $templateSource = Resolve-SourceFile -Root $RepoRoot -RelativeCandidates @(
        "collector\windows\vector\vector.toml.tpl",
        "vector\vector.toml.tpl"
    )
    $emitterSource = Resolve-SourceFile -Root $RepoRoot -RelativeCandidates @(
        "collector\windows\scripts\emit-security-events.ps1",
        "emit-security-events.ps1",
        "scripts\emit-security-events.ps1"
    )

    if ([string]::IsNullOrWhiteSpace($templateSource) -or -not (Test-Path -LiteralPath $templateSource)) {
        Fail "Missing Vector template: $templateSource"
    }
    if ([string]::IsNullOrWhiteSpace($emitterSource) -or -not (Test-Path -LiteralPath $emitterSource)) {
        Fail "Missing event export helper: $emitterSource"
    }

    Copy-Item -LiteralPath $templateSource -Destination (Join-Path $ConfigDir "vector.toml.tpl") -Force
    Copy-Item -LiteralPath $emitterSource -Destination (Join-Path $ScriptsDir "emit-security-events.ps1") -Force

    foreach ($scriptName in @("start.ps1", "stop.ps1", "status.ps1", "uninstall.ps1")) {
        $source = Join-Path $PSScriptRoot $scriptName
        if (Test-Path -LiteralPath $source) {
            Copy-Item -LiteralPath $source -Destination (Join-Path $ScriptsDir $scriptName) -Force
        }
    }
}

function Render-Config {
    param(
        [string]$ConfigDir,
        [string]$LogsDir,
        [string]$StateDir,
        [string]$ScriptsDir
    )

    $templatePath = Join-Path $ConfigDir "vector.toml.tpl"
    $outputPath = Join-Path $ConfigDir "vector.toml"
    if (-not (Test-Path -LiteralPath $templatePath)) {
        Fail "Template file missing: $templatePath"
    }

    $eventScriptPath = Join-Path $ScriptsDir "emit-security-events.ps1"
    $cursorPath = Join-Path $StateDir "windows-event-log.cursor"
    $debugPath = Join-Path $LogsDir "windows-auth-normalized.jsonl"

    $content = Get-Content -LiteralPath $templatePath -Raw
    $content = $content.Replace("__NATS_URL__", $NatsUrl)
    $content = $content.Replace("__NATS_SUBJECT__", $Subject)
    $content = $content.Replace("__SUBJECT__", $Subject)
    $content = $content.Replace("__COLLECTOR_NAME__", $CollectorName)
    $content = $content.Replace("__ENVIRONMENT_TAG__", $Environment)
    $content = $content.Replace("__STATE_DIR__", ($StateDir -replace "\\", "/"))
    $content = $content.Replace("__EVENT_EXPORT_SCRIPT__", ($eventScriptPath -replace "\\", "/"))
    $content = $content.Replace("__EVENT_EXPORT_STATE__", ($cursorPath -replace "\\", "/"))
    $content = $content.Replace("__DEBUG_OUTPUT_PATH__", ($debugPath -replace "\\", "/"))
    $content = $content.Replace("__NATS_AUTH_BLOCK__", "# Hayabusa MVP NATS runs without auth by default.")

    Set-Content -LiteralPath $outputPath -Value $content -Encoding UTF8

    $settings = @"
NATS_URL=$NatsUrl
NATS_SUBJECT=$Subject
COLLECTOR_NAME=$CollectorName
ENVIRONMENT=$Environment
CONFIG_PATH=$outputPath
"@
    Set-Content -LiteralPath (Join-Path $ConfigDir "collector-settings.txt") -Value $settings -Encoding UTF8
    return $outputPath
}

function Register-NssmService {
    param(
        [string]$NssmExe,
        [string]$ScriptsDir,
        [string]$LogsDir
    )

    $startScript = Join-Path $ScriptsDir "start.ps1"
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service) {
        Write-Step "Existing $ServiceName service found; stopping and replacing configuration."
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        & $NssmExe remove $ServiceName confirm | Out-Null
    }

    $stdoutPath = Join-Path $LogsDir "service.stdout.log"
    $stderrPath = Join-Path $LogsDir "service.stderr.log"
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$startScript`""

    & $NssmExe install $ServiceName "powershell.exe" $arguments | Out-Null
    & $NssmExe set $ServiceName AppDirectory $CollectorRoot | Out-Null
    & $NssmExe set $ServiceName AppStdout $stdoutPath | Out-Null
    & $NssmExe set $ServiceName AppStderr $stderrPath | Out-Null
    & $NssmExe set $ServiceName AppRotateFiles 1 | Out-Null
    & $NssmExe set $ServiceName AppRotateOnline 1 | Out-Null
    & $NssmExe set $ServiceName AppRotateBytes 10485760 | Out-Null
    & $NssmExe set $ServiceName Start SERVICE_AUTO_START | Out-Null
}

function Register-StartupTask {
    param([string]$ScriptsDir)

    $startScript = Join-Path $ScriptsDir "start.ps1"
    $argument = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$startScript`""
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $argument
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null
}

foreach ($required in @(
    @{ Name = "NatsUrl"; Value = $NatsUrl },
    @{ Name = "Subject"; Value = $Subject },
    @{ Name = "CollectorName"; Value = $CollectorName }
)) {
    if ([string]::IsNullOrWhiteSpace($required.Value)) {
        Fail "$($required.Name) is required."
    }
}

if (-not (Test-IsAdmin)) {
    Fail "Run this installer from an elevated PowerShell session. Admin rights are required for Security log access and service registration."
}

$repoRoot = Resolve-SourceRoot
$configDir = Join-Path $CollectorRoot "config"
$logsDir = Join-Path $CollectorRoot "logs"
$stateDir = Join-Path $CollectorRoot "state"
$binDir = Join-Path $CollectorRoot "bin"
$scriptsDir = Join-Path $CollectorRoot "scripts"

Write-Step "Installing Hayabusa Collector to $CollectorRoot"
foreach ($dir in @($CollectorRoot, $configDir, $logsDir, $stateDir, $binDir, $scriptsDir)) {
    Ensure-Directory -Path $dir
}

$vectorExe = Ensure-Vector -RepoRoot $repoRoot -BinDir $binDir
Write-Ok "Installed vector"

Copy-RequiredFiles -RepoRoot $repoRoot -ScriptsDir $scriptsDir -ConfigDir $configDir
$configPath = Render-Config -ConfigDir $configDir -LogsDir $logsDir -StateDir $stateDir -ScriptsDir $scriptsDir
Write-Ok "Configured collector"

try {
    $nssmExe = Ensure-Nssm -BinDir $binDir
    Register-NssmService -NssmExe $nssmExe -ScriptsDir $scriptsDir -LogsDir $logsDir
    Write-Ok "Service registered"
    Start-Service -Name $ServiceName
    Write-Ok "Service started"
} catch {
    Write-Warning "NSSM service setup failed: $($_.Exception.Message)"
    Write-Warning "Falling back to a startup scheduled task."
    Register-StartupTask -ScriptsDir $scriptsDir
    Start-ScheduledTask -TaskName $TaskName
    Write-Ok "Startup scheduled task registered"
}

Write-Host ""
Write-Host "✅ Hayabusa Collector is running and sending events" -ForegroundColor Green
Write-Host ""
Write-Host "Collector root : $CollectorRoot"
Write-Host "Vector exe     : $vectorExe"
Write-Host "Config         : $configPath"
Write-Host "Logs           : $logsDir"
Write-Host ""
Write-Host "Check status:"
Write-Host "  powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$scriptsDir\status.ps1`""
