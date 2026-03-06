Design the SSRS 2019 Native iframe embedding architecture for:
- .NET Framework 4.8 app on IIS with Forms Auth
- users authenticate only in the app
- role-based authorization stored in SQL
- user should not see / access SSRS endpoints directly

Deliverables:
1) Recommended architecture using IIS reverse proxy (ARR + URL Rewrite) OR alternative if you think better.
2) Request flow diagram (text)
3) How to construct safe embed URLs (parameter allowlist)
4) Authorization flow: user->roles->allowed reports
5) Security: CSRF, clickjacking, CSP frame-ancestors, cookies SameSite, caching, audit logging
6) Operational notes: SSRS base URL, service credentials, TLS, timeouts
End with a step-by-step implementation plan.