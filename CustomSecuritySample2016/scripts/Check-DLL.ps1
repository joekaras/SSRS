# Check DLL types
$dllPath = 'C:\Program Files\Microsoft SQL Server Reporting Services\SSRS\ReportServer\bin\Microsoft.ReportingServices.CustomSecurity.dll'
$asm = [System.Reflection.Assembly]::LoadFile($dllPath)

Write-Host "Assembly: $($asm.FullName)" -ForegroundColor Cyan
Write-Host ""
Write-Host "Types with 'Extension' in name:" -ForegroundColor Yellow
$asm.GetTypes() | Where-Object { $_.Name -like '*Extension*' } | ForEach-Object {
    Write-Host "  $($_.FullName)" -ForegroundColor White
}

Write-Host ""
Write-Host "Types with 'Security' in name:" -ForegroundColor Yellow
$asm.GetTypes() | Where-Object { $_.Name -like '*Security*' } | ForEach-Object {
    Write-Host "  $($_.FullName)" -ForegroundColor White
}
