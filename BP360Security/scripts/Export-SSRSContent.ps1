# Export-SSRSContent.ps1
# Run on the SOURCE server (vwmazbptestbp360) as Administrator.
# Reads folders, reports, data sources, models, and users directly from
# the Production SQL databases — no SSRS service required.
#
# Source databases on vwmazbptestbp360 (localhost when run on that server):
#   ReportServerProduction     — SSRS catalog (folders, reports, data sources, models)
#   UserAccountsProduction     — custom Forms Auth user store (users + password hashes)
#
# USAGE:
#   .\Export-SSRSContent.ps1
#   .\Export-SSRSContent.ps1 -SqlServer localhost -Database ReportServerProduction -UserDatabase UserAccountsProduction -OutputFolder C:\Temp\SSRSExport
#
# OUTPUT:
#   <OutputFolder>\
#     manifest.json              — folder/item inventory
#     users.json                 — users with hashed passwords (portable between servers)
#     reports\**\*.rdl           — report definitions (mirroring SSRS path)
#     models\**\*.smdl           — report models
#     datasources\**\*.json      — data source stubs (connection strings NOT included — encrypted in DB)
#     DataSourceConnections.json — fill this in before running Import-SSRSContent.ps1

param(
    [string]$SqlServer    = 'localhost',
    [string]$Database     = 'ReportServerProduction',
    [string]$UserDatabase = 'UserAccountsProduction',
    [string]$OutputFolder = 'C:\Temp\SSRSExport'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── SSRS type constants ──────────────────────────────────────────────────────
$TYPE_FOLDER     = 1
$TYPE_REPORT     = 2
$TYPE_DATASOURCE = 5
$TYPE_MODEL      = 7

# Paths to skip (SSRS system folders)
$SKIP_PATHS = @('/', '/Users Folders', '/My Reports')

Write-Host '================================================' -ForegroundColor Cyan
Write-Host 'SSRS Content Export' -ForegroundColor Cyan
Write-Host "Source DB : $SqlServer.$Database" -ForegroundColor Cyan
Write-Host "Output    : $OutputFolder" -ForegroundColor Cyan
Write-Host '================================================' -ForegroundColor Cyan
Write-Host ''

# ── Create output folders ────────────────────────────────────────────────────
foreach ($sub in @('reports', 'models', 'datasources')) {
    New-Item -ItemType Directory -Path (Join-Path $OutputFolder $sub) -Force | Out-Null
}

# ── Helper: decompress SSRS GZip content ────────────────────────────────────
function Expand-SSRSBytes {
    param([byte[]]$Bytes)
    $ms  = New-Object System.IO.MemoryStream(, $Bytes)
    $gz  = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionMode]::Decompress)
    $out = New-Object System.IO.MemoryStream
    $gz.CopyTo($out)
    $gz.Dispose(); $ms.Dispose()
    return [System.Text.Encoding]::UTF8.GetString($out.ToArray())
}

# ── Helper: safe file path from SSRS path ───────────────────────────────────
function ConvertTo-SafePath {
    param([string]$SsrsPath, [string]$Base, [string]$Extension)
    $rel  = $SsrsPath.TrimStart('/')
    $safe = $rel -replace '[\\/:*?"<>|]', '_'
    return Join-Path $Base "$safe$Extension"
}

# ── Query catalog ────────────────────────────────────────────────────────────
Write-Host '[1/4] Reading catalog from database...' -ForegroundColor Yellow

$query = @"
SELECT
    CONVERT(varchar(50), ItemID)  AS ItemID,
    Path,
    Name,
    Type,
    Content,
    CONVERT(varchar(50), ParentID) AS ParentID,
    CreationDate,
    ModifiedDate
FROM [$Database].[dbo].[Catalog]
WHERE Type IN ($TYPE_FOLDER, $TYPE_REPORT, $TYPE_DATASOURCE, $TYPE_MODEL)
ORDER BY LEN(Path) - LEN(REPLACE(Path, '/', '')), Path
"@

$conn = New-Object System.Data.SqlClient.SqlConnection
$conn.ConnectionString = "Server=$SqlServer;Integrated Security=SSPI;"
$conn.Open()

$cmd = $conn.CreateCommand()
$cmd.CommandText  = $query
$cmd.CommandTimeout = 120

$adapter = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
$table   = New-Object System.Data.DataTable
$adapter.Fill($table) | Out-Null
$conn.Close()

Write-Host "  Found $($table.Rows.Count) items in catalog" -ForegroundColor Green

# ── Process items ────────────────────────────────────────────────────────────
$manifest    = @{ ExportDate = (Get-Date -Format 'o'); Source = "$SqlServer.$Database"; Items = @() }
$dsStubs     = @{}   # path -> stub for DataSourceConnections.json

$counts = @{ Folders = 0; Reports = 0; DataSources = 0; Models = 0; Skipped = 0 }

# Reports
Write-Host '[2/4] Extracting reports...' -ForegroundColor Yellow
foreach ($row in $table.Rows) {
    if ($row.Path -in $SKIP_PATHS) { $counts.Skipped++; continue }

    $item = @{
        ItemID       = $row.ItemID
        Path         = $row.Path
        Name         = $row.Name
        Type         = $row.Type
        ParentID     = $row.ParentID
        CreationDate = $row.CreationDate.ToString('o')
        ModifiedDate = $row.ModifiedDate.ToString('o')
        File         = $null
    }

    switch ($row.Type) {
        $TYPE_FOLDER {
            $counts.Folders++
            Write-Host "  [Folder] $($row.Path)" -ForegroundColor Gray
        }

        $TYPE_REPORT {
            if ($row.IsNull('Content')) {
                Write-Warning "  Report has no content, skipping: $($row.Path)"
                $counts.Skipped++
                continue
            }
            try {
                $rdl     = Expand-SSRSBytes -Bytes $row['Content']
                $outFile = ConvertTo-SafePath -SsrsPath $row.Path -Base (Join-Path $OutputFolder 'reports') -Extension '.rdl'
                New-Item -ItemType Directory -Path (Split-Path $outFile) -Force | Out-Null
                [System.IO.File]::WriteAllText($outFile, $rdl, [System.Text.Encoding]::UTF8)
                $item.File = 'reports\' + ($row.Path.TrimStart('/') -replace '[\\/:*?"<>|]', '_') + '.rdl'
                $counts.Reports++
                Write-Host "  [Report] $($row.Path)" -ForegroundColor Green
            } catch {
                Write-Warning "  Could not extract report $($row.Path): $_"
                $counts.Skipped++
            }
        }

        $TYPE_DATASOURCE {
            $stub = @{
                Path      = $row.Path
                Name      = $row.Name
                # Connection string is encrypted in the DB — must be provided manually.
                # Fill in DataSourceConnections.json before running the import.
                Extension        = 'SQL'
                ConnectionString = ''
                CredentialRetrieval = 'None'
                IsEnabled        = $true
            }
            $outFile = ConvertTo-SafePath -SsrsPath $row.Path -Base (Join-Path $OutputFolder 'datasources') -Extension '.json'
            New-Item -ItemType Directory -Path (Split-Path $outFile) -Force | Out-Null
            $stub | ConvertTo-Json | Out-File -FilePath $outFile -Encoding UTF8
            $item.File = 'datasources\' + ($row.Path.TrimStart('/') -replace '[\\/:*?"<>|]', '_') + '.json'
            $dsStubs[$row.Path] = $stub
            $counts.DataSources++
            Write-Host "  [DataSource] $($row.Path)" -ForegroundColor Yellow
        }

        $TYPE_MODEL {
            if ($row.IsNull('Content')) { $counts.Skipped++; continue }
            try {
                $smdl    = Expand-SSRSBytes -Bytes $row['Content']
                $outFile = ConvertTo-SafePath -SsrsPath $row.Path -Base (Join-Path $OutputFolder 'models') -Extension '.smdl'
                New-Item -ItemType Directory -Path (Split-Path $outFile) -Force | Out-Null
                [System.IO.File]::WriteAllText($outFile, $smdl, [System.Text.Encoding]::UTF8)
                $item.File = 'models\' + ($row.Path.TrimStart('/') -replace '[\\/:*?"<>|]', '_') + '.smdl'
                $counts.Models++
                Write-Host "  [Model] $($row.Path)" -ForegroundColor Green
            } catch {
                Write-Warning "  Could not extract model $($row.Path): $_"
                $counts.Skipped++
            }
        }
    }

    $manifest.Items += $item
}

# ── Export users from UserAccountsProduction ─────────────────────────────────
Write-Host '[3/5] Exporting users from UserAccountsProduction...' -ForegroundColor Yellow

try {
    $userQuery = "SELECT UserName, BankNumber, PasswordHash, salt FROM [$UserDatabase].[dbo].[Users] ORDER BY UserName"
    $conn2 = New-Object System.Data.SqlClient.SqlConnection
    $conn2.ConnectionString = "Server=$SqlServer;Integrated Security=SSPI;"
    $conn2.Open()
    $cmd2 = $conn2.CreateCommand()
    $cmd2.CommandText = $userQuery
    $adapter2 = New-Object System.Data.SqlClient.SqlDataAdapter $cmd2
    $userTable = New-Object System.Data.DataTable
    $adapter2.Fill($userTable) | Out-Null
    $conn2.Close()

    $users = @()
    foreach ($row in $userTable.Rows) {
        $users += @{
            UserName     = $row.UserName
            BankNumber   = if ($row.IsNull('BankNumber')) { $null } else { $row.BankNumber }
            PasswordHash = $row.PasswordHash
            Salt         = $row.salt
        }
        Write-Host "  [User] $($row.UserName)" -ForegroundColor Gray
    }

    $users | ConvertTo-Json -Depth 5 | Out-File -FilePath (Join-Path $OutputFolder 'users.json') -Encoding UTF8
    Write-Host "  Exported $($users.Count) users" -ForegroundColor Green
} catch {
    Write-Warning "Could not export users from $UserDatabase : $_"
    Write-Warning "users.json will not be included — users must be registered manually after import."
}

# ── Write manifest ───────────────────────────────────────────────────────────
Write-Host '[4/5] Writing manifest and connection string template...' -ForegroundColor Yellow

$manifest | ConvertTo-Json -Depth 10 | Out-File -FilePath (Join-Path $OutputFolder 'manifest.json') -Encoding UTF8

# DataSourceConnections.json — admin fills in connection strings before import
$connMap = @{}
foreach ($path in $dsStubs.Keys) {
    $connMap[$path] = @{
        Extension           = $dsStubs[$path].Extension    # e.g. SQL, OLEDB, Oracle
        ConnectionString    = 'FILL_IN_CONNECTION_STRING'
        CredentialRetrieval = 'None'   # None | Store | Prompt | Integrated
        UserName            = ''       # only if CredentialRetrieval = Store
        Password            = ''       # only if CredentialRetrieval = Store
        IsEnabled           = $true
    }
}
$connMap | ConvertTo-Json -Depth 5 | Out-File -FilePath (Join-Path $OutputFolder 'DataSourceConnections.json') -Encoding UTF8
Write-Host "  DataSourceConnections.json written — fill in connection strings before importing" -ForegroundColor Yellow

# ── Create ZIP ───────────────────────────────────────────────────────────────
Write-Host '[5/5] Creating ZIP package...' -ForegroundColor Yellow

$zipPath = "$OutputFolder.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($OutputFolder, $zipPath)
Write-Host "  ZIP: $zipPath" -ForegroundColor Green

# ── Summary ──────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '================================================' -ForegroundColor Cyan
Write-Host 'Export complete.' -ForegroundColor Green
Write-Host "  Folders     : $($counts.Folders)"
Write-Host "  Reports     : $($counts.Reports)"
Write-Host "  Data Sources: $($counts.DataSources)"
Write-Host "  Models      : $($counts.Models)"
Write-Host "  Skipped     : $($counts.Skipped)"
Write-Host ''
Write-Host 'Next steps:' -ForegroundColor Cyan
Write-Host "  1. Edit $OutputFolder\DataSourceConnections.json — fill in new connection strings for VMLENOVO"
Write-Host "  2. Review users.json — remove any users that should not be migrated"
Write-Host "  3. Copy $zipPath to VMLENOVO"
Write-Host "  4. Run Import-SSRSContent.ps1 on VMLENOVO"
Write-Host '================================================' -ForegroundColor Cyan
