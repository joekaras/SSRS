Create the IIS configuration to reverse-proxy SSRS 2019 through our app domain.

Requirements:
- ARR enabled with proxy
- URL Rewrite: /ssrs/{R:1} -> https://SSRS_HOST/ReportServer/{R:1}
- Must work for SSRS HTML viewer in an iframe (scripts/images/css)
- Handle redirects so relative links keep working under /ssrs/
- Upstream auth: inject Authorization header for Basic auth using SSRS service account
- Timeouts tuned for long report rendering
- Security: prevent direct access to SSRS_HOST (note firewall / IIS request filtering guidance)

Output:
- step-by-step IIS setup instructions
- example rewrite rules (XML)
- where/how to store credentials securely on the IIS server
- troubleshooting checklist for 401 loops, broken resources, and mixed-content issues