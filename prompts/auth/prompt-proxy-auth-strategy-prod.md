Given:
- IIS reverse proxies SSRS 2019 Native mode
- Dev/QA can use Windows auth to SSRS (same domain)
- Production cannot rely on Windows auth (different domain)
- SSRS supports Basic auth

Choose and justify a production-proof strategy for IIS->SSRS authentication:
Option 1: Always use Basic from proxy to SSRS (all envs)
Option 2: Windows in Dev/QA, Basic in Prod (env-dependent)
Option 3: Establish domain trust / Kerberos delegation for Prod
Option 4: Other

For the chosen strategy, provide:
- required SSRS configuration
- how to store credentials securely (DPAPI, machineKey-protected config, Windows Credential Manager, etc.)
- operational guidance (rotation, least privilege)
- what to log
- failure modes and troubleshooting
End with a concrete recommendation.