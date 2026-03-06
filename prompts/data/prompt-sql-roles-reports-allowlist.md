Design the SQL schema and queries for:
- Users (app identities), Roles, UserRoles
- Reports (unique key, ssrsPath, displayName, enabled flag)
- RoleReports mapping
- ReportParameters allowlist: reportId, paramName, type, required, allowedValues (optional), min/max (optional)

Output:
- table definitions (concise)
- index recommendations
- queries:
  1) list allowed reports for user
  2) authorize access to a specific report path
  3) get allowed parameters for a report
- caching plan in app (memory cache TTL + invalidation approach)
- audit log table for report views (store a hash of parameters, not raw secrets)