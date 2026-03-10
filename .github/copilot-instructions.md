# GitHub Copilot Workspace Instructions

## Project Context

This is a **deployed SSRS 2019 Custom Security Extension** (Forms Authentication).
.NET Framework 4.8 class library. No IIS — SSRS 2019 Native Mode self-hosts both
the ReportServer and Portal endpoints via HTTP.sys.

The extension runs on two independent Windows servers:
- `VMLENOVO` — service account `VMLENOVO\ssrssvc`
- `VWMAZBPTESTBP360` — service account `vwmazbptestbp360\bp360svcc`

Scripts auto-detect the server via `$env:COMPUTERNAME` using `scripts/Environment.ps1`.

## Auth Architecture

```
Browser / WPF WebView2
    ↓
logon.aspx  or  UILogon.aspx (server-to-server)
    ↓
FormsAuthentication.SetAuthCookie() → sqlAuthCookie
    ↓
RSPortal decrypts cookie via FormsAuthentication.Decrypt
    ↓
Portal renders reports
```

**Critical**: MachineKey must be identical in all three files:
- `ReportServer\rsreportserver.config` (`<MachineKey>` Pascal case under `<Configuration>`)
- `ReportServer\web.config` (`<machineKey>` inside `<system.web>`)
- `Portal\RSPortal.exe.config` (`<machineKey>` inside `<system.web>`)

## Non-Negotiables (apply to every suggestion)

- Report paths must come from a DB allowlist — never from raw browser input.
- Parameters are allowlisted per report and validated server-side.
- Every report view is authorization-checked and audit-logged.
- Anti-forgery tokens on all POST operations.
- Cookies: `Secure; HttpOnly; SameSite` — review SameSite for iframe context.
- CSP with `frame-ancestors` set; do not rely solely on `X-Frame-Options`.
- Centralize SSRS URL building; never ad-hoc string concatenation.
- Timeouts handled explicitly (SSRS rendering can be slow).
- No secrets in source code; use `appSettings` in DLL config or environment variables.
- `UILogon.aspx` shared keys (`UILogon.Key1` / `UILogon.Key2`) must be strong random values, never hardcoded in source.

## Key Patterns

- Auth extension: `IAuthenticationExtension2` in `AuthenticationExtension.cs`
- Authorization: `IAuthorizationExtension` in `Authorization.cs`
- User store: `UserAccounts` SQL DB → `LookupUser` / `RegisterUser` stored procs
- Password hashing: SHA1(password + Base64Salt) → uppercase hex
- Logging: `SecurityLog.Info()` / `Warn()` / `Error()` (Windows Event Log)
- UILogon: POST UID/PWD/BNBR/KEY → validate key from `appSettings` → `FormsAuthentication.SetAuthCookie()`
- WPF client: `WpfAuthHelper/SsrsAuthHelper.cs` + `Microsoft.Web.WebView2` NuGet

## Prompt Library

Reusable prompts are in `prompts/` organized by concern:
- `prompts/architecture/`     — system design decisions
- `prompts/auth/`             — Forms Auth, roles, proxy auth strategy
- `prompts/data/`             — SQL schema, queries, DAL patterns
- `prompts/security/`         — headers, CSP, threat model
- `prompts/ssrs-url-builder/` — safe URL construction
- `prompts/thin-slice/`       — end-to-end feature slices
- `prompts/testing/`          — test strategy, definition of done
- `prompts/playbooks/`        — master briefs / senior engineer context
- `prompts/misc/`             — local dev setup, quick micro-prompts

## Skills Checklist

See `skills/skills-checklist.md` — treat each rule as a review gate before marking any feature complete.
