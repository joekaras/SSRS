Implement Forms Authentication in ASP.NET Web Forms (.NET Framework 4.8) with role-based authorization stored in SQL.

Need:
- web.config forms auth setup
- login.aspx + login.aspx.cs sample (validate user, set auth cookie)
- Global.asax guidance for principal/roles loading per request
- role checks in pages (e.g., redirect to 403 page)
- secure cookie settings (Secure, HttpOnly, SameSite) and session timeout settings
- CSRF guidance for Web Forms (ViewStateUserKey, anti-forgery patterns)
Also include password hashing best practices for .NET Framework 4.8.