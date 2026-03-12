# SSRS 2019 Custom Security Extension — Documentation

Complete guide for SSRS 2019 Custom Security Extension (Forms Authentication) deployment, architecture, security, and testing.

## Quick Start

New to this project? Start here:
1. [CLAUDE.md](../CLAUDE.md) — Architecture overview, auth flow, all scripts, hard rules
2. [Deployment Guide](DEPLOYMENT-SSRS2019.md) — Step-by-step setup and configuration
3. [Integration Guide](../WpfAuthHelper/INTEGRATION_GUIDE.md) — WPF client integration (embedded + external browser)

## Documentation Index

| Document | Purpose |
|----------|---------|
| [DEPLOYMENT-SSRS2019.md](DEPLOYMENT-SSRS2019.md) | Complete step-by-step deployment, config syntax, backup/rollback, smoke tests |
| [TESTING.md](TESTING.md) | Test strategy, smoke tests, definition of done, validation checklist |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Common errors, MachineKey issues, database connection failures, logs |
| [FAQ.md](FAQ.md) | Frequent questions, known limitations, workarounds |

## Component Documentation (in-place)

- [BP360Security/README.md](../BP360Security/README.md) — Extension DLL, stored procs, logging
- [WpfAuthHelper/INTEGRATION_GUIDE.md](../WpfAuthHelper/INTEGRATION_GUIDE.md) — WPF client setup, WebView2, auth flow

## Workspace Context

- [CLAUDE.md](../CLAUDE.md) — Team instructions, scripts table, skills gate, hard rules

## Key Concepts

**Authentication Flow**: Browser → `logon.aspx` → Forms Auth cookie (`sqlAuthCookie`) → Portal decrypts via `FormsAuthentication.Decrypt`

**User Store**: SQL `UserAccounts` DB → `Users` table → `LookupUser`/`RegisterUser` stored procs

**UILogon (WPF)**: Server-to-server endpoint; WPF POSTs UID/PWD/BNBR/KEY → receives cookie → injects into WebView2

**Critical**: MachineKey must be **identical** in three places:
- `rsreportserver.config`
- `web.config`
- `RSPortal.exe.config`

## Environments

| Setting | VMLENOVO | VWMAZBPTESTBP360 |
|---------|----------|-----------------|
| Service account | `VMLENOVO\ssrssvc` | `vwmazbptestbp360\bp360svcc` |
| Portal URL | `http://vmlenovo/Reports` | `http://vwmazbptestbp360/Reports` |
| ReportServer URL | `http://vmlenovo/ReportServer` | `http://vwmazbptestbp360/ReportServer` |
| SQL Server | localhost | localhost |

## Scripts

| Script | Purpose |
|--------|---------|
| `Deploy-CustomSecurity.ps1` | Full deploy: build → DB → backup → copy files → configure → restart |
| `Configure-CustomSecurity.ps1` | Patch configs, set permissions, generate UILogon keys, restart service |
| `Setup-Users.ps1` | Register test users (default: 999-testuser, 532-admin for UILogon) |
| `Test-UILogon.ps1` | Smoke test UILogon.aspx endpoint |
| `Test-SSRSEndpoints.ps1` | Verify ReportServer / Portal connectivity |

Full script reference in [CLAUDE.md](../CLAUDE.md).
