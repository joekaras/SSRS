# Package-SourceFiles.ps1
# Creates a portable ZIP package (base64-encoded) that can be emailed
# On another machine, extract by running the generated restore script

param(
    [string]$RootFolder = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$OutputFile = "$RootFolder\SourceFiles.zip",
    [string]$RestoreScript = "$RootFolder\Restore-SourceFiles.ps1",
    [switch]$CreateRestoreScript = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "================================" -ForegroundColor Cyan
Write-Host "Package Source Files for Email" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# File extensions to include
$extensions = @(
    '*.md', '*.txt',           # Markdown and text
    '*.config',                # Config files
    '*.sln', '*.csproj',       # Visual Studio
    '*.aspx', '*.aspx.cs',     # ASP.NET
    '*.cs',                    # C# code
    '*.xaml', '*.xaml.cs',     # WPF
    '*.sql',                   # SQL scripts
    '*.ps1',                   # PowerShell
    '*.json',                  # JSON config
    '*.resx'                   # Resource files
)

Write-Host "Scanning for source files in: $RootFolder" -ForegroundColor Yellow
Write-Host "Extensions: $($extensions -join ', ')" -ForegroundColor Gray
Write-Host ""

# Find all matching files, excluding bin/obj/bin
$files = @()
foreach ($ext in $extensions) {
    $found = Get-ChildItem -Path $RootFolder -Filter $ext -Recurse -File | 
        Where-Object {
            $path = $_.FullName
            -not ($path -match '\\bin\\' -or $path -match '\\obj\\' -or $path -match '\\.git\\')
        }
    $files += $found
}

$files = $files | Sort-Object -Property FullName -Unique

Write-Host "Found $($files.Count) files" -ForegroundColor Green
Write-Host ""

if ($files.Count -eq 0) {
    Write-Warning "No files found matching extensions"
    exit 1
}

# Create ZIP file
Write-Host "Creating ZIP file: $OutputFile" -ForegroundColor Yellow

if (Test-Path $OutputFile) {
    Remove-Item $OutputFile -Force
}

# Use PowerShell's Compress-Archive for simplicity
Compress-Archive -Path $files.FullName -DestinationPath $OutputFile -Force

$zipSize = (Get-Item $OutputFile).Length
Write-Host ""
Write-Host "ZIP created: $($zipSize / 1MB) MB" -ForegroundColor Green
Write-Host ""

# If requested, create restore script
if ($CreateRestoreScript) {
    Write-Host "Creating restore script: $RestoreScript" -ForegroundColor Yellow
    
    # Base64 encode the ZIP
    $zipBytes = [System.IO.File]::ReadAllBytes($OutputFile)
    $zipBase64 = [System.Convert]::ToBase64String($zipBytes)
    
    $base64Size = $zipBase64.Length / 1MB
    Write-Host "Base64 encoded: $([Math]::Round($base64Size, 2)) MB" -ForegroundColor Gray
    Write-Host ""
    
    # Create restore script
    $restoreContent = @'
# Restore-SourceFiles.ps1
# Generated: {TIMESTAMP}
# 
# Usage: 
#   1. Copy this file to the target machine (or paste content)
#   2. Run: .\Restore-SourceFiles.ps1 -RootFolder "C:\path\to\SecurityExtension"
#
# This script will extract the embedded ZIP to your folder structure

param(
    [Parameter(Mandatory=$true)]
    [string]$RootFolder
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $RootFolder)) {
    Write-Error "Root folder not found: $RootFolder"
    exit 1
}

Write-Host "Restoring files to: $RootFolder" -ForegroundColor Cyan

# Embedded base64-encoded ZIP data
$zipBase64 = @"
{ZIPBASE64}
"@

# Decode and extract
Add-Type -AssemblyName System.Io.Compression.FileSystem

$zipBytes = [System.Convert]::FromBase64String($zipBase64)
$zipPath = Join-Path $env:TEMP "SourceFiles_$(Get-Random).zip"
[System.IO.File]::WriteAllBytes($zipPath, $zipBytes)

Write-Host "Extracting from $zipPath to $RootFolder" -ForegroundColor Yellow

[System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $RootFolder, $true)

Remove-Item $zipPath -Force
Write-Host "Done!" -ForegroundColor Green
'@
    
    # Now replace placeholders
    $restoreContent = $restoreContent.Replace('{TIMESTAMP}', (Get-Date))
    $restoreContent = $restoreContent.Replace('{ZIPBASE64}', $zipBase64)
    
    Set-Content -Path $RestoreScript -Value $restoreContent -Encoding UTF8
    
    $scriptSize = (Get-Item $RestoreScript).Length
    Write-Host "Restore script created: $($scriptSize / 1KB) KB" -ForegroundColor Green
    Write-Host ""
}

Write-Host "================================" -ForegroundColor Cyan
Write-Host "NEXT STEPS" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Email the restore script:" -ForegroundColor White
Write-Host "   $RestoreScript" -ForegroundColor Gray
Write-Host ""
Write-Host "2. On the target machine, save the restore script to a folder" -ForegroundColor White
Write-Host ""
Write-Host "3. Run the restore script:" -ForegroundColor White
Write-Host "   .\Restore-SourceFiles.ps1 -RootFolder `"C:\path\to\SecurityExtension`"" -ForegroundColor Gray
Write-Host ""
Write-Host "This will extract all files to the same folder structure." -ForegroundColor White
Write-Host ""
