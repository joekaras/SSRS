# BP360Security — SSRS 2019 Custom Security Extension

Forms Authentication custom security extension for **SQL Server Reporting Services 2019 Native Mode**, based on the Microsoft sample and customized for production use.

## What this repo contains

| Folder | Contents |
|--------|----------|
| `BP360Security/` | The active extension project (.NET Framework 4.8 class library) |
| `BP360Security/scripts/` | PowerShell scripts: build, deploy, configure, test, backup |
| `BP360Security/Setup/` | `CreateUserStore.sql` — creates the `UserAccounts` database |
| `BP360Security/2012Extension/` | Legacy VB.NET files from the SSRS 2012 version (reference only) |
| `WpfAuthHelper/` | Reference implementation for WPF clients using WebView2 instead of the IE WebBrowser control |
| `prompts/` | Reusable AI prompt library organized by concern |
| `extensions/` | Microsoft SSRS extension SDK reference documentation |

## Quick start — deploy to a server

```powershell
# Run as Administrator on the target server
.\BP360Security\scripts\Deploy-CustomSecurity.ps1
```

The script auto-detects the server (`VMLENOVO` or `VWMAZBPTESTBP360`), builds the DLL, sets up the database, patches all config files, and restarts SSRS.

See `BP360Security/DEPLOYMENT-SSRS2019.md` for the full manual step-by-step guide.

## Servers

| Server | Portal URL |
|--------|-----------|
| VMLENOVO | http://vmlenovo/Reports |
| VWMAZBPTESTBP360 | http://vwmazbptestbp360/Reports |

## Key components

- **`AuthenticationExtension.cs`** — implements `IAuthenticationExtension2`; validates credentials against the `UserAccounts` SQL database
- **`Authorization.cs`** — implements `IAuthorizationExtension`; admin configured in `rsreportserver.config`
- **`AuthenticationUtilities.cs`** — SHA1+salt password hashing; DB calls via `LookupUser` / `RegisterUser` stored procs
- **`Logon.aspx`** — browser-facing login page placed in the ReportServer virtual directory
- **`UILogon.aspx`** — server-to-server login endpoint for the BancPac WPF client (posts UID/PWD/BNBR/KEY, returns `sqlAuthCookie`)
- **`Logging/EventLogWriter.cs`** — Windows Event Log wrapper
- **`Logging/SecurityLog.cs`** — shared singleton logger for the extension

## WPF client integration

See `WpfAuthHelper/INTEGRATION_GUIDE.md` for how to replace the old `WebBrowser` (IE) control with `WebView2` (Chromium/Edge) using `SsrsAuthHelper.cs`.

**NuGet required in WPF project**: `Microsoft.Web.WebView2`
