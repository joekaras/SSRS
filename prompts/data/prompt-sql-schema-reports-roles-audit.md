Design the SQL schema for:
- Users, Roles, UserRoles
- Reports (id, ssrsPath, displayName, enabled)
- RoleReports mapping
- ReportParameters allowlist (reportId, name, type, required, allowedValues/min/max)
- ReportViewAudit table (userId, reportId, timestamp, ip, userAgent, parametersHash)

Provide:
- concise DDL-ish definitions
- indexes
- key queries:
  1) list reports for user
  2) authorize report access (user + reportId)
  3) get allowed parameters for report
  4) insert audit record