[CmdletBinding()]
param(
    [string]$CollectorRoot = "$env:ProgramData\HayabusaCollector",
    [string]$VectorConfigPath,
    [int]$LookbackHours = 24
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Warning "test-ingestion.ps1 is kept for compatibility. Use validate.ps1 going forward."

$validateScript = Join-Path $PSScriptRoot "validate.ps1"
& $validateScript `
    -CollectorRoot $CollectorRoot `
    -VectorConfigPath $VectorConfigPath `
    -LookbackHours $LookbackHours
