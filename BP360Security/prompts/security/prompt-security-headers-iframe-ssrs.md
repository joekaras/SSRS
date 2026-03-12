Configure secure headers for an ASP.NET Framework 4.8 app that embeds SSRS via iframe.

Need:
- CSP recommendation (especially frame-ancestors) to allow framing only by our app pages
- Whether to use X-Frame-Options (and limitations)
- HSTS, X-Content-Type-Options, Referrer-Policy, Permissions-Policy
- Where to set headers (web.config vs global.asax vs IIS)
- Special notes for SSRS pages proxied through our site

Provide exact web.config snippets and explain tradeoffs.