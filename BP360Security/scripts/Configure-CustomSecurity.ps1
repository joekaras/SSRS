# Configure-CustomSecurity.ps1
# Applies all SSRS configuration changes required for Forms Authentication
# on SSRS 2019 Native Mode (no IIS required).
#
# Edits:
#   rsreportserver.config  — AuthenticationTypes, Extensions, MachineKey, PassThroughCookies
#   ReportServer\web.config — Forms auth, machineKey, identity
#   rssrvpolicy.config     — FullTrust CodeGroup for custom DLL
#   Portal\RSPortal.exe.config — machineKey (critical for SSRS 2016+)
#   ReportServer\bin\BancPac.ReportingServices.BP360.dll.config — UILogon shared keys
#
# Optionally grants service account file permissions and starts SSRS.

param(
    [string]$SsrsRoot       = '',   # auto-detected from Environment.ps1
    [string]$SqlServer      = '',   # auto-detected from Environment.ps1
    [string]$ServiceAccount = '',   # SSRS service account — auto-detected from Environment.ps1
    [string]$ValidationKey  = '',   # leave blank to auto-generate
    [string]$DecryptionKey  = '',   # leave blank to auto-generate
    [string]$AdminUser      = 'admin',  # username given Content Manager role in SSRS
    [switch]$StartService
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Auto-detect server environment ────────────────────────────────────────
. (Join-Path $PSScriptRoot 'Environment.ps1')
$_prof = Get-ServerProfile
if (-not $SsrsRoot)       { $SsrsRoot       = $_prof.SsrsInstallRoot }
if (-not $SqlServer)      { $SqlServer       = $_prof.SqlServer }
if (-not $ServiceAccount) { $ServiceAccount  = $_prof.ServiceAccount }

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error 'This script must be run as Administrator.'
    exit 1
}

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
$rsDir          = Join-Path $SsrsRoot 'SSRS\ReportServer'
$rsConfig       = Join-Path $rsDir 'rsreportserver.config'
$rsWebConfig    = Join-Path $rsDir 'web.config'
$rsPolicyConfig = Join-Path $rsDir 'rssrvpolicy.config'
$portalConfig   = Join-Path $SsrsRoot 'SSRS\Portal\RSPortal.exe.config'
$customDllPath  = Join-Path $rsDir "bin\BancPac.ReportingServices.BP360.dll"
$dllAssembly    = 'BancPac.ReportingServices.BP360'
$secType        = "BancPac.ReportingServices.BP360.Authorization, $dllAssembly"
$authType       = "BancPac.ReportingServices.BP360.AuthenticationExtension, $dllAssembly"

foreach ($f in @($rsConfig, $rsWebConfig, $rsPolicyConfig)) {
    if (-not (Test-Path $f)) {
        Write-Error "Required file not found: $f"
        exit 1
    }
}

Write-Host '================================================' -ForegroundColor Cyan
Write-Host 'SSRS Custom Security Configuration' -ForegroundColor Cyan
Write-Host '================================================' -ForegroundColor Cyan
Write-Host ''

# ---------------------------------------------------------------------------
# Helper: save XML preserving declaration
# ---------------------------------------------------------------------------
function Save-Xml {
    param([xml]$Doc, [string]$Path)
    $settings = [System.Xml.XmlWriterSettings]::new()
    $settings.Indent             = $true
    $settings.IndentChars        = '  '
    $settings.Encoding           = [System.Text.Encoding]::UTF8
    $settings.OmitXmlDeclaration = $false
    $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
    try   { $Doc.Save($writer) }
    finally { $writer.Dispose() }
}

# ---------------------------------------------------------------------------
# Helper: generate random hex string
# ---------------------------------------------------------------------------
function New-HexString {
    param([int]$ByteLength)
    $bytes = New-Object byte[] $ByteLength
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try   { $rng.GetBytes($bytes) }
    finally { $rng.Dispose() }
    ($bytes | ForEach-Object { $_.ToString('X2') }) -join ''
}

# ---------------------------------------------------------------------------
# Step 1: Machine keys
# ---------------------------------------------------------------------------
Write-Host '[1/7] Machine keys' -ForegroundColor Yellow

if ([string]::IsNullOrWhiteSpace($ValidationKey)) {
    $ValidationKey = New-HexString -ByteLength 64   # 128 hex chars
}
if ([string]::IsNullOrWhiteSpace($DecryptionKey)) {
    $DecryptionKey = New-HexString -ByteLength 32   # 64 hex chars
}

Write-Host "  ValidationKey: $($ValidationKey.Substring(0,16))..." -ForegroundColor Gray
Write-Host "  DecryptionKey: $($DecryptionKey.Substring(0,16))..." -ForegroundColor Gray

# Save keys to repo backups folder for reference
$keyFile = Join-Path $PSScriptRoot "..\backups\MachineKey_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').txt"
New-Item -ItemType Directory -Path (Split-Path $keyFile) -Force | Out-Null
@"
Generated: $(Get-Date)

<!-- rsreportserver.config (under <Configuration>, Pascal case) -->
<MachineKey ValidationKey="$ValidationKey" DecryptionKey="$DecryptionKey" Validation="AES" Decryption="AES" />

<!-- web.config and RSPortal.exe.config (inside <system.web>, camelCase) -->
<machineKey validationKey="$ValidationKey" decryptionKey="$DecryptionKey" validation="AES" decryption="AES" />
"@ | Out-File -FilePath $keyFile -Encoding UTF8
Write-Host "  Keys saved to: $keyFile" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Step 2: rsreportserver.config
# ---------------------------------------------------------------------------
Write-Host '[2/7] Patching rsreportserver.config' -ForegroundColor Yellow

[xml]$rsCfg = Get-Content $rsConfig -Raw

# 2a. Authentication -> Custom
$authNode = $rsCfg.SelectSingleNode('//Configuration/Authentication')
if ($null -eq $authNode) { Write-Error '<Authentication> not found in rsreportserver.config'; exit 1 }
$authTypesNode = $authNode.SelectSingleNode('AuthenticationTypes')
if ($null -eq $authTypesNode) {
    $authTypesNode = $rsCfg.CreateElement('AuthenticationTypes')
    $authNode.PrependChild($authTypesNode) | Out-Null
}
$authTypesNode.RemoveAll()
$authTypesNode.AppendChild($rsCfg.CreateElement('Custom')) | Out-Null
Write-Host '  AuthenticationTypes -> Custom' -ForegroundColor Green

# 2b. Security extension -> Forms/Authorization
$extNode = $rsCfg.SelectSingleNode('//Extensions')
if ($null -eq $extNode) { Write-Error '<Extensions> not found in rsreportserver.config'; exit 1 }

$secParent = $extNode.SelectSingleNode('Security')
if ($null -eq $secParent) {
    $secParent = $rsCfg.CreateElement('Security')
    $extNode.AppendChild($secParent) | Out-Null
}
$secParent.RemoveAll()
$secExt = $rsCfg.CreateElement('Extension')
$secExt.SetAttribute('Name', 'Forms')
$secExt.SetAttribute('Type', $secType)
$configEl  = $rsCfg.CreateElement('Configuration')
$adminEl   = $rsCfg.CreateElement('AdminConfiguration')
$userEl    = $rsCfg.CreateElement('UserName')
$userEl.InnerText = $AdminUser
$adminEl.AppendChild($userEl)  | Out-Null
$configEl.AppendChild($adminEl) | Out-Null
$secExt.AppendChild($configEl)  | Out-Null
$secParent.AppendChild($secExt) | Out-Null
Write-Host "  Security extension -> Forms ($secType)" -ForegroundColor Green

# 2c. Authentication extension -> Forms/AuthenticationExtension
$authParent = $extNode.SelectSingleNode('Authentication')
if ($null -eq $authParent) {
    $authParent = $rsCfg.CreateElement('Authentication')
    $extNode.AppendChild($authParent) | Out-Null
}
$authParent.RemoveAll()
$authExt = $rsCfg.CreateElement('Extension')
$authExt.SetAttribute('Name', 'Forms')
$authExt.SetAttribute('Type', $authType)
$authParent.AppendChild($authExt) | Out-Null
Write-Host "  Authentication extension -> Forms ($authType)" -ForegroundColor Green

# 2d. MachineKey (Pascal case, under <Configuration> root)
$existingMk = $rsCfg.SelectSingleNode('//Configuration/MachineKey')
if ($existingMk) { $existingMk.ParentNode.RemoveChild($existingMk) | Out-Null }
$mkEl = $rsCfg.CreateElement('MachineKey')
$mkEl.SetAttribute('ValidationKey', $ValidationKey)
$mkEl.SetAttribute('DecryptionKey', $DecryptionKey)
$mkEl.SetAttribute('Validation', 'AES')
$mkEl.SetAttribute('Decryption', 'AES')
$rsCfg.SelectSingleNode('//Configuration').AppendChild($mkEl) | Out-Null
Write-Host '  MachineKey added to rsreportserver.config' -ForegroundColor Green

# 2e. PassThroughCookies under <UI><CustomAuthenticationUI>
$uiNode = $rsCfg.SelectSingleNode('//Configuration/UI')
if ($null -eq $uiNode) {
    $uiNode = $rsCfg.CreateElement('UI')
    $rsCfg.SelectSingleNode('//Configuration').AppendChild($uiNode) | Out-Null
}
$cauiEl = $uiNode.SelectSingleNode('CustomAuthenticationUI')
if ($null -eq $cauiEl) {
    $cauiEl = $rsCfg.CreateElement('CustomAuthenticationUI')
    $uiNode.AppendChild($cauiEl) | Out-Null
}
# Remove existing PassThroughCookies if present (idempotent)
$existingPtc = $cauiEl.SelectSingleNode('PassThroughCookies')
if ($existingPtc) { $cauiEl.RemoveChild($existingPtc) | Out-Null }
$ptcEl    = $rsCfg.CreateElement('PassThroughCookies')
$cookieEl = $rsCfg.CreateElement('PassThroughCookie')
$cookieEl.InnerText = 'sqlAuthCookie'
$ptcEl.AppendChild($cookieEl) | Out-Null
$cauiEl.AppendChild($ptcEl)   | Out-Null
Write-Host '  PassThroughCookies -> sqlAuthCookie' -ForegroundColor Green

Save-Xml -Doc $rsCfg -Path $rsConfig
Write-Host "  Saved: $rsConfig" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Step 3: ReportServer web.config
# ---------------------------------------------------------------------------
Write-Host '[3/7] Patching ReportServer web.config' -ForegroundColor Yellow

[xml]$rwc = Get-Content $rsWebConfig -Raw
$sw = $rwc.SelectSingleNode('//configuration/system.web')
if ($null -eq $sw) { Write-Error '<system.web> not found in web.config'; exit 1 }

# 3a. Authentication mode -> Forms, cookie name -> sqlAuthCookie
$authEl = $sw.SelectSingleNode('authentication')
if ($null -eq $authEl) {
    $authEl = $rwc.CreateElement('authentication')
    $sw.AppendChild($authEl) | Out-Null
}
$authEl.SetAttribute('mode', 'Forms')
$existingForms = $authEl.SelectSingleNode('forms')
if ($existingForms) { $authEl.RemoveChild($existingForms) | Out-Null }
$formsEl = $rwc.CreateElement('forms')
$formsEl.SetAttribute('loginUrl', 'logon.aspx')
$formsEl.SetAttribute('name',     'sqlAuthCookie')
$formsEl.SetAttribute('timeout',  '60')
$formsEl.SetAttribute('path',     '/')
$authEl.AppendChild($formsEl) | Out-Null
Write-Host '  authentication mode -> Forms (cookie: sqlAuthCookie)' -ForegroundColor Green

# 3b. Authorization -> deny anonymous
$authzEl = $sw.SelectSingleNode('authorization')
if ($null -eq $authzEl) {
    $authzEl = $rwc.CreateElement('authorization')
    $sw.AppendChild($authzEl) | Out-Null
}
if ($null -eq $authzEl.SelectSingleNode("deny[@users='?']")) {
    $denyEl = $rwc.CreateElement('deny')
    $denyEl.SetAttribute('users', '?')
    $authzEl.AppendChild($denyEl) | Out-Null
}
Write-Host '  authorization -> deny anonymous users' -ForegroundColor Green

# 3b2. Allow unauthenticated access to UILogon.aspx (server-to-server login endpoint)
#      Without this <location> block, Forms Auth would redirect UILogon.aspx requests
#      to logon.aspx before the extension can process them.
$uiLogonLocation = $rwc.SelectSingleNode("configuration/location[@path='UILogon.aspx']")
if ($null -eq $uiLogonLocation) {
    $locEl   = $rwc.CreateElement('location')
    $locEl.SetAttribute('path', 'UILogon.aspx')
    $swLocEl = $rwc.CreateElement('system.web')
    $azLocEl = $rwc.CreateElement('authorization')
    $allowEl = $rwc.CreateElement('allow')
    $allowEl.SetAttribute('users', '*')
    $azLocEl.AppendChild($allowEl) | Out-Null
    $swLocEl.AppendChild($azLocEl) | Out-Null
    $locEl.AppendChild($swLocEl)   | Out-Null
    $rwc.DocumentElement.AppendChild($locEl) | Out-Null
    Write-Host '  location UILogon.aspx -> allow all users (Forms Auth exemption)' -ForegroundColor Green
} else {
    Write-Host '  location UILogon.aspx already present' -ForegroundColor Gray
}

# 3c. Identity impersonate -> false
$identEl = $sw.SelectSingleNode('identity')
if ($null -eq $identEl) {
    $identEl = $rwc.CreateElement('identity')
    $sw.AppendChild($identEl) | Out-Null
}
$identEl.SetAttribute('impersonate', 'false')
Write-Host '  identity impersonate -> false' -ForegroundColor Green

# 3d. machineKey (camelCase attributes)
$existingMkW = $sw.SelectSingleNode('machineKey')
if ($existingMkW) { $sw.RemoveChild($existingMkW) | Out-Null }
$mkwEl = $rwc.CreateElement('machineKey')
$mkwEl.SetAttribute('validationKey', $ValidationKey)
$mkwEl.SetAttribute('decryptionKey', $DecryptionKey)
$mkwEl.SetAttribute('validation',    'AES')
$mkwEl.SetAttribute('decryption',    'AES')
$sw.AppendChild($mkwEl) | Out-Null
Write-Host '  machineKey added to web.config' -ForegroundColor Green

Save-Xml -Doc $rwc -Path $rsWebConfig
Write-Host "  Saved: $rsWebConfig" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Step 4: rssrvpolicy.config — FullTrust CodeGroup for the DLL
# ---------------------------------------------------------------------------
Write-Host '[4/7] Patching rssrvpolicy.config' -ForegroundColor Yellow

[xml]$rsp = Get-Content $rsPolicyConfig -Raw

# Find the MyComputer FirstMatchCodeGroup (inner one with ZoneMembershipCondition)
$targetGroup = $rsp.SelectNodes("//CodeGroup[@class='FirstMatchCodeGroup']") |
    Where-Object { $_.SelectSingleNode("IMembershipCondition[@Zone='MyComputer']") } |
    Select-Object -First 1

if ($null -eq $targetGroup) {
    Write-Warning 'Could not locate MyComputer CodeGroup in rssrvpolicy.config — skipping'
} else {
    $existing = $targetGroup.SelectSingleNode("CodeGroup[@Name='SecurityExtensionCodeGroup']")
    if ($existing) {
        # Update URL in case path changed
        $existing.SelectSingleNode('IMembershipCondition').SetAttribute('Url', $customDllPath)
        Write-Host '  SecurityExtensionCodeGroup already present — URL updated' -ForegroundColor Gray
    } else {
        $cgEl = $rsp.CreateElement('CodeGroup')
        $cgEl.SetAttribute('class',             'UnionCodeGroup')
        $cgEl.SetAttribute('version',           '1')
        $cgEl.SetAttribute('PermissionSetName', 'FullTrust')
        $cgEl.SetAttribute('Name',              'SecurityExtensionCodeGroup')
        $cgEl.SetAttribute('Description',       'Code group for the custom security extension')
        $imcEl = $rsp.CreateElement('IMembershipCondition')
        $imcEl.SetAttribute('class',   'UrlMembershipCondition')
        $imcEl.SetAttribute('version', '1')
        $imcEl.SetAttribute('Url',     $customDllPath)
        $cgEl.AppendChild($imcEl) | Out-Null
        $targetGroup.AppendChild($cgEl) | Out-Null
        Write-Host '  SecurityExtensionCodeGroup (FullTrust) added' -ForegroundColor Green
    }
    Save-Xml -Doc $rsp -Path $rsPolicyConfig
    Write-Host "  Saved: $rsPolicyConfig" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Step 5: RSPortal.exe.config — machineKey (SSRS 2016+ CRITICAL)
# ---------------------------------------------------------------------------
Write-Host '[5/7] Patching RSPortal.exe.config' -ForegroundColor Yellow

if (-not (Test-Path $portalConfig)) {
    Write-Warning "Portal config not found: $portalConfig"
} else {
    [xml]$pcfg = Get-Content $portalConfig -Raw
    $pcRoot = $pcfg.SelectSingleNode('//configuration')
    $psw    = $pcfg.SelectSingleNode('//configuration/system.web')
    if ($null -eq $psw) {
        $psw = $pcfg.CreateElement('system.web')
        $pcRoot.AppendChild($psw) | Out-Null
    }
    $existingPmk = $psw.SelectSingleNode('machineKey')
    if ($existingPmk) { $psw.RemoveChild($existingPmk) | Out-Null }
    $pmkEl = $pcfg.CreateElement('machineKey')
    $pmkEl.SetAttribute('validationKey', $ValidationKey)
    $pmkEl.SetAttribute('decryptionKey', $DecryptionKey)
    $pmkEl.SetAttribute('validation',    'AES')
    $pmkEl.SetAttribute('decryption',    'AES')
    $psw.AppendChild($pmkEl) | Out-Null
    Save-Xml -Doc $pcfg -Path $portalConfig
    Write-Host '  machineKey added to RSPortal.exe.config' -ForegroundColor Green
    Write-Host "  Saved: $portalConfig" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Step 6: DLL config — UILogon shared keys
# Existing keys are NOT overwritten so deployed WPF clients keep working.
# New keys are generated only if the entry is missing.
# ---------------------------------------------------------------------------
Write-Host '[6/7] Patching DLL config with UILogon keys' -ForegroundColor Yellow

$dllConfigPath = Join-Path $rsDir "bin\BancPac.ReportingServices.BP360.dll.config"
if (-not (Test-Path $dllConfigPath)) {
    Write-Warning "DLL config not found: $dllConfigPath — skipping UILogon key setup"
} else {
    [xml]$dllCfg = Get-Content $dllConfigPath -Raw -Encoding UTF8

    $cfgRoot = $dllCfg.SelectSingleNode('//configuration')
    if ($null -eq $cfgRoot) { Write-Error '<configuration> not found in dll.config'; exit 1 }

    $appSettings = $dllCfg.SelectSingleNode('//configuration/appSettings')
    if ($null -eq $appSettings) {
        $appSettings = $dllCfg.CreateElement('appSettings')
        $cfgRoot.AppendChild($appSettings) | Out-Null
    }

    $newKeys = @{}
    foreach ($keyName in @('UILogon.Key1', 'UILogon.Key2')) {
        $existing = $appSettings.SelectSingleNode("add[@key='$keyName']")
        if ($existing) {
            Write-Host "  $keyName already configured (not overwritten)" -ForegroundColor Gray
            $newKeys[$keyName] = $existing.GetAttribute('value')
        } else {
            $keyVal = New-HexString -ByteLength 32   # 64-char hex key
            $addEl = $dllCfg.CreateElement('add')
            $addEl.SetAttribute('key',   $keyName)
            $addEl.SetAttribute('value', $keyVal)
            $appSettings.AppendChild($addEl) | Out-Null
            $newKeys[$keyName] = $keyVal
            Write-Host "  $keyName generated" -ForegroundColor Green
        }
    }

    Save-Xml -Doc $dllCfg -Path $dllConfigPath
    Write-Host "  Saved: $dllConfigPath" -ForegroundColor Green

    # Append UILogon keys to the key file so the admin can configure WPF clients
    if (Test-Path $keyFile) {
        @"

UILogon keys (use one of these as UILogon.Key in WPF App.config):
  UILogon.Key1 = $($newKeys['UILogon.Key1'])
  UILogon.Key2 = $($newKeys['UILogon.Key2'])
"@ | Add-Content -Path $keyFile -Encoding UTF8
    }
    Write-Host "  Keys appended to: $keyFile" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Step 7: Service account file permissions
# ---------------------------------------------------------------------------
Write-Host '[7/7] Setting file permissions for service account' -ForegroundColor Yellow

if ([string]::IsNullOrWhiteSpace($ServiceAccount)) {
    Write-Warning 'No service account specified — skipping file permissions'
} else {
    foreach ($filePath in @($rsWebConfig, $rsPolicyConfig)) {
        try {
            $acl  = Get-Acl $filePath
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $ServiceAccount, 'Modify', 'Allow')
            $acl.SetAccessRule($rule)
            Set-Acl $filePath $acl
            Write-Host "  Modify granted to $ServiceAccount on $(Split-Path $filePath -Leaf)" -ForegroundColor Green
        } catch {
            Write-Warning "Could not set permissions on $filePath : $_"
        }
    }
}

# ---------------------------------------------------------------------------
# Optionally start SSRS
# ---------------------------------------------------------------------------
if ($StartService) {
    Write-Host 'Starting SSRS service...' -ForegroundColor Yellow
    $svc = Get-Service -Name 'SQLServerReportingServices' -ErrorAction SilentlyContinue
    if ($svc) {
        Start-Service -Name 'SQLServerReportingServices'
        Write-Host 'SSRS service started.' -ForegroundColor Green
    } else {
        Write-Warning 'SSRS service not found — start manually.'
    }
}

Write-Host ''
Write-Host '================================================' -ForegroundColor Cyan
Write-Host 'Configuration complete.' -ForegroundColor Cyan
Write-Host "  Keys saved : $keyFile" -ForegroundColor White
Write-Host "  Portal URL : $($_prof.PortalUrl)" -ForegroundColor White
if (-not $StartService) {
    Write-Host '  Start SSRS : Restart-Service SQLServerReportingServices' -ForegroundColor Yellow
}
Write-Host '================================================' -ForegroundColor Cyan
