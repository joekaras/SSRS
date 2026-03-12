Engineering rules for this project:
- All SSRS report paths must be sourced from DB allowlist; never accept arbitrary paths from the browser.
- All SSRS parameters must be allowlisted per report and validated server-side.
- Every report view is authorization-checked and audit-logged (user, report, parameters hash, timestamp).
- SSRS is only reachable through app domain (reverse proxy); direct SSRS host blocked by network/firewall if possible.
- Anti-forgery on all POSTs; no state-changing GET endpoints.
- Cookies: Secure + HttpOnly; SameSite reviewed for iframe scenario.
- Add CSP with frame-ancestors (do not rely solely on X-Frame-Options).
- Centralize URL building; never concatenate query strings ad-hoc.
- Timeouts handled explicitly (report rendering can be slow).