Implement forms authentication for this app.

First ask whether this is:
A) ASP.NET Framework 4.8 (System.Web) OR
B) ASP.NET Core (.NET 6/8)

Then provide:
- recommended auth mechanism (cookie auth / Identity, etc.)
- login/logout flow
- password storage approach (hashing, policies)
- account lockout + MFA-ready design notes
- anti-forgery, same-site cookie settings, secure headers
- role/claims authorization example (admin vs standard user)
- minimal code snippets + config (web.config or appsettings + middleware)