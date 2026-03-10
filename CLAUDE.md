# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

.NET Framework 4.8 · SSRS 2019 Native Mode · Custom Security Extension · Forms Authentication

This repository contains a **deployed SSRS 2019 Custom Security Extension** (Forms Authentication) based on the Microsoft sample, customized for production use on `VMLENOVO`. The `BP360Security/` folder is the active codebase. The `prompts/` folder contains design prompts for future portal work.

### Deployed Environment

- **Host**: `VMLENOVO` (Windows Server, IIS)
- **SSRS install**: `C:\Program Files\Microsoft SQL Server Reporting Services\SSRS\`
- **Service account**: `VMLENOVO\ssrssvc` (runs both RSHostingService and SQL Server)
- **Portal URL**: `http://vmlenovo/Reports`
- **ReportServer URL**: `http://vmlenovo/ReportServer`
- **User store**: SQL Server `UserAccounts` database (localhost, Integrated Security)
- **Auth cookie**: `sqlAuthCookie` (Forms Authentication, 60-min timeout)

## Architecture Overview

**Auth flow**: Browser → `logon.aspx` (ReportServer) → FormsAuth cookie (`sqlAuthCookie`) → RSPortal decrypts cookie via `FormsAuthentication.Decrypt` → portal renders reports.

**Extension components**:
- `AuthenticationExtension.cs` — implements `IAuthenticationExtension2`; validates credentials against `UserAccounts.LookupUser` stored procedure
- `Authorization.cs` — implements `IAuthorizationExtension`; admin configured via `rsreportserver.config`
- `AuthenticationUtilities.cs` — SHA1+salt password hashing; connection string from `Properties.Settings.Default.Database_ConnectionString`

**User store**: `UserAccounts` DB → `Users` table → `LookupUser` / `RegisterUser` stored procs.
Password hashing: SHA1(password + Base64Salt), stored as uppercase hex.

**Key config files**:

| File | Purpose |
|------|---------|
| `ReportServer\rsreportserver.config` | Auth extension registration, MachineKey, PassThroughCookies |
| `ReportServer\web.config` | Forms Auth mode, cookie name, MachineKey (must match rsreportserver.config) |
| `Portal\RSPortal.exe.config` | MachineKey for RSPortal's FormsAuthentication.Decrypt (CRITICAL — must match) |
| `ReportServer\rssrvpolicy.config` | FullTrust code group for the custom security DLL |

## Critical: MachineKey Must Be Identical in All Three Places

RSPortal runs as a separate OWIN process and calls `FormsAuthentication.Decrypt` using its own `RSPortal.exe.config`. If the MachineKey in `RSPortal.exe.config` does not match `web.config` and `rsreportserver.config`, the portal returns HTTP 500 with "Unable to validate data."

All three files must contain:
```xml
<machineKey validationKey="D549EC24E7C65C59C6486CCC68E7990C26D7812C62151F015A6F5B7224DBDB4D26478B8012305BDF5DCB1F280AB8E747B85CDD7E71FF23E85BFCB3EB0973C47F" decryptionKey="F3AF0D7C6EBEB09B0AB332DB91818F05F70746750CBDD43E96E3444F888510AA" validation="AES" decryption="AES" />
```

In `rsreportserver.config` the element uses Pascal case (`<MachineKey>`) under `<Configuration>` (not `<system.web>`).

## Service Account Permissions (VMLENOVO\ssrssvc)

RSHostingService runs as `VMLENOVO\ssrssvc` (NOT the virtual `NT SERVICE\SQLServerReportingServices`). This account needs:

1. **Modify** on `ReportServer\web.config` — RSHostingService rewrites it at startup to sync MachineKey
2. **Modify** on `ReportServer\rssrvpolicy.config` — same startup sync
3. **SQL login** in `UserAccounts` DB with `EXECUTE` on `LookupUser` and `RegisterUser`

## Logon.aspx Form Field Names

The correct ASP.NET control IDs (required for any test scripts or automation):
- Username field: `TxtUser`
- Password field: `TxtPwd`
- Login button: `BtnLogon`
- Register button: `BtnRegister`

## Scripts

| Script | Purpose |
|--------|---------|
| `BP360Security/scripts/Setup-Users.ps1` | Register users in UserAccounts DB (use `-Integrated` flag) |
| `BP360Security/Setup/CreateUserStore.sql` | Create UserAccounts DB, tables, stored procs |

**No IIS required**: SSRS 2019 Native Mode self-hosts both endpoints via HTTP.sys (URL reservations managed by Reporting Services Configuration Manager). IIS is only needed if a separate front-end proxy application is added.

## Hard Rules

1. **Report paths**: always fetched from DB by `reportId`; never trust browser input for ssrsPath.
2. **Parameters**: validated server-side against per-report allowlist (type, range, enum).
3. **Authorization**: checked before every report render; result audit-logged.
4. **CSRF**: `ViewStateUserKey` + AntiForgery on every POST; no state-changing GETs.
5. **Cookies**: `Secure; HttpOnly; SameSite` — review SameSite for iframe context.
6. **CSP**: `frame-ancestors` must be set; `X-Frame-Options` alone is insufficient.
7. **SSRS URL building**: always via `SsrsUrlBuilder`; no ad-hoc concatenation.
8. **Secrets**: use environment variables or DPAPI-encrypted config; never plaintext.
9. **Timeouts**: configure explicit timeouts for SSRS proxy calls.
10. **Audit log**: every report view logs userId, reportId, timestamp, clientIP, parametersHash.

## Skills Gate

Before marking any feature complete, verify every item in `skills/skills-checklist.md`.

## Prompt Library

| Folder | Use when you need... |
|--------|----------------------|
| `prompts/playbooks/` | Full senior-engineer context to start a session |
| `prompts/architecture/` | System design, SSRS integration approach |
| `prompts/auth/` | Forms Auth setup, role provider, proxy auth |
| `prompts/data/` | SQL schema, DAL, caching strategy |
| `prompts/iis-proxy/` | ARR + URL Rewrite config snippets |
| `prompts/security/` | Headers, CSP, threat model |
| `prompts/ssrs-url-builder/` | Safe SSRS URL construction code |
| `prompts/thin-slice/` | End-to-end feature implementation |
| `prompts/testing/` | Test plan, definition of done |
| `prompts/misc/` | Local dev setup, quick micro-prompts |

## Suggested Session Start

Paste the contents of `prompts/playbooks/prompt-playbook-webforms-ssrs2019-proxy-basic.md`
or `prompts/playbooks/prompt-master-brief-48-ssrs-proxy-envsplit.md` at the top of your
conversation to give Claude full project context.
