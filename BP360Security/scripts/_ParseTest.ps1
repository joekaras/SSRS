$path = 'C:\Users\joeka\OneDrive\Documents\GitHub\SSRS\BP360Security\scripts\Deploy-CustomSecurity.ps1'
$errors = $null
$tokens = $null
[System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors.Count -eq 0) {
    Write-Host "Script parses cleanly." -ForegroundColor Green
} else {
    Write-Host "$($errors.Count) parse error(s):" -ForegroundColor Red
    foreach ($e in $errors) {
        Write-Host "  Line $($e.Extent.StartLineNumber): $($e.Message)" -ForegroundColor Yellow
    }
}
