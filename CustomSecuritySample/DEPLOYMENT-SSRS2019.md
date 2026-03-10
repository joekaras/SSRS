# SSRS 2019 Custom Security Extension — Complete Deployment Guide

Step-by-step record of everything done to get the Microsoft Custom Security Sample operational on SSRS 2019 Native Mode with Forms Authentication.

**Environment**:
- Host: `VMLENOVO` (Windows Server)
- SSRS install: `C:\Program Files\Microsoft SQL Server Reporting Services\SSRS\`
- Service account: `VMLENOVO\ssrssvc`
- Portal URL: `http://vmlenovo/Reports`

---

## Step 1: Create the UserAccounts Database

Run the setup script in SSMS connected to localhost:

```
CustomSecuritySample\Setup\CreateUserStore.sql
```

This creates:
- `UserAccounts` database
- `Users` table (userName, passwordHash, salt)
- `LookupUser` stored procedure (called at login)
- `RegisterUser` stored procedure (called to add users)

---

## Step 2: Grant the SSRS Service Account Access to UserAccounts

The authentication extension connects to SQL using Integrated Security, running as the SSRS service account. That account must exist as a database user.

Run in SSMS (master first, then UserAccounts):

```sql
-- In master: verify the login exists
SELECT name FROM sys.server_principals WHERE name = 'VMLENOVO\ssrssvc';

-- In UserAccounts:
CREATE USER [VMLENOVO\ssrssvc] FOR LOGIN [VMLENOVO\ssrssvc];
GRANT EXECUTE ON dbo.LookupUser   TO [VMLENOVO\ssrssvc];
GRANT EXECUTE ON dbo.RegisterUser TO [VMLENOVO\ssrssvc];
```

> **Note**: Use the actual Windows account shown in Services → SQLServerReportingServices → Log On tab. In SSRS 2019 this is typically a domain account, NOT `NT SERVICE\SQLServerReportingServices`.

---

## Step 3: Build the Extension

Open `CustomSecuritySample.sln` in Visual Studio and build in Release mode.

Output DLL: `BancPac.ReportingServices.BP360.dll`

---

## Step 4: Deploy the Extension DLLs

Copy the compiled DLL (and PDB) to two locations:

```
<install>\ReportServer\bin\BancPac.ReportingServices.BP360.dll
<install>\Portal\BancPac.ReportingServices.BP360.dll
```

---

## Step 5: Copy Logon.aspx

Copy `Logon.aspx` (and `Logon.aspx.cs` if present) to:

```
<install>\ReportServer\Logon.aspx
```

---

## Step 6: Modify rsreportserver.config

File: `<install>\ReportServer\rsreportserver.config`

### 6a. Set Authentication Type to Custom

```xml
<Authentication>
  <AuthenticationTypes>
    <Custom/>
  </AuthenticationTypes>
  <RSWindowsExtendedProtectionLevel>Off</RSWindowsExtendedProtectionLevel>
  <RSWindowsExtendedProtectionScenario>Proxy</RSWindowsExtendedProtectionScenario>
  <EnableAuthPersistence>true</EnableAuthPersistence>
</Authentication>
```

### 6b. Register the Security and Authentication Extensions

Inside the `<Extensions>` element:

```xml
<Security>
  <Extension Name="Forms"
    Type="BancPac.ReportingServices.BP360.Authorization,
          BancPac.ReportingServices.BP360">
    <Configuration>
      <AdminConfiguration>
        <UserName>admin</UserName>
      </AdminConfiguration>
    </Configuration>
  </Extension>
</Security>

<Authentication>
  <Extension Name="Forms"
    Type="BancPac.ReportingServices.BP360.AuthenticationExtension,
          BancPac.ReportingServices.BP360" />
</Authentication>
```

### 6c. Add MachineKey

Under the root `<Configuration>` element (Pascal case, NOT inside `<system.web>`):

```xml
<MachineKey
  ValidationKey="[YOUR VALIDATION KEY]"
  DecryptionKey="[YOUR DECRYPTION KEY]"
  Validation="AES"
  Decryption="AES" />
```

Generate keys using IIS Manager → Server node → Machine Key feature, or:
```powershell
Add-Type -AssemblyName System.Web
[System.Web.Security.MachineKeySection]::GenerateKey(64) # run twice for two keys
```

### 6d. Configure PassThroughCookies

Inside the `<UI>` element:

```xml
<UI>
  <CustomAuthenticationUI>
    <PassThroughCookies>
      <PassThroughCookie>sqlAuthCookie</PassThroughCookie>
    </PassThroughCookies>
  </CustomAuthenticationUI>
</UI>
```

---

## Step 7: Modify web.config

File: `<install>\ReportServer\web.config`

### 7a. Set Authentication Mode to Forms

```xml
<authentication mode="Forms">
  <forms loginUrl="logon.aspx" name="sqlAuthCookie" timeout="60" path="/"></forms>
</authentication>
```

### 7b. Deny Anonymous Users

```xml
<authorization>
  <deny users="?" />
</authorization>
```

### 7c. Disable Impersonation

```xml
<identity impersonate="false" />
```

### 7d. Add MachineKey (must match rsreportserver.config exactly)

Inside `<system.web>` (camelCase attributes):

```xml
<machineKey
  validationKey="[YOUR VALIDATION KEY]"
  decryptionKey="[YOUR DECRYPTION KEY]"
  validation="AES"
  decryption="AES" />
```

---

## Step 8: Modify rssrvpolicy.config

File: `<install>\ReportServer\rssrvpolicy.config`

Add a FullTrust CodeGroup for the custom security DLL. Inside the `MyComputer` `<CodeGroup>`, after the `$CodeGen$` entry:

```xml
<CodeGroup
  class="UnionCodeGroup"
  version="1"
  PermissionSetName="FullTrust"
  Name="SecurityExtensionCodeGroup"
  Description="Code group for the custom security extension">
  <IMembershipCondition
    class="UrlMembershipCondition"
    version="1"
    Url="C:\Program Files\Microsoft SQL Server Reporting Services\SSRS\ReportServer\bin\BancPac.ReportingServices.BP360.dll" />
</CodeGroup>
```

---

## Step 9: Add MachineKey to RSPortal.exe.config (SSRS 2019 — CRITICAL)

File: `<install>\Portal\RSPortal.exe.config`

> **This step is not in the original Microsoft sample but is required for SSRS 2016+.**
>
> RSPortal runs as a separate OWIN process and decrypts the Forms Authentication cookie using `FormsAuthentication.Decrypt`. Without an explicit MachineKey, RSPortal uses an auto-generated key and cannot decrypt the cookie issued by `logon.aspx`, resulting in HTTP 500: *"Unable to validate data."*

Add inside `<configuration>` (after the `<startup>` block):

```xml
<system.web>
  <machineKey
    validationKey="[YOUR VALIDATION KEY]"
    decryptionKey="[YOUR DECRYPTION KEY]"
    validation="AES"
    decryption="AES" />
</system.web>
```

The key values must be **identical** across:
- `rsreportserver.config` (`<MachineKey>` Pascal case under `<Configuration>`)
- `web.config` (`<machineKey>` inside `<system.web>`)
- `RSPortal.exe.config` (`<machineKey>` inside `<system.web>`)

---

## Step 10: Fix File Permissions for the Service Account

RSHostingService rewrites `web.config` and `rssrvpolicy.config` at startup. The service account needs **Modify** permission on both files.

Run in an Administrator PowerShell — replacing `VMLENOVO\ssrssvc` with your actual service account:

```powershell
$account = "VMLENOVO\ssrssvc"
$rsDir = "C:\Program Files\Microsoft SQL Server Reporting Services\SSRS\ReportServer"

foreach ($file in @("web.config", "rssrvpolicy.config")) {
    $path = "$rsDir\$file"
    $acl = Get-Acl $path
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $account, "Modify", "Allow")
    $acl.SetAccessRule($rule)
    Set-Acl $path $acl
    Write-Host "Granted Modify on $file"
}
```

> **Gotcha**: The service account is the Windows account on the Log On tab of the service, not the virtual account name shown in Task Manager. Check: `Services → SQLServerReportingServices → Properties → Log On`.

---

## Step 11: Register Users

Use the included PowerShell script to create user accounts:

```powershell
cd CustomSecuritySample

# Create default test users
.\scripts\Setup-Users.ps1 -CreateTestUsers -Integrated

# Or register a single user
.\scripts\Setup-Users.ps1 -UserName "jdoe" -Password "Pass@123" -Integrated
```

Default test accounts created by `-CreateTestUsers`:

| Username | Password |
|----------|----------|
| testuser | Test@123 |
| admin | Admin@123 |
| report_viewer | Viewer@123 |

The admin username must match the `<UserName>` configured in `rsreportserver.config` Step 6b.

---

## Step 12: Restart SSRS

All configuration changes require a service restart to take effect — especially the RSPortal.exe.config MachineKey change.

Run in Administrator PowerShell:

```powershell
Restart-Service SQLServerReportingServices
```

---

## Step 13: Verify

1. Browse to `http://<server>/Reports` — should redirect to `logon.aspx`
2. Log in with a registered user
3. Should land on the SSRS portal home page

If the portal returns HTTP 500 after login, check:
```
<install>\LogFiles\RSPortal_*.log
```

Common errors and causes:

| Error | Cause |
|-------|-------|
| `Unable to validate data` | MachineKey mismatch — verify all three config files have identical keys, then restart |
| `UnauthorizedAccessException` on web.config | Service account lacks Modify — redo Step 10 |
| `Login failed for user` | Service account not in UserAccounts DB — redo Step 2 |
| Redirect loop on logon.aspx | `<deny users="?" />` missing from web.config |

---

## Logon.aspx Form Field Reference

If writing test scripts or automation, use the correct ASP.NET control IDs:

| Field | Control ID |
|-------|-----------|
| Username | `TxtUser` |
| Password | `TxtPwd` |
| Login button | `BtnLogon` |
| Register button | `BtnRegister` |

Using wrong field names causes EventValidation errors (HTTP 500 on POST).
