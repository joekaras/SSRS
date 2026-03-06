Before we implement anything, ask me the minimum set of questions to lock down:
- .NET Framework vs .NET (Core) and why
- Hosting model (IIS, Windows service, containers)
- SSRS access pattern (Report Viewer vs URL access vs REST, native mode)
- Authentication + authorization rules (roles, groups, admin flows)
- Data sources (SQL Server version, connection strategy, secrets management)
- Environments (dev/test/prod) and deployment constraints

Then output:
1) recommended architecture diagram (textual)
2) key risks & mitigations
3) a phased plan (MVP -> hardening -> production)