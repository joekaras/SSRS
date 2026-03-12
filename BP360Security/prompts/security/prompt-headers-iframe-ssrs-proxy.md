Provide a secure headers configuration for an IIS-hosted .NET 4.8 app that embeds proxied SSRS pages in an iframe.

Need:
- CSP policy including frame-ancestors
- Guidance on X-Frame-Options (and why CSP is preferred)
- HSTS, X-Content-Type-Options, Referrer-Policy, Permissions-Policy
- Where/how to set in web.config and/or IIS
- Considerations for SSRS content coming through /ssrs/ proxy path (avoid breaking scripts/styles)
Provide exact web.config snippets and explain what might break.