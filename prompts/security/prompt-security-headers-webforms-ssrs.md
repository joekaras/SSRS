Provide secure headers for an IIS-hosted Web Forms app that embeds SSRS via an iframe through a proxy path /ssrs/.

Need:
- CSP including frame-ancestors (allow self; optionally allow specific parent pages)
- guidance for X-Frame-Options limitations
- HSTS, X-Content-Type-Options, Referrer-Policy, Permissions-Policy
- where to set: web.config <customHeaders> and/or Global.asax
- warnings about breaking SSRS scripts/styles; propose a CSP approach that doesn't break proxied SSRS

Output exact web.config snippets and explain tradeoffs.