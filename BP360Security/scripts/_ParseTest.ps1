$scriptDir = 'C:\Users\joeka\OneDrive\Documents\GitHub\SSRS\BP360Security\scripts'
$scripts = Get-ChildItem -Path $scriptDir -Filter '*.ps1' | Where-Object { $_.Name -notlike '_*' }

$allOk = $true
foreach ($s in $scripts) {
    $errors = $null
    $tokens = $null
    [System.Management.Automation.Language.Parser]::ParseFile($s.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -eq 0) {
        Write-Host "  OK: $($s.Name)" -ForegroundColor Green
    } else {
        $allOk = $false
        Write-Host "  ERRORS in $($s.Name):" -ForegroundColor Red
        foreach ($e in $errors) {
            Write-Host "    Line $($e.Extent.StartLineNumber): $($e.Message)" -ForegroundColor Yellow
        }
    }
}

if ($allOk) {
    Write-Host ''
    Write-Host 'All scripts parse cleanly.' -ForegroundColor Green
} else {
    Write-Host ''
    Write-Host 'Parse errors found — fix before deploying.' -ForegroundColor Red
    exit 1
}
