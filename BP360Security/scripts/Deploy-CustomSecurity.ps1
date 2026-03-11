# Deploy-CustomSecurity.ps1
# Deploys the SSRS Custom Security Extension for SSRS 2019 Native Mode.
# No IIS required — SSRS self-hosts the portal and ReportServer via HTTP.sys.
#
# USAGE:
#   Run as Administrator on the target server.
#   Defaults are auto-detected from Environment.ps1 based on $env:COMPUTERNAME.
#   Override any param explicitly if needed:
#     .\Deploy-CustomSecurity.ps1 -ServiceAccount "DOMAIN\svc" -SkipDatabase

param(
    [string]$SsrsRoot       = '',   # auto-detected from Environment.ps1
    [string]$SqlServer      = '',   # auto-detected from Environment.ps1
    [string]$ServiceAccount = '',   # SSRS service account — NOT the developer's login
    [switch]$SkipBuild,
    [switch]$SkipDatabase
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error 'This script must be run as Administrator.'
    exit 1
}

# ── Auto-detect server environment ────────────────────────────────────────
. (Join-Path $PSScriptRoot 'Environment.ps1')
$_prof = Get-ServerProfile
if (-not $SsrsRoot)       { $SsrsRoot       = $_prof.SsrsInstallRoot }
if (-not $SqlServer)      { $SqlServer       = $_prof.SqlServer }
if (-not $ServiceAccount) { $ServiceAccount  = $_prof.ServiceAccount }

$repoRoot       = Split-Path -Parent $PSScriptRoot
$projectFile    = Join-Path $repoRoot 'BP360Security.csproj'
$dllName        = 'BancPac.ReportingServices.BP360.dll'
$pdbName        = 'BancPac.ReportingServices.BP360.pdb'
$builtDll       = Join-Path $repoRoot "bin\Release\$dllName"
$builtPdb       = Join-Path $repoRoot "bin\Release\$pdbName"
$rsDir          = Join-Path $SsrsRoot 'SSRS\ReportServer'
$rssBinDir      = Join-Path $rsDir 'bin'
$portalDir      = Join-Path $SsrsRoot 'SSRS\Portal'
$serviceName    = 'SQLServerReportingServices'

Write-Host '================================================' -ForegroundColor Cyan
Write-Host 'SSRS 2019 Custom Security Deployment' -ForegroundColor Cyan
Write-Host "Server          : $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host "Service account : $ServiceAccount" -ForegroundColor Cyan
Write-Host "SQL Server      : $SqlServer" -ForegroundColor Cyan
Write-Host '================================================' -ForegroundColor Cyan
Write-Host ''

# Warn if service account is blank (unknown server)
if ([string]::IsNullOrWhiteSpace($ServiceAccount)) {
    Write-Warning 'Service account not resolved. Add this server to Environment.ps1 or pass -ServiceAccount explicitly.'
    $ServiceAccount = Read-Host 'Enter SSRS service account (e.g. DOMAIN\ssrssvc)'
}

# ---------------------------------------------------------------------------
# Step 1: Build
# ---------------------------------------------------------------------------
Write-Host '[1/8] Building extension DLL' -ForegroundColor Yellow

if ($SkipBuild) {
    Write-Host '  Skipped (-SkipBuild)' -ForegroundColor Gray
} else {
    $buildScript = Join-Path $PSScriptRoot 'Build-CustomSecurity.ps1'
    if (Test-Path $buildScript) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $buildScript -Configuration Release
    } else {
        if (-not (Test-Path $projectFile)) {
            Write-Error "Project file not found: $projectFile"
            exit 1
        }
        $msbuild = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" `
            -latest -products '*' -requires Microsoft.Component.MSBuild `
            -find 'MSBuild\**\Bin\MSBuild.exe' 2>$null | Select-Object -First 1
        if ($msbuild -and (Test-Path $msbuild)) {
            & $msbuild $projectFile /p:Configuration=Release /p:Platform=AnyCPU /t:Rebuild
        } else {
            dotnet build $projectFile --configuration Release
        }
    }
    if ($LASTEXITCODE -ne 0) { Write-Error 'Build failed.'; exit 1 }
}

if (-not (Test-Path $builtDll)) {
    Write-Error "Built DLL not found: $builtDll"
    exit 1
}
Write-Host "  DLL: $builtDll" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Step 2: Create UserAccounts database
# ---------------------------------------------------------------------------
Write-Host '[2/8] Creating UserAccounts database' -ForegroundColor Yellow

if ($SkipDatabase) {
    Write-Host '  Skipped (-SkipDatabase)' -ForegroundColor Gray
} else {
    $createDbSql = Join-Path $repoRoot 'Setup\CreateUserStore.sql'
    if (-not (Test-Path $createDbSql)) {
        Write-Warning "CreateUserStore.sql not found at $createDbSql — skipping"
    } else {
        $exists = sqlcmd -S $SqlServer -E -Q "SET NOCOUNT ON; SELECT 1 FROM sys.databases WHERE name='UserAccounts'" -h -1 -W 2>$null
        if ($exists -and ($exists -join '').Trim() -eq '1') {
            Write-Host '  UserAccounts database already exists' -ForegroundColor Green
        } else {
            sqlcmd -S $SqlServer -E -i $createDbSql -b
            if ($LASTEXITCODE -ne 0) { Write-Error 'Failed to create UserAccounts database'; exit 1 }
            Write-Host '  UserAccounts database created' -ForegroundColor Green
        }
    }
}

# ---------------------------------------------------------------------------
# Step 3: Grant service account access to UserAccounts DB
# NOTE: This grants permissions to the SSRS service account ($ServiceAccount),
#       NOT to the developer running this script. Those are different accounts.
# ---------------------------------------------------------------------------
Write-Host '[3/8] Granting DB access to service account' -ForegroundColor Yellow

$grantSql = @"
USE [UserAccounts];
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'$ServiceAccount')
    CREATE USER [$ServiceAccount] FOR LOGIN [$ServiceAccount];
IF NOT EXISTS (SELECT 1 FROM sys.database_permissions dp
    JOIN sys.objects o ON dp.major_id = o.object_id
    JOIN sys.database_principals pr ON dp.grantee_principal_id = pr.principal_id
    WHERE pr.name = N'$ServiceAccount' AND o.name = 'LookupUser' AND dp.permission_name = 'EXECUTE')
BEGIN
    GRANT EXECUTE ON dbo.LookupUser   TO [$ServiceAccount];
    GRANT EXECUTE ON dbo.RegisterUser TO [$ServiceAccount];
END
"@
try {
    sqlcmd -S $SqlServer -E -Q $grantSql -b | Out-Null
    Write-Host "  EXECUTE granted to $ServiceAccount on LookupUser, RegisterUser" -ForegroundColor Green
} catch {
    Write-Warning "Could not grant DB permissions: $_"
}

# ---------------------------------------------------------------------------
# Step 4: Backup current config files
# ---------------------------------------------------------------------------
Write-Host '[4/8] Backing up configuration files' -ForegroundColor Yellow

$backupScript = Join-Path $PSScriptRoot 'Backup-Config.ps1'
if (Test-Path $backupScript) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $backupScript -SsrsRoot $SsrsRoot
    if ($LASTEXITCODE -ne 0) { Write-Warning 'Backup reported errors — continuing anyway' }
} else {
    Write-Warning "Backup-Config.ps1 not found at $backupScript — skipping backup"
}

# ---------------------------------------------------------------------------
# Step 5: Stop SSRS
# ---------------------------------------------------------------------------
Write-Host '[5/8] Stopping SSRS service' -ForegroundColor Yellow

$svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq 'Running') {
    Stop-Service -Name $serviceName -Force
    Write-Host '  SSRS stopped' -ForegroundColor Green
} elseif (-not $svc) {
    Write-Warning "Service '$serviceName' not found"
}

# ---------------------------------------------------------------------------
# Step 6: Copy DLL + Logon.aspx
# ---------------------------------------------------------------------------
Write-Host '[6/8] Copying files to SSRS directories' -ForegroundColor Yellow

foreach ($f in @($builtDll, $builtPdb)) {
    if (Test-Path $f) {
        Copy-Item $f -Destination $rssBinDir -Force
        Write-Host "  ReportServer\bin\$(Split-Path $f -Leaf)" -ForegroundColor Green
    }
}

foreach ($f in @($builtDll, $builtPdb)) {
    if (Test-Path $f) {
        Copy-Item $f -Destination $portalDir -Force
        Write-Host "  Portal\$(Split-Path $f -Leaf)" -ForegroundColor Green
    }
}

$logonSrc = Join-Path $repoRoot 'Logon.aspx'
if (Test-Path $logonSrc) {
    Copy-Item $logonSrc -Destination $rsDir -Force
    Write-Host "  ReportServer\Logon.aspx" -ForegroundColor Green
} else {
    Write-Warning "Logon.aspx not found at $logonSrc"
}

# ---------------------------------------------------------------------------
# Step 7: Apply configuration changes
# ---------------------------------------------------------------------------
Write-Host '[7/8] Applying configuration' -ForegroundColor Yellow

$configScript = Join-Path $PSScriptRoot 'Configure-CustomSecurity.ps1'
if (-not (Test-Path $configScript)) {
    Write-Error "Configure-CustomSecurity.ps1 not found at $configScript"
    exit 1
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $configScript `
    -SsrsRoot $SsrsRoot `
    -SqlServer $SqlServer `
    -ServiceAccount $ServiceAccount `
    -StartService

if ($LASTEXITCODE -ne 0) {
    Write-Error "Configure-CustomSecurity.ps1 failed (exit $LASTEXITCODE)"
    exit 1
}

# ---------------------------------------------------------------------------
# Step 8: Register users
# ---------------------------------------------------------------------------
Write-Host '[8/8] Register users' -ForegroundColor Yellow

$setupScript = Join-Path $PSScriptRoot 'Setup-Users.ps1'
if (Test-Path $setupScript) {
    # 8a — direct-login test users (logon.aspx)
    Write-Host 'Create direct-login test users (testuser, admin, report_viewer)? [Y/N, default Y]: ' -ForegroundColor Yellow -NoNewline
    $resp = Read-Host
    if ($resp -notmatch '^[Nn]') {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $setupScript -CreateTestUsers -Integrated -SqlServer $SqlServer
        if ($LASTEXITCODE -eq 0) {
            Write-Host '  Direct-login users: testuser/Test@123, admin/Admin@123, report_viewer/Viewer@123' -ForegroundColor Green
        } else {
            Write-Warning 'Failed to create direct-login test users. Run manually: .\scripts\Setup-Users.ps1 -CreateTestUsers -Integrated'
        }
    } else {
        Write-Host '  Skipped direct-login users.' -ForegroundColor Gray
    }

    # 8b — bank-scoped test users (UILogon.aspx / Key1 flow)
    Write-Host ''
    Write-Host 'Create bank-scoped test users for UILogon (BNBR=004)? [Y/N, default Y]: ' -ForegroundColor Yellow -NoNewline
    $resp2 = Read-Host
    if ($resp2 -notmatch '^[Nn]') {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $setupScript -CreateBankTestUsers -BankNumber '004' -Integrated -SqlServer $SqlServer
        if ($LASTEXITCODE -eq 0) {
            Write-Host '  Bank-scoped users: UID=testuser/Test@123, UID=admin/Admin@123, UID=report_viewer/Viewer@123 (BNBR=004)' -ForegroundColor Green
        } else {
            Write-Warning 'Failed to create bank-scoped test users. Run manually: .\scripts\Setup-Users.ps1 -CreateBankTestUsers -BankNumber 004 -Integrated'
        }
    } else {
        Write-Host '  Skipped bank-scoped users.' -ForegroundColor Gray
    }
} else {
    Write-Warning "Setup-Users.ps1 not found at $setupScript"
}

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '================================================' -ForegroundColor Cyan
Write-Host 'Deployment complete.' -ForegroundColor Green
Write-Host ''
Write-Host 'Next steps:' -ForegroundColor Cyan
Write-Host "  1. Open browser: $($_prof.PortalUrl)" -ForegroundColor White
Write-Host '  2. Log in with a registered user account' -ForegroundColor White
Write-Host '  3. Test UILogon (WPF/server-to-server):' -ForegroundColor White
Write-Host '       .\scripts\Test-UILogon.ps1 -UID testuser -PWD Test@123 -BNBR 004' -ForegroundColor Gray
Write-Host "  4. Check logs if issues: $SsrsRoot\SSRS\LogFiles\RSPortal_*.log" -ForegroundColor White
Write-Host '================================================' -ForegroundColor Cyan
