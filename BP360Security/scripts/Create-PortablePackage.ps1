# Create-PortablePackage.ps1
# Creates a single self-contained PowerShell script that can be emailed
# and executed on another machine to restore all source files

param(
    [string]$RootFolder = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$OutputScript = "$RootFolder\Restore-AllFiles.ps1"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "================================" -ForegroundColor Cyan
Write-Host "Create Portable Package" -ForegroundColor Cyan
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

# Find all matching files, excluding bin/obj/.git
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

# Build the manifest
Write-Host "Encoding files to base64..." -ForegroundColor Yellow
$manifest = @()
$totalSize = 0

foreach ($file in $files) {
    $relativePath = $file.FullName.Substring($RootFolder.Length).TrimStart('\')
    $content = [System.IO.File]::ReadAllBytes($file.FullName)
    $base64 = [System.Convert]::ToBase64String($content)
    $totalSize += $content.Length
    
    Write-Host "  $relativePath ($($content.Length) bytes)"
    
    $manifest += @{
        Path = $relativePath
        Base64 = $base64
    }
}

Write-Host ""
Write-Host "Total uncompressed size: $([Math]::Round($totalSize / 1MB, 2)) MB" -ForegroundColor Green
Write-Host ""

# Generate the restore script
Write-Host "Generating restore script: $OutputScript" -ForegroundColor Yellow

$scriptContent = @'
# Restore-AllFiles.ps1
# Auto-generated manifest-based restore script
# 
# USAGE:
#   .\Restore-AllFiles.ps1 -RootFolder "C:\path\to\SecurityExtension"
#
# This script will restore all source files to the original folder structure

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
Write-Host ""

# File manifest: array of [Path, Base64] pairs
$manifest = @(
'@

# Add each file to the manifest
foreach ($item in $manifest) {
    $path = $item.Path
    $base64 = $item.Base64
    $scriptContent += "`n    @{ Path = '$path'; Base64 = `n@`"`n$base64`n`"@ },"
}

# Remove trailing comma from last entry
$scriptContent = $scriptContent.TrimEnd(',')

$scriptContent += @'
)

# Restore each file
$count = 0
foreach ($entry in $manifest) {
    $filePath = Join-Path $RootFolder $entry.Path
    $folderPath = Split-Path -Parent $filePath
    
    # Create folder if it doesn't exist
    if (-not (Test-Path $folderPath)) {
        New-Item -ItemType Directory -Path $folderPath -Force | Out-Null
    }
    
    # Decode and write file
    $bytes = [System.Convert]::FromBase64String($entry.Base64)
    [System.IO.File]::WriteAllBytes($filePath, $bytes)
    
    Write-Host "  Restored $($entry.Path)"
    $count++
}

Write-Host ""
Write-Host "Restored $count files" -ForegroundColor Green
Write-Host "Done!" -ForegroundColor Green
'@

# Write the script
Set-Content -Path $OutputScript -Value $scriptContent -Encoding UTF8

$scriptSize = (Get-Item $OutputScript).Length
Write-Host "Restore script size: $($scriptSize / 1KB) KB" -ForegroundColor Green
Write-Host ""

Write-Host "================================" -ForegroundColor Cyan
Write-Host "NEXT STEPS" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Email this file to the target machine:" -ForegroundColor White
Write-Host "   $OutputScript" -ForegroundColor Gray
Write-Host ""
Write-Host "2. On the target machine, open PowerShell and run:" -ForegroundColor White
Write-Host "   .\Restore-AllFiles.ps1 -RootFolder `"C:\path\to\SecurityExtension`"" -ForegroundColor Gray
Write-Host ""
Write-Host "3. All files will be restored to the same folder structure" -ForegroundColor White
Write-Host ""
Write-Host "NOTE: The restore script is self-contained and requires no external files" -ForegroundColor Yellow
Write-Host ""
