# Import-SSRSContent.ps1
# Run on the TARGET server (VMLENOVO) as Administrator.
# Reads the ZIP package produced by Export-SSRSContent.ps1 and uploads
# folders, reports, data sources, and models to SSRS 2019 via REST API.
#
# USAGE:
#   .\Import-SSRSContent.ps1 -PackagePath C:\Temp\SSRSExport.zip -AdminUID 999-admin -AdminPWD Admin@123
#
# PREREQUISITES:
#   - Fill in DataSourceConnections.json in the ZIP before running.
#   - The admin user must exist in UserAccounts DB and have Content Manager role in SSRS.
#   - UILogon.Key1 must be configured in dll.config.

param(
    [Parameter(Mandatory=$true)]
    [string]$PackagePath,

    [string]$SsrsBaseUrl  = 'http://vmlenovo',
    [string]$UILogonPath  = '/ReportServer/UILogon.aspx',

    [Parameter(Mandatory=$true)]
    [string]$AdminUID,        # SSRS username (e.g. 999-admin for Key1, or admin for Key2)

    [Parameter(Mandatory=$true)]
    [string]$AdminPWD,

    [string]$AdminBNBR    = '999',   # bank number — use '' if logging in via Key2
    [string]$UILogonKey   = '',      # leave blank to read from dll.config automatically
    [string]$SqlServer    = 'localhost',   # SQL Server for UserAccounts DB on target
    [string]$UserDatabase = 'UserAccounts',
    [string]$ExtractPath  = '',      # leave blank to auto-extract to Temp
    [switch]$SkipUsers,              # skip user import
    [switch]$WhatIf                  # dry run — shows what would be imported
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$restBase = "$($SsrsBaseUrl.TrimEnd('/'))/ReportServer/api/v2.0"

Write-Host '================================================' -ForegroundColor Cyan
Write-Host 'SSRS Content Import' -ForegroundColor Cyan
Write-Host "Target    : $SsrsBaseUrl" -ForegroundColor Cyan
Write-Host "Package   : $PackagePath" -ForegroundColor Cyan
if ($WhatIf) { Write-Host '  *** DRY RUN — no changes will be made ***' -ForegroundColor Yellow }
Write-Host '================================================' -ForegroundColor Cyan
Write-Host ''

# ── Read UILogon key from dll.config if not supplied ─────────────────────────
if ([string]::IsNullOrWhiteSpace($UILogonKey)) {
    $dllConfig = 'C:\Program Files\Microsoft SQL Server Reporting Services\SSRS\ReportServer\bin\BancPac.ReportingServices.BP360.dll.config'
    if (Test-Path $dllConfig) {
        [xml]$cfg = Get-Content $dllConfig -Raw
        $UILogonKey = $cfg.SelectSingleNode('//add[@key="UILogon.Key1"]')?.GetAttribute('value')
        if ([string]::IsNullOrWhiteSpace($UILogonKey)) {
            Write-Error 'UILogon.Key1 not found in dll.config and -UILogonKey not supplied.'
            exit 1
        }
        Write-Host "  UILogon.Key1 read from dll.config" -ForegroundColor Gray
    } else {
        Write-Error "dll.config not found. Pass -UILogonKey explicitly."
        exit 1
    }
}

# ── Extract ZIP ───────────────────────────────────────────────────────────────
Write-Host '[1/6] Extracting package...' -ForegroundColor Yellow

if ([string]::IsNullOrWhiteSpace($ExtractPath)) {
    $ExtractPath = Join-Path $env:TEMP "SSRSImport_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
}
if (Test-Path $ExtractPath) { Remove-Item $ExtractPath -Recurse -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($PackagePath, $ExtractPath)
Write-Host "  Extracted to: $ExtractPath" -ForegroundColor Green

$manifest = Get-Content (Join-Path $ExtractPath 'manifest.json') -Raw | ConvertFrom-Json
$dsConnFile = Join-Path $ExtractPath 'DataSourceConnections.json'

if (-not (Test-Path $dsConnFile)) {
    Write-Warning 'DataSourceConnections.json not found — data sources will be skipped.'
    $dsConnections = @{}
} else {
    $dsConnections = Get-Content $dsConnFile -Raw | ConvertFrom-Json
    # Check for unfilled placeholders
    $unfilled = @($dsConnections.PSObject.Properties | Where-Object {
        $_.Value.ConnectionString -eq 'FILL_IN_CONNECTION_STRING'
    })
    if ($unfilled.Count -gt 0) {
        Write-Warning "$($unfilled.Count) data source(s) still have placeholder connection strings:"
        $unfilled | ForEach-Object { Write-Warning "  $($_.Name)" }
        Write-Warning 'These will be imported with empty connection strings — update them in SSRS after import.'
    }
}

# ── Authenticate — get sqlAuthCookie ─────────────────────────────────────────
Write-Host '[2/7] Authenticating to SSRS...' -ForegroundColor Yellow

$uiLogonUrl = "$($SsrsBaseUrl.TrimEnd('/'))$UILogonPath"
$body = @{ UID = $AdminUID; PWD = $AdminPWD; BNBR = $AdminBNBR; KEY = $UILogonKey }

try {
    $authResp = Invoke-WebRequest -Uri $uiLogonUrl -Method POST -Body $body `
        -SessionVariable 'WebSession' -UseBasicParsing -ErrorAction Stop

    if ($authResp.StatusCode -ne 200 -or $authResp.Content -notmatch '"success":true') {
        Write-Error "UILogon failed: HTTP $($authResp.StatusCode) — $($authResp.Content)"
        exit 1
    }
    Write-Host "  Authenticated as $AdminUID" -ForegroundColor Green
} catch {
    Write-Error "Authentication failed: $_"
    exit 1
}

# ── Helper: REST API call with cookie session ─────────────────────────────────
function Invoke-SSRS {
    param(
        [string]$Method,
        [string]$Endpoint,
        [object]$Body = $null
    )
    $uri    = "$restBase/$($Endpoint.TrimStart('/'))"
    $params = @{
        Uri         = $uri
        Method      = $Method
        WebSession  = $WebSession
        ContentType = 'application/json'
        UseBasicParsing = $true
        ErrorAction = 'Stop'
    }
    if ($Body) { $params.Body = ($Body | ConvertTo-Json -Depth 10) }
    return Invoke-RestMethod @params
}

function Test-SSRSExists {
    param([string]$Path)
    try {
        $encoded = [Uri]::EscapeDataString($Path)
        Invoke-SSRS -Method GET -Endpoint "CatalogItems(Path='$encoded')" | Out-Null
        return $true
    } catch { return $false }
}

# ── Import users into UserAccounts DB ────────────────────────────────────────
Write-Host '[3/7] Importing users...' -ForegroundColor Yellow

$usersFile = Join-Path $ExtractPath 'users.json'
if ($SkipUsers) {
    Write-Host '  Skipped (-SkipUsers)' -ForegroundColor Gray
} elseif (-not (Test-Path $usersFile)) {
    Write-Warning '  users.json not found in package — skipping user import.'
} else {
    $users = Get-Content $usersFile -Raw | ConvertFrom-Json

    if ($WhatIf) {
        Write-Host "  Would import $($users.Count) users (dry run)" -ForegroundColor Gray
    } else {
        $conn = New-Object System.Data.SqlClient.SqlConnection
        $conn.ConnectionString = "Server=$SqlServer;Integrated Security=SSPI;"
        $conn.Open()

        $imported = 0; $skipped = 0; $userErrors = 0
        foreach ($u in $users) {
            # Check if user already exists
            $checkCmd = $conn.CreateCommand()
            $checkCmd.CommandText = "SELECT COUNT(1) FROM [$UserDatabase].[dbo].[Users] WHERE UserName = @u"
            $checkCmd.Parameters.AddWithValue('@u', $u.UserName) | Out-Null
            $exists = [int]$checkCmd.ExecuteScalar()

            if ($exists -gt 0) {
                Write-Host "  [User] $($u.UserName) — already exists, skipped" -ForegroundColor Gray
                $skipped++
                continue
            }

            try {
                $insCmd = $conn.CreateCommand()
                $insCmd.CommandText = @"
INSERT INTO [$UserDatabase].[dbo].[Users] (UserName, BankNumber, PasswordHash, salt)
VALUES (@UserName, @BankNumber, @PasswordHash, @salt)
"@
                $insCmd.Parameters.AddWithValue('@UserName',     $u.UserName)     | Out-Null
                $insCmd.Parameters.AddWithValue('@BankNumber',   if ($null -eq $u.BankNumber) { [DBNull]::Value } else { $u.BankNumber }) | Out-Null
                $insCmd.Parameters.AddWithValue('@PasswordHash', $u.PasswordHash) | Out-Null
                $insCmd.Parameters.AddWithValue('@salt',         $u.Salt)         | Out-Null
                $insCmd.ExecuteNonQuery() | Out-Null
                Write-Host "  [User] $($u.UserName) — imported" -ForegroundColor Green
                $imported++
            } catch {
                Write-Warning "  [User] $($u.UserName) — failed: $_"
                $userErrors++
            }
        }
        $conn.Close()
        Write-Host "  Users: $imported imported, $skipped skipped, $userErrors errors" -ForegroundColor $(if ($userErrors) { 'Yellow' } else { 'Green' })
    }
}

# ── Sort items: folders first, then by path depth ────────────────────────────
$TYPE_FOLDER     = 1
$TYPE_REPORT     = 2
$TYPE_DATASOURCE = 5
$TYPE_MODEL      = 7

$folders     = @($manifest.Items | Where-Object { $_.Type -eq $TYPE_FOLDER     } | Sort-Object { $_.Path.Split('/').Count })
$dataSources = @($manifest.Items | Where-Object { $_.Type -eq $TYPE_DATASOURCE } | Sort-Object { $_.Path })
$reports     = @($manifest.Items | Where-Object { $_.Type -eq $TYPE_REPORT     } | Sort-Object { $_.Path })
$models      = @($manifest.Items | Where-Object { $_.Type -eq $TYPE_MODEL      } | Sort-Object { $_.Path })

$counts = @{ Folders = 0; Reports = 0; DataSources = 0; Models = 0; Skipped = 0; Errors = 0 }

# ── Step 3: Create folders ────────────────────────────────────────────────────
Write-Host '[4/7] Creating folders...' -ForegroundColor Yellow

foreach ($item in $folders) {
    if ($item.Path -in @('/', '/Users Folders', '/My Reports')) { continue }

    $parentPath = ($item.Path -split '/' | Select-Object -SkipLast 1) -join '/'
    if ([string]::IsNullOrEmpty($parentPath)) { $parentPath = '/' }

    Write-Host "  [Folder] $($item.Path)" -ForegroundColor Gray

    if ($WhatIf) { $counts.Folders++; continue }

    if (Test-SSRSExists -Path $item.Path) {
        Write-Host "    Already exists — skipped" -ForegroundColor Gray
        continue
    }

    try {
        Invoke-SSRS -Method POST -Endpoint 'Folders' -Body @{
            Name        = $item.Name
            Path        = $item.Path
            Description = ''
        } | Out-Null
        $counts.Folders++
        Write-Host "    Created" -ForegroundColor Green
    } catch {
        Write-Warning "    Failed to create folder $($item.Path): $_"
        $counts.Errors++
    }
}

# ── Step 4: Create data sources ───────────────────────────────────────────────
Write-Host '[5/7] Creating data sources...' -ForegroundColor Yellow

foreach ($item in $dataSources) {
    $parentPath = ($item.Path -split '/' | Select-Object -SkipLast 1) -join '/'
    if ([string]::IsNullOrEmpty($parentPath)) { $parentPath = '/' }

    # Look up connection info from DataSourceConnections.json
    $connInfo = $dsConnections.PSObject.Properties |
        Where-Object { $_.Name -eq $item.Path } |
        Select-Object -First 1 -ExpandProperty Value

    $connString = if ($connInfo -and $connInfo.ConnectionString -ne 'FILL_IN_CONNECTION_STRING') {
        $connInfo.ConnectionString
    } else { '' }
    $extension  = if ($connInfo) { $connInfo.Extension } else { 'SQL' }
    $credMode   = if ($connInfo) { $connInfo.CredentialRetrieval } else { 'None' }

    Write-Host "  [DataSource] $($item.Path)" -ForegroundColor $(if ($connString) { 'Green' } else { 'Yellow' })
    if (-not $connString) { Write-Host "    *** No connection string — will need manual update in SSRS ***" -ForegroundColor Yellow }

    if ($WhatIf) { $counts.DataSources++; continue }

    if (Test-SSRSExists -Path $item.Path) {
        Write-Host "    Already exists — skipped" -ForegroundColor Gray
        continue
    }

    try {
        $dsBody = @{
            Name                = $item.Name
            Path                = $item.Path
            Description         = ''
            DataSourceType      = $extension
            ConnectionString    = $connString
            CredentialRetrieval = $credMode
            IsEnabled           = $true
        }
        if ($connInfo -and $credMode -eq 'Store') {
            $dsBody.UserName = $connInfo.UserName
            $dsBody.Password = $connInfo.Password
        }
        Invoke-SSRS -Method POST -Endpoint 'DataSources' -Body $dsBody | Out-Null
        $counts.DataSources++
        Write-Host "    Created" -ForegroundColor Green
    } catch {
        Write-Warning "    Failed to create data source $($item.Path): $_"
        $counts.Errors++
    }
}

# ── Step 5: Upload reports ────────────────────────────────────────────────────
Write-Host '[6/7] Uploading reports...' -ForegroundColor Yellow

foreach ($item in $reports) {
    if ([string]::IsNullOrEmpty($item.File)) { $counts.Skipped++; continue }

    $rdlPath = Join-Path $ExtractPath $item.File
    if (-not (Test-Path $rdlPath)) {
        Write-Warning "  RDL file not found: $rdlPath — skipping"
        $counts.Skipped++
        continue
    }

    $parentPath = ($item.Path -split '/' | Select-Object -SkipLast 1) -join '/'
    if ([string]::IsNullOrEmpty($parentPath)) { $parentPath = '/' }

    Write-Host "  [Report] $($item.Path)" -ForegroundColor Gray

    if ($WhatIf) { $counts.Reports++; continue }

    try {
        $rdlBytes   = [System.IO.File]::ReadAllBytes($rdlPath)
        $rdlBase64  = [Convert]::ToBase64String($rdlBytes)

        Invoke-SSRS -Method POST -Endpoint 'Reports' -Body @{
            Name        = $item.Name
            Path        = $item.Path
            Description = ''
            Content     = $rdlBase64
        } | Out-Null
        $counts.Reports++
        Write-Host "    Uploaded" -ForegroundColor Green
    } catch {
        Write-Warning "    Failed to upload report $($item.Path): $_"
        $counts.Errors++
    }
}

# ── Step 6: Upload models ─────────────────────────────────────────────────────
Write-Host '[7/7] Uploading models...' -ForegroundColor Yellow

foreach ($item in $models) {
    if ([string]::IsNullOrEmpty($item.File)) { $counts.Skipped++; continue }

    $smdlPath = Join-Path $ExtractPath $item.File
    if (-not (Test-Path $smdlPath)) {
        Write-Warning "  SMDL file not found: $smdlPath — skipping"
        $counts.Skipped++
        continue
    }

    Write-Host "  [Model] $($item.Path)" -ForegroundColor Gray

    if ($WhatIf) { $counts.Models++; continue }

    try {
        $smdlBytes  = [System.IO.File]::ReadAllBytes($smdlPath)
        $smdlBase64 = [Convert]::ToBase64String($smdlBytes)

        # Models use the generic CatalogItem upload endpoint in SSRS 2019
        Invoke-SSRS -Method POST -Endpoint 'Reports' -Body @{
            Name        = $item.Name
            Path        = $item.Path
            Description = ''
            Content     = $smdlBase64
        } | Out-Null
        $counts.Models++
        Write-Host "    Uploaded" -ForegroundColor Green
    } catch {
        Write-Warning "    Failed to upload model $($item.Path): $_"
        $counts.Errors++
    }
}

# ── Cleanup temp folder ───────────────────────────────────────────────────────
if ($ExtractPath -like "$env:TEMP\SSRSImport_*") {
    Remove-Item $ExtractPath -Recurse -Force -ErrorAction SilentlyContinue
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '================================================' -ForegroundColor Cyan
Write-Host $(if ($WhatIf) { 'Dry run complete (no changes made).' } else { 'Import complete.' }) -ForegroundColor Green
Write-Host "  Folders     : $($counts.Folders)"
Write-Host "  Data Sources: $($counts.DataSources)"
Write-Host "  Reports     : $($counts.Reports)"
Write-Host "  Models      : $($counts.Models)"
Write-Host "  Skipped     : $($counts.Skipped)"
if ($counts.Errors -gt 0) {
    Write-Host "  Errors      : $($counts.Errors)" -ForegroundColor Red
    Write-Host '  Review warnings above and re-run failed items manually.' -ForegroundColor Yellow
}
Write-Host ''
Write-Host 'Next steps:' -ForegroundColor Cyan
Write-Host "  1. Open $SsrsBaseUrl/Reports and verify folder/report structure"
Write-Host '  2. Update any data sources that had empty connection strings'
Write-Host '  3. Test report rendering'
Write-Host '================================================' -ForegroundColor Cyan
