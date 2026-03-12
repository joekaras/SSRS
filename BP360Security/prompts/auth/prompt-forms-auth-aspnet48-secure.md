Implement Forms Authentication securely in an ASP.NET Framework 4.8 MVC app (System.Web).

Need:
- web.config forms auth setup
- login/logout controller actions
- password hashing guidance (PBKDF2 via Rfc2898DeriveBytes) and account lockout
- role-based authorization integration (AuthorizeAttribute + custom role provider OR claims via OWIN cookie if you recommend it)
- CSRF protection with AntiForgery tokens
- secure cookie settings: Secure, HttpOnly, SameSite (note iframe scenario)
- session timeout and sliding expiration guidance
- secure headers suitable for an app embedding SSRS (CSP with frame-ancestors, X-Content-Type-Options, etc.)

Provide minimal code + config with explanations and “do not do this” warnings.