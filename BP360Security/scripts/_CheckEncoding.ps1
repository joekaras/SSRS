$path = 'C:\Users\joeka\OneDrive\Documents\GitHub\SSRS\BP360Security\scripts\Deploy-CustomSecurity.ps1'
$lines = [System.IO.File]::ReadAllLines($path)

# Check lines 124-136 (here-string) and 224-228, 251-253
$checkLines = @(123..135) + @(223..227) + @(250..252)
foreach ($i in $checkLines) {
    $line = $lines[$i]
    $lineNum = $i + 1
    $hasNonAscii = $line -match '[^\x00-\x7F]'
    $hexStr = ([System.Text.Encoding]::UTF8.GetBytes($line) | ForEach-Object { $_.ToString('X2') }) -join ' '
    if ($hasNonAscii) {
        Write-Host "LINE $lineNum [NON-ASCII]: $line" -ForegroundColor Red
        Write-Host "  HEX: $hexStr"
    } else {
        Write-Host "LINE $lineNum [ok]: $line"
    }
}
