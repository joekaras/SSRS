Write .NET Framework 4.8 C# code for a safe SSRS iframe URL builder.

Requirements:
- Input: current user, reportId, and requested parameters from UI
- Server-side: verify user is authorized for reportId
- Server-side: fetch SSRS path + allowed parameters from DB
- Validate and normalize parameter values by type:
  - DateTime (with range limits)
  - int/decimal
  - enum from allowlist
  - string with length limits
- Build the final proxied URL under our domain: /ssrs/?<query>
- Ensure proper URL encoding and prevent injection
- Return structured validation errors

Deliver:
- DTOs + SsrsUrlBuilder class
- example usage from a handler/controller endpoint (framework-agnostic if you don’t know whether MVC/WebForms/OWIN yet)
- unit test cases list