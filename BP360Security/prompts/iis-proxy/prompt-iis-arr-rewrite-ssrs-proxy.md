I need to expose SSRS 2019 through my app domain using IIS reverse proxy so that:
- users never directly access SSRS host
- app controls authorization
- iframe points to something like https://app.company.com/ssrs/ReportServer?...

Provide:
1) IIS prerequisites (ARR install, proxy enable)
2) URL Rewrite rules examples for /ssrs/ -> http(s)://ssrs-server/ReportServer/
3) Header/cookie considerations
4) How to handle SSRS resources (scripts, images) without breaking
5) Timeouts and buffering settings for report rendering
6) Troubleshooting checklist (common 401/403/500 issues)
Assume SSRS is Native mode.