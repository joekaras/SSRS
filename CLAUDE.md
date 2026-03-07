# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

.NET Framework 4.8 · ASP.NET Web Forms · IIS · SSRS 2019 Native Mode · Forms Authentication

This repository is currently a **prompt engineering library** for building a secure SSRS report portal. No application code exists yet — the `prompts/` folder contains detailed design prompts organized by concern, and `skills/` contains the engineering review gate.

## Architecture Overview

**Flow**: User → App (Forms Auth) → `/reportview.aspx?reportId=N` → server checks authz, builds URL → iframe renders via `/ssrs/...` → IIS ARR proxies to SSRS with Basic Auth header injection.

**Data model**: `Users ← UserRoles → Roles → RoleReports → Reports → ReportParameters` + `ReportViewAudit` for audit logging.

**Key patterns**:
- Auth: `FormsAuthentication` with SQL-backed roles (`users → roles → reports`)
- Proxy: IIS ARR + URL Rewrite at `/ssrs/*` → SSRS ReportServer
- Upstream SSRS auth: Basic Authentication with dedicated service account
- URL construction: always via `SsrsUrlBuilder` class
- Audit: `ReportViewAudit` table (userId, reportId, timestamp, clientIP, parametersHash)

**Environment split**: Dev/QA share Windows domain with SSRS (Windows or Basic auth); Prod does not (must use Basic auth).

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
