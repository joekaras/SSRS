# GitHub Copilot Workspace Instructions

## Project Context
This is a .NET Framework 4.8 ASP.NET Web Forms app hosted on IIS.
It embeds SSRS 2019 (Native mode) reports via iframe through an IIS reverse proxy.
Users authenticate via Forms Authentication only. SSRS is never accessed directly by end users.

## Non-Negotiables (apply to every suggestion)
- Report paths come from DB allowlist only — never from raw browser input.
- Parameters are allowlisted per report and validated server-side.
- Every report view is authorization-checked and audit-logged.
- Anti-forgery tokens on all POST operations.
- Cookies: Secure + HttpOnly + SameSite reviewed for iframe scenario.
- CSP with `frame-ancestors` set; do not rely solely on `X-Frame-Options`.
- Centralize SSRS URL building via `SsrsUrlBuilder`; never ad-hoc string concat.
- Timeouts handled explicitly (SSRS rendering can be slow).
- No secrets in source code or web.config plaintext in production.

## Key Patterns
- Auth: `System.Web.Security.FormsAuthentication`
- Roles: SQL-backed (`users -> roles -> reports`)
- SSRS proxy path: `/ssrs/...` via IIS ARR + URL Rewrite
- Upstream SSRS auth: Basic Authentication with a dedicated service account
- URL builder: `SsrsUrlBuilder` class (see `prompts/ssrs-url-builder/`)
- Audit log: `ReportViewAudit` table (userId, reportId, timestamp, ip, parametersHash)

## Prompt Library
Reusable prompts are in `prompts/` organized by concern:
- `prompts/architecture/`     — system design decisions
- `prompts/auth/`             — Forms Auth, roles, proxy auth strategy
- `prompts/data/`             — SQL schema, queries, DAL patterns
- `prompts/iis-proxy/`        — ARR + URL Rewrite configuration
- `prompts/security/`         — headers, CSP, threat model
- `prompts/ssrs-url-builder/` — safe URL construction
- `prompts/thin-slice/`       — end-to-end feature slices
- `prompts/testing/`          — test strategy, definition of done
- `prompts/playbooks/`        — master briefs / senior engineer context
- `prompts/misc/`             — local dev setup, quick micro-prompts

## Skills Checklist
See `skills/skills-checklist.md` — treat each rule as a review gate before marking any feature complete.
