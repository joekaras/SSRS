Design a SQL-based authorization model for SSRS embedding.

Requirements:
- users authenticate via app forms auth
- map users -> roles -> allowed reports (and optionally folders)
- allow per-report parameter restrictions (optional)
- support environment-specific SSRS paths (Dev/Test/Prod)

Output:
1) Proposed SQL tables (DDL-ish) for Users, Roles, UserRoles, Reports, RoleReports
2) Example queries for: get allowed reports for user; check access for reportPath
3) C# data access approach (ADO.NET/Dapper) for these lookups
4) Caching recommendations (memory cache with invalidation strategy)
5) Audit logging schema (who viewed which report, when, parameters)