Create an IIS reverse proxy for SSRS 2019 with:
- ARR enabled proxy
- URL Rewrite rules mapping /ssrs/ -> https://ssrs-server/ReportServer/
- Ensure SSRS resources (scripts/images) load correctly through the proxy
- Address redirects (Location header rewriting if necessary)
- Handle large responses/timeouts for report rendering
- Provide notes for both Windows auth (Dev/QA) and Basic (Prod)
- Include a troubleshooting checklist for 401 loops, double-hop, and broken resource URLs
Provide exact example rewrite rules and ARR settings.