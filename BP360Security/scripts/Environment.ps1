# Environment.ps1
# Central server profile configuration for BP360Security deployment.
#
# USAGE — dot-source this file AFTER the param block in any script:
#
#   . (Join-Path $PSScriptRoot 'Environment.ps1')
#   $_prof = Get-ServerProfile
#   if (-not $SsrsRoot)      { $SsrsRoot      = $_prof.SsrsInstallRoot }
#   if (-not $ServiceAccount) { $ServiceAccount = $_prof.ServiceAccount }
#   if (-not $SqlServer)     { $SqlServer      = $_prof.SqlServer }
#
# ADDING A NEW SERVER:
#   Copy an existing block, change the key to the new COMPUTERNAME (uppercase),
#   and update ServiceAccount, DbServiceAccount, SqlServer, and URLs.
#
# NOTE — The logged-in developer account and the service account are different.
#   Scripts run as the developer (using Windows Integrated Auth to reach SQL).
#   ServiceAccount / DbServiceAccount are the accounts that SSRS runs as and
#   that are granted EXECUTE on the UserAccounts stored procedures.
#   Never confuse the two — the developer's own account is NOT granted access
#   to UserAccounts; only the service account is.

Set-StrictMode -Version Latest

# ── Server profiles ────────────────────────────────────────────────────────
# Key   = $env:COMPUTERNAME.ToUpper()
# Value = hashtable of per-server settings
$script:BP360ServerProfiles = @{

    # ------------------------------------------------------------------ #
    # Development server: VMLENOVO                                        #
    # ------------------------------------------------------------------ #
    'VMLENOVO' = @{
        # Windows account that runs the SSRS service (RSHostingService)
        ServiceAccount   = 'VMLENOVO\ssrssvc'
        # Windows account granted EXECUTE on UserAccounts.LookupUser / RegisterUser
        # (same account on this server; update if DB is remote)
        DbServiceAccount = 'VMLENOVO\ssrssvc'
        # SQL Server instance hosting UserAccounts DB
        SqlServer        = 'localhost'
        # SSRS install root — scripts append \SSRS\ReportServer etc. internally
        SsrsInstallRoot  = 'C:\Program Files\Microsoft SQL Server Reporting Services'
        # Public-facing URLs
        PortalUrl        = 'http://vmlenovo/Reports'
        ReportServerUrl  = 'http://vmlenovo/ReportServer'
        LogonUrl         = 'http://vmlenovo/ReportServer/logon.aspx'
    }

    # ------------------------------------------------------------------ #
    # Test/staging server: VWMAZBPTESTBP360                              #
    # ------------------------------------------------------------------ #
    'VWMAZBPTESTBP360' = @{
        ServiceAccount   = 'vwmazbptestbp360\bp360svcc'
        # Update DbServiceAccount below if the DB account differs from the SSRS account
        DbServiceAccount = 'vwmazbptestbp360\bp360svcc'
        SqlServer        = 'localhost'
        SsrsInstallRoot  = 'C:\Program Files\Microsoft SQL Server Reporting Services'
        PortalUrl        = 'http://vwmazbptestbp360/Reports'
        ReportServerUrl  = 'http://vwmazbptestbp360/ReportServer'
        LogonUrl         = 'http://vwmazbptestbp360/ReportServer/logon.aspx'
    }
}

function Get-ServerProfile {
    <#
    .SYNOPSIS
        Returns the BP360 server profile for the machine this script runs on.
    .DESCRIPTION
        Looks up $env:COMPUTERNAME in the server profile table.
        If no entry is found, returns safe localhost defaults and warns the
        operator to add an entry to Environment.ps1.
    .OUTPUTS
        Hashtable with keys: ServiceAccount, DbServiceAccount, SqlServer,
        SsrsInstallRoot, PortalUrl, ReportServerUrl, LogonUrl.
    #>
    $machine = $env:COMPUTERNAME.ToUpper()

    if ($script:BP360ServerProfiles.ContainsKey($machine)) {
        $prof = $script:BP360ServerProfiles[$machine]
        Write-Host "  [Env] $machine | SSRS svc: $($prof.ServiceAccount) | SQL: $($prof.SqlServer)" -ForegroundColor DarkGray
        return $prof
    }

    Write-Warning "No BP360 profile for server '$machine'. Using localhost defaults."
    Write-Warning "Add an entry for '$machine' in scripts\Environment.ps1."
    return @{
        ServiceAccount   = ''
        DbServiceAccount = ''
        SqlServer        = 'localhost'
        SsrsInstallRoot  = 'C:\Program Files\Microsoft SQL Server Reporting Services'
        PortalUrl        = "http://$($env:COMPUTERNAME)/Reports"
        ReportServerUrl  = "http://$($env:COMPUTERNAME)/ReportServer"
        LogonUrl         = "http://$($env:COMPUTERNAME)/ReportServer/logon.aspx"
    }
}
