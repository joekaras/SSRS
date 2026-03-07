# Restore-SSRSWindowsAuth.ps1
# Patches rsreportserver.config and web.config back to default Windows auth
# after a rollback where the backup already contained Custom Security settings.

param(
    [string]$SSRSPath = 'C:\Program Files\Microsoft SQL Server Reporting Services',
    [switch]$SkipServiceManagement   # Set when SSRS is already stopped by the caller (Deploy/Rollback)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error 'Must be run as Administrator.'; exit 1
}

function Save-Xml {
    param([xml]$Doc, [string]$Path)
    $s = [System.Xml.XmlWriterSettings]::new()
    $s.Indent = $true; $s.IndentChars = '  '
    $s.Encoding = [System.Text.Encoding]::UTF8
    $s.OmitXmlDeclaration = $false
    $w = [System.Xml.XmlWriter]::Create($Path, $s)
    try { $Doc.Save($w) } finally { $w.Dispose() }
}

$rsConfigCopy  = Join-Path $SSRSPath 'SSRS\ReportServer\rsreportserver - Copy.config'
$webConfigCopy = Join-Path $SSRSPath 'SSRS\ReportServer\web - Copy.config'
$rsConfig      = Join-Path $SSRSPath 'SSRS\ReportServer\rsreportserver.config'
$webConfig     = Join-Path $SSRSPath 'SSRS\ReportServer\web.config'
$policyConfigCopy = Join-Path $SSRSPath 'SSRS\ReportServer\rssrvpolicy - Copy.config'
$policyConfig     = Join-Path $SSRSPath 'SSRS\ReportServer\rssrvpolicy.config'

Write-Host '================================================' -ForegroundColor Cyan
Write-Host 'Restoring SSRS Windows Authentication' -ForegroundColor Cyan
Write-Host '================================================' -ForegroundColor Cyan

# ── Stop SSRS ────────────────────────────────────────────────────────────────
if ($SkipServiceManagement) {
    Write-Host '[1/4] Stopping SSRS (skipped - managed by caller)' -ForegroundColor Gray
} else {
    Write-Host '[1/4] Stopping SSRS' -ForegroundColor Yellow
    $svc = Get-Service SQLServerReportingServices -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') {
        Stop-Service SQLServerReportingServices -Force
        Write-Host '  Stopped' -ForegroundColor Green
    }
}

# ── Fix rsreportserver.config and web.config ──────────────────────────────────
# Primary: copy the definitive '- Copy.config' files created after initial install.
# Fallback: XML patching if the copy files are not present.

$useCopyFiles = (Test-Path $rsConfigCopy) -and (Test-Path $webConfigCopy)

if ($useCopyFiles) {
    Write-Host '[2/4] Restoring configs from definitive copy files' -ForegroundColor Yellow
    Copy-Item $rsConfigCopy  -Destination $rsConfig   -Force
    Write-Host '  Restored: rsreportserver.config' -ForegroundColor Green
    Copy-Item $webConfigCopy -Destination $webConfig  -Force
    Write-Host '  Restored: web.config' -ForegroundColor Green
    if (Test-Path $policyConfigCopy) {
        Copy-Item $policyConfigCopy -Destination $policyConfig -Force
        Write-Host '  Restored: rssrvpolicy.config' -ForegroundColor Green
    }
    Write-Host '[3/4] (skipped - copy files used, no XML patching needed)' -ForegroundColor Gray
} else {
    Write-Warning 'Definitive copy files not found - falling back to XML patching'

    # ── Fix rsreportserver.config ──────────────────────────────────────────────
    Write-Host '[2/4] Patching rsreportserver.config' -ForegroundColor Yellow
    [xml]$rs = [System.IO.File]::ReadAllText($rsConfig)

    # 1. AuthenticationTypes -> RSWindowsNegotiate
    $authTypes = $rs.SelectSingleNode('//Authentication/AuthenticationTypes')
    if ($authTypes) {
        $authTypes.InnerXml = '<RSWindowsNegotiate />'
        Write-Host '  AuthenticationTypes -> RSWindowsNegotiate' -ForegroundColor Gray
    }

    # 2. Remove CustomAuthenticationUI element
    $ui = $rs.SelectSingleNode('//Authentication/CustomAuthenticationUI')
    if ($ui) {
        $ui.ParentNode.RemoveChild($ui) | Out-Null
        Write-Host '  Removed CustomAuthenticationUI' -ForegroundColor Gray
    }

    # 3. Security extensions -> Windows only
    $secNode = $rs.SelectSingleNode('//Extensions/Security')
    if ($secNode) {
        $secNode.RemoveAll()
        $ext = $rs.CreateElement('Extension')
        $ext.SetAttribute('Name', 'Windows')
        $ext.SetAttribute('Type', 'Microsoft.ReportingServices.Authorization.WindowsAuthorization, Microsoft.ReportingServices.Authorization')
        $secNode.AppendChild($ext) | Out-Null
        Write-Host '  Security extension -> Windows' -ForegroundColor Gray
    }

    # 4. Authentication extensions -> Windows only
    $authExt = $rs.SelectSingleNode('//Extensions/Authentication')
    if ($authExt) {
        $authExt.RemoveAll()
        $ext = $rs.CreateElement('Extension')
        $ext.SetAttribute('Name', 'Windows')
        $ext.SetAttribute('Type', 'Microsoft.ReportingServices.Authentication.WindowsAuthentication, Microsoft.ReportingServices.Authorization')
        $authExt.AppendChild($ext) | Out-Null
        Write-Host '  Authentication extension -> Windows' -ForegroundColor Gray
    }

    Save-Xml -Doc $rs -Path $rsConfig
    Write-Host "  Saved: $rsConfig" -ForegroundColor Green

    # ── Fix ReportServer web.config ────────────────────────────────────────────
    Write-Host '[3/4] Patching ReportServer web.config' -ForegroundColor Yellow
    [xml]$wc = [System.IO.File]::ReadAllText($webConfig)

    # 1. authentication mode -> Windows, remove Forms child
    $authNode = $wc.SelectSingleNode('//system.web/authentication')
    if ($authNode) {
        $authNode.SetAttribute('mode', 'Windows')
        $formsNode = $authNode.SelectSingleNode('forms')
        if ($formsNode) { $authNode.RemoveChild($formsNode) | Out-Null }
        Write-Host '  authentication mode -> Windows' -ForegroundColor Gray
    }

    # 2. identity impersonate -> true
    $idNode = $wc.SelectSingleNode('//system.web/identity')
    if ($idNode) {
        $idNode.SetAttribute('impersonate', 'true')
        Write-Host '  identity impersonate -> true' -ForegroundColor Gray
    }

    # 3. Remove CustomSecurity assembly reference
    $assemblies = $wc.SelectSingleNode('//system.web/compilation/assemblies')
    if ($assemblies) {
        $toRemove = $assemblies.SelectNodes('add') | Where-Object {
            $_.GetAttribute('assembly') -match 'CustomSecurity'
        }
        foreach ($node in $toRemove) {
            $assemblies.RemoveChild($node) | Out-Null
            Write-Host '  Removed CustomSecurity assembly reference' -ForegroundColor Gray
        }
    }

    # 4. Remove machineKey element
    $mk = $wc.SelectSingleNode('//system.web/machineKey')
    if ($mk) {
        $mk.ParentNode.RemoveChild($mk) | Out-Null
        Write-Host '  Removed machineKey' -ForegroundColor Gray
    }

    Save-Xml -Doc $wc -Path $webConfig
    Write-Host "  Saved: $webConfig" -ForegroundColor Green
}

# ── Start SSRS ────────────────────────────────────────────────────────────────
if ($SkipServiceManagement) {
    Write-Host '[4/4] Starting SSRS (skipped - managed by caller)' -ForegroundColor Gray
} else {
    Write-Host '[4/4] Starting SSRS' -ForegroundColor Yellow
    Start-Service SQLServerReportingServices
    Write-Host '  Started' -ForegroundColor Green
}

Write-Host ''
Write-Host '================================================' -ForegroundColor Cyan
Write-Host 'Done. SSRS is back to Windows Authentication.' -ForegroundColor Cyan
Write-Host "Test: http://vwmazbp360test/ReportServer" -ForegroundColor White
Write-Host '================================================' -ForegroundColor Cyan
