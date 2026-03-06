# Claude Code Instructions

## Project
.NET Framework 4.8 · ASP.NET Web Forms · IIS · SSRS 2019 Native Mode · Forms Authentication

## Hard Rules
1. **Report paths**: always fetched from DB by `reportId`; never trust browser input for ssrsPath.
2. **Parameters**: validated server-side against per-report allowlist (type, range, enum).
3. **Authorization**: checked before every report render; result audit-logged.
4. **CSRF**: `ViewStateUserKey` + AntiForgery on every POST.
5. **Cookies**: `Secure; HttpOnly; SameSite` — review SameSite for iframe context.
6. **CSP**: `frame-ancestors` must be set; `X-Frame-Options` alone is insufficient.
7. **SSRS URL building**: always via `SsrsUrlBuilder`; no ad-hoc concatenation.
8. **Secrets**: use environment variables or DPAPI-encrypted config; never plaintext.
9. **Timeouts**: configure explicit timeouts for SSRS proxy calls.
10. **Audit log**: every report view logs userId, reportId, timestamp, clientIP, parametersHash.

## Prompt Library Index
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

## Skills Gate
Before marking any feature complete, verify every item in `skills/skills-checklist.md`.

## Suggested Session Start
Paste the contents of `prompts/playbooks/prompt-playbook-webforms-ssrs2019-proxy-basic.md`
or `prompts/playbooks/prompt-master-brief-48-ssrs-proxy-envsplit.md` at the top of your
conversation to give Claude full project context.
