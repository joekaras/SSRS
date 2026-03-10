# Backup-Config.ps1
# Backs up all SSRS configuration files modified by the Custom Security Extension deployment.
# Creates a timestamped subfolder under .\backups\ with subfolders mirroring source locations.

param(
    [string]$SsrsRoot   = '',   # SSRS install root (without \SSRS) — auto-detected from Environment.ps1
    [string]$BackupRoot = "$PSScriptRoot\..\backups"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Auto-detect server environment ────────────────────────────────────────
. (Join-Path $PSScriptRoot 'Environment.ps1')
$_prof = Get-ServerProfile
if (-not $SsrsRoot) { $SsrsRoot = $_prof.SsrsInstallRoot }

$ssrsDir = Join-Path $SsrsRoot 'SSRS'

# Files to back up: @{ Source = full path; SubFolder = subfolder name under backup dir }
$files = @(
    @{ Source = "$ssrsDir\ReportServer\rsreportserver.config"; SubFolder = 'ReportServer' }
    @{ Source = "$ssrsDir\ReportServer\web.config";            SubFolder = 'ReportServer' }
    @{ Source = "$ssrsDir\ReportServer\rssrvpolicy.config";    SubFolder = 'ReportServer' }
    @{ Source = "$ssrsDir\Portal\RSPortal.exe.config";           SubFolder = 'Portal'       }
)

# Create timestamped backup folder
$timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$resolvedRoot = if (Test-Path $BackupRoot) { Resolve-Path $BackupRoot } else { $BackupRoot }
$backupDir = Join-Path $resolvedRoot $timestamp

Write-Host '================================================' -ForegroundColor Cyan
Write-Host "SSRS Config Backup" -ForegroundColor Cyan
Write-Host "Destination: $backupDir" -ForegroundColor Cyan
Write-Host '================================================' -ForegroundColor Cyan
Write-Host ''

$ok = 0
$fail = 0

foreach ($entry in $files) {
    $src = $entry.Source
    $dest = Join-Path $backupDir $entry.SubFolder

    if (-not (Test-Path $src)) {
        Write-Warning "Not found, skipping: $src"
        $fail++
        continue
    }

    try {
        if (-not (Test-Path $dest)) {
            New-Item -ItemType Directory -Path $dest -Force | Out-Null
        }
        Copy-Item -Path $src -Destination $dest -Force
        $fileName = Split-Path $src -Leaf
        Write-Host "  OK  $($entry.SubFolder)\$fileName" -ForegroundColor Green
        $ok++
    }
    catch {
        Write-Warning "FAILED $src : $_"
        $fail++
    }
}

Write-Host ''
Write-Host '================================================' -ForegroundColor Cyan
$color = if ($fail -eq 0) { 'Green' } else { 'Yellow' }
Write-Host "Backed up: $ok succeeded, $fail failed" -ForegroundColor $color
Write-Host '================================================' -ForegroundColor Cyan

if ($fail -gt 0) { exit 1 }
