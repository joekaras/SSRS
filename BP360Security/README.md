# BP360Security — SSRS 2019 Custom Security Extension

.NET Framework 4.8 class library that implements Forms Authentication for SSRS 2019 Native Mode. Deployed on two independent servers; scripts auto-detect the server via `$env:COMPUTERNAME`.

---

## Project structure

```
BP360Security/
├── AuthenticationExtension.cs   IAuthenticationExtension2 — validates credentials
├── Authorization.cs             IAuthorizationExtension — admin via rsreportserver.config
├── AuthenticationUtilities.cs   SHA1+salt hashing; LookupUser/RegisterUser stored procs; VerifyUser
├── Logon.aspx / .cs             Browser-facing login page (ReportServer virtual dir)
├── UILogon.aspx / .cs           Server-to-server login endpoint for WPF client
├── Logging/
│   ├── EventLogWriter.cs        Windows Event Log wrapper
│   └── SecurityLog.cs           Lazy singleton logger
├── Setup/
│   └── CreateUserStore.sql      Creates UserAccounts DB, Users table, stored procs
├── scripts/
│   ├── Deploy-CustomSecurity.ps1      Full deploy (build → DB → backup → copy → configure → restart)
│   ├── Build-CustomSecurity.ps1       Build DLL only
│   ├── Configure-CustomSecurity.ps1   Patch config files, set permissions, start service
│   ├── Backup-Config.ps1              Snapshot all config files before changes
│   ├── Setup-Users.ps1                Register users in UserAccounts DB
│   ├── Environment.ps1                Server auto-detection (VMLENOVO vs VWMAZBPTESTBP360)
│   ├── Generate-MachineKeys.ps1       Generate new MachineKey values
│   ├── Rollback-CustomSecurity.ps1    Restore config from backup
│   ├── SmokeTest-Logon.ps1            Quick browser test of logon.aspx
│   ├── Test-FormsAuth.ps1             Full Forms Auth flow test
│   ├── Test-Login.ps1                 Credential verification test
│   └── Test-SSRSEndpoints.ps1         ReportServer / Portal endpoint check
└── 2012Extension/               Legacy VB.NET files from SSRS 2012 (reference only)
```

---

## Deploy

Run as Administrator on the target server:

```powershell
.\scripts\Deploy-CustomSecurity.ps1
```

Auto-detects server, builds DLL, creates/updates UserAccounts DB, backs up configs, patches all three config files (rsreportserver.config, web.config, RSPortal.exe.config), sets file permissions, restarts SSRS, and optionally registers test users.

For manual step-by-step instructions see `DEPLOYMENT-SSRS2019.md`.

---

## Servers

| Setting | VMLENOVO | VWMAZBPTESTBP360 |
|---------|----------|-----------------|
| Service account | `VMLENOVO\ssrssvc` | `vwmazbptestbp360\bp360svcc` |
| Portal URL | `http://vmlenovo/Reports` | `http://vwmazbptestbp360/Reports` |
| ReportServer URL | `http://vmlenovo/ReportServer` | `http://vwmazbptestbp360/ReportServer` |
| SSRS install | `C:\Program Files\Microsoft SQL Server Reporting Services\SSRS\` | same |

---

## Auth flow

```
Browser → logon.aspx → FormsAuthentication cookie (sqlAuthCookie)
                                  ↓
                      RSPortal decrypts cookie via FormsAuthentication.Decrypt
                                  ↓
                            Portal renders reports
```

**MachineKey must be identical** in all three files — see `DEPLOYMENT-SSRS2019.md` Step 9.

---

## UILogon endpoint (WPF client)

`UILogon.aspx` accepts POST requests from the BancPac WPF client:

| Field | Description |
|-------|-------------|
| `UID`  | User ID |
| `PWD`  | Password |
| `BNBR` | Bank number |
| `KEY`  | Shared secret (matches `UILogon.Key1` or `UILogon.Key2` in `appSettings`) |

On valid credentials, issues `sqlAuthCookie` and returns HTTP 200. The WPF client captures the cookie and injects it into a WebView2 control. See `WpfAuthHelper/INTEGRATION_GUIDE.md`.

**Required appSettings in `BancPac.ReportingServices.BP360.dll.config`:**
```xml
<appSettings>
  <add key="UILogon.Key1" value="STRONG_RANDOM_40_CHAR_KEY" />
  <add key="UILogon.Key2" value="STRONG_RANDOM_40_CHAR_KEY_2" />
</appSettings>
```

Generate keys:
```powershell
[System.Web.Security.Membership]::GeneratePassword(40, 10)
```

---

## User management

```powershell
# Create default test users (testuser/Test@123, admin/Admin@123, report_viewer/Viewer@123)
.\scripts\Setup-Users.ps1 -CreateTestUsers -Integrated

# Register a single user
.\scripts\Setup-Users.ps1 -UserName "jdoe" -Password "Pass@123" -Integrated
```

Registered users are stored in the `UserAccounts` SQL database (localhost, Integrated Security).
Password hashing: SHA1(password + Base64Salt), stored as uppercase hex.

---

## Logon.aspx form field reference

| Purpose | Control ID |
|---------|-----------|
| Username | `TxtUser` |
| Password | `TxtPwd` |
| Login | `BtnLogon` |
| Register | `BtnRegister` |

Using wrong field names causes EventValidation errors (HTTP 500 on POST).
