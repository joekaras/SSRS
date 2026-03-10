# Set-Logging.ps1
# Controls SSRS trace logging level via rsreportserver.config.
# SSRS 2019 Native Mode — no IIS required.
#
# Usage:
#   .\scripts\Set-Logging.ps1 -Level Verbose      # Maximum detail
#   .\scripts\Set-Logging.ps1 -Level Info          # Normal production level
#   .\scripts\Set-Logging.ps1 -Level Off           # Disable tracing
#   .\scripts\Set-Logging.ps1 -Status              # Show current setting
#
# Log files written to: <SsrsRoot>\SSRS\LogFiles\

param(
    [ValidateSet('Verbose', 'Info', 'Warning', 'Error', 'Off')]
    [string]$Level = 'Info',
    [string]$SsrsRoot = '',   # auto-detected from Environment.ps1
    [switch]$Status
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Auto-detect server environment ────────────────────────────────────────
. (Join-Path $PSScriptRoot 'Environment.ps1')
$_prof = Get-ServerProfile
if (-not $SsrsRoot) { $SsrsRoot = $_prof.SsrsInstallRoot }

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error 'This script must be run as Administrator.'
    exit 1
}

$rsConfig  = Join-Path $SsrsRoot 'SSRS\ReportServer\rsreportserver.config'
$logDir    = Join-Path $SsrsRoot 'SSRS\LogFiles'

if (-not (Test-Path $rsConfig)) {
    Write-Error "rsreportserver.config not found: $rsConfig"
    exit 1
}

# Map friendly level names to SSRS DefaultTraceSwitch values:
#   0 = Off, 1 = Error, 2 = Warning, 3 = Info, 4 = Verbose
$levelMap = @{ Off = 0; Error = 1; Warning = 2; Info = 3; Verbose = 4 }

# ---------------------------------------------------------------------------
# -Status: show current settings
# ---------------------------------------------------------------------------
if ($Status) {
    [xml]$cfg = Get-Content $rsConfig -Raw
    $traceNode = $cfg.SelectSingleNode('//Configuration/Service/IsSchedulingService')
    $switchNode = $cfg.SelectSingleNode('//Configuration/Service/DefaultTraceSwitch')
    $currentSwitch = if ($switchNode) { $switchNode.InnerText } else { '(not set, default=3)' }

    $currentName = ($levelMap.GetEnumerator() | Where-Object { $_.Value -eq [int]$currentSwitch } | Select-Object -First 1).Key
    if (-not $currentName) { $currentName = "level $currentSwitch" }

    Write-Host '================================================' -ForegroundColor Cyan
    Write-Host 'SSRS Logging Status' -ForegroundColor Cyan
    Write-Host '================================================' -ForegroundColor Cyan
    Write-Host "  DefaultTraceSwitch : $currentSwitch ($currentName)" -ForegroundColor White
    Write-Host "  Config file        : $rsConfig" -ForegroundColor Gray
    Write-Host "  Log directory      : $logDir" -ForegroundColor Gray
    Write-Host ''
    Write-Host 'Recent log files:' -ForegroundColor Yellow
    Get-ChildItem $logDir -Filter '*.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 5 |
        ForEach-Object { Write-Host "  $($_.Name)  ($([math]::Round($_.Length/1KB,1)) KB)" -ForegroundColor Gray }
    Write-Host '================================================' -ForegroundColor Cyan
    exit 0
}

# ---------------------------------------------------------------------------
# Apply level
# ---------------------------------------------------------------------------
$switchValue = $levelMap[$Level]

Write-Host '================================================' -ForegroundColor Cyan
Write-Host "Setting SSRS trace level: $Level ($switchValue)" -ForegroundColor Cyan
Write-Host '================================================' -ForegroundColor Cyan

[xml]$cfg = Get-Content $rsConfig -Raw

$serviceNode = $cfg.SelectSingleNode('//Configuration/Service')
if ($null -eq $serviceNode) {
    $serviceNode = $cfg.CreateElement('Service')
    $cfg.SelectSingleNode('//Configuration').AppendChild($serviceNode) | Out-Null
}

$switchNode = $serviceNode.SelectSingleNode('DefaultTraceSwitch')
if ($null -eq $switchNode) {
    $switchNode = $cfg.CreateElement('DefaultTraceSwitch')
    $serviceNode.AppendChild($switchNode) | Out-Null
}
$switchNode.InnerText = $switchValue.ToString()

$settings = [System.Xml.XmlWriterSettings]::new()
$settings.Indent             = $true
$settings.IndentChars        = '  '
$settings.Encoding           = [System.Text.Encoding]::UTF8
$settings.OmitXmlDeclaration = $false
$writer = [System.Xml.XmlWriter]::Create($rsConfig, $settings)
try   { $cfg.Save($writer) }
finally { $writer.Dispose() }

Write-Host "  DefaultTraceSwitch -> $switchValue ($Level)" -ForegroundColor Green
Write-Host "  Saved: $rsConfig" -ForegroundColor Green
Write-Host ''
Write-Host 'Restart SSRS to apply: Restart-Service SQLServerReportingServices' -ForegroundColor Yellow
Write-Host "Log files: $logDir" -ForegroundColor Gray
Write-Host '================================================' -ForegroundColor Cyan
