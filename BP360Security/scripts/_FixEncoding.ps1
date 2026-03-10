# Re-saves all .ps1 files in this folder with UTF-8 BOM so Windows PowerShell 5.1 reads them correctly.
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$utf8Bom = New-Object System.Text.UTF8Encoding $true  # $true = emit BOM

Get-ChildItem -Path $scriptDir -Filter '*.ps1' | Where-Object { $_.Name -notlike '_*' } | ForEach-Object {
    $content = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($_.FullName, $content, $utf8Bom)
    Write-Host "Fixed: $($_.Name)" -ForegroundColor Green
}
Write-Host "Done." -ForegroundColor Cyan
