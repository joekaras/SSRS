Define a data access standard for this project:
- whether to use EF Core, Dapper, or ADO.NET (ask which fits constraints)
- connection management and resiliency
- transaction boundaries
- handling reporting queries vs OLTP queries
- performance guidance (indexes, timeouts, pagination)
- patterns for repository/service layers (or why to avoid repositories)

End with “team rules” we can paste into a CONTRIBUTING doc.