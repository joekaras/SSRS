# Frequently Asked Questions

See also: [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for error diagnosis.

## General

### What is this project?

A custom Forms Authentication extension for SSRS 2019 Native Mode. Replaces default Windows auth with a SQL Server-backed credential store.

### Why not just use Windows Authentication?

- Supports non-domain users
- Better for multi-tenant scenarios (bank-scoped users: BNBR-UID)
- Simpler setup without domain infrastructure
- Better audit logging

### Who can deploy this?

- System administrators with SSRS 2019 install access
- SQL Server DBA (to create UserAccounts database and configure logins)
- .NET developers (to build the DLL and troubleshoot code issues)

### What is the license?

MIT License (see LICENSE file). Free to use and modify.

### What is a BNBR-UID username?

Bank-scoped username: `BNBR-UID` where BNBR=bank number (e.g., `532-testuser`).
- Used when WPF posts KEY=`UILogon.Key1`
- Allows same user ID across multiple banks

### Can I extend the Users table?

Yes. Modify:
1. SQL schema: `ALTER TABLE Users ADD ...`
2. `LookupUser` / `RegisterUser` stored procs
3. `AuthenticationUtilities.cs` if using new fields

### Can I use Active Directory instead?

Yes, but requires modifying `AuthenticationExtension.cs` to use `PrincipalContext`. Not provided in sample.

---

## Architecture & Design

### What's the difference between logon.aspx and UILogon.aspx?

| Endpoint | Client | Purpose |
|----------|--------|---------|
| **logon.aspx** | Browser | HTML login form; also embeds the UILogon API handler (KEY in POST body) |
| **UILogon.aspx** | WPF app / browser | REST-like API; returns JSON + cookie; supports `ReturnUrl` for browser redirect |

### Can I run two SSRS instances on the same machine?

Not recommended. Named instances complicate config paths. Use separate machines if possible.

---

## Deployment

### How long does deployment take?

- Automated: 5-10 min (`Deploy-CustomSecurity.ps1`)
- Manual: 20-30 min ([DEPLOYMENT-SSRS2019.md](DEPLOYMENT-SSRS2019.md) steps)

### What if I deploy to multiple servers?

Same repo, each dev clones it. Scripts auto-detect server via `$env:COMPUTERNAME`.

**Important**: UILogon keys can be shared. MachineKey must match if behind load balancer.

### How do I upgrade versions?

1. Backup configs (automatic)
2. Build new DLL
3. Run `Configure-CustomSecurity.ps1`
4. Restart SSRS
5. Test login

No database migration needed.

---

## Security

### Is the password secure?

Only over HTTPS in production. Never log passwords.

### What if I forget the UILogon.Key?

It's stored in `dll.config`. Retrieve it:

```powershell
[xml]$cfg = Get-Content "C:\Program Files\Microsoft SQL Server Reporting Services\SSRS\ReportServer\bin\BancPac.ReportingServices.BP360.dll.config"
$cfg.SelectSingleNode("//appSettings/add[@key='UILogon.Key1']").value
```

### Can I use a weaker password hash (e.g., MD5)?

No. SHA1 is the minimum. Consider upgrading to bcrypt or PBKDF2 if enhancing the code.

### What's the password hash algorithm?

SHA1(password + Base64Salt). Consider upgrading to bcrypt if enhancing.

### How do I rotate MachineKey?

1. Generate new key: `Generate-MachineKeys.ps1`
2. Update all three config files
3. Restart SSRS
4. All users forced to re-login

### How often should I rotate the key?

Yearly or after a security incident.

### What if someone steals the MachineKey?

They can forge Forms Auth cookies. Rotate immediately:
1. Generate new MachineKey via `Generate-MachineKeys.ps1`
2. Update all three config files simultaneously
3. Restart SSRS
4. Force re-login for all users (old cookies become invalid)

---

## Testing

### Where are the smoke tests?

```
BP360Security/scripts/
  ├── Test-SSRSEndpoints.ps1
  ├── Test-UILogon.ps1
  ├── Test-FormsAuth.ps1
  └── SmokeTest-Logon.ps1
```

### Default test user credentials?

**Regular login**:
- Username: `999-testuser`
- Password: `Test@123`

**UILogon (Key1)**:
- UID: `testuser`
- BNBR: `532`
- KEY: read from `dll.config`

### Can I test locally?

Yes. SSRS 2019 uses HTTP.sys (no IIS). Deploy to local SSRS, access via `http://localhost/Reports`.

### How do I test with existing SSRS reports?

1. Create a test report in SSRS via Report Builder
2. Save to ReportServer catalog
3. Login and navigate via portal
4. Check authorization (should use Authorization.cs)

---

## Performance

### How fast is the password hash?

SHA1(password + salt) is < 1 ms. Per-login cost is negligible.

### What's the maximum number of concurrent users?

Limited by SQL Server connection pool and SSRS capacity (not this extension). Typical: 100–1000 concurrent users per server.

### Should I cache the password hash?

No. Always hash on login. Don't cache across requests.

### Can I add caching for reports?

Yes. SSRS Report Caching is independent of auth. Configure in ReportServer catalog properties (portal UI).

---

## Integration

### How do I add my WPF app?

See `WpfAuthHelper/INTEGRATION_GUIDE.md`. Two modes:

**Embedded (WebView2)**:
1. Add `Microsoft.Web.WebView2` NuGet
2. POST to UILogon.aspx (UID/PWD/BNBR/KEY)
3. Capture `sqlAuthCookie`
4. Inject into WebView2 via `CoreWebView2Cookie`
5. Navigate WebView2 to `http://[host]/Reports`

**External browser (Edge/default)**:
1. Call `SsrsEdgeLauncher.LaunchAsync(uid, pwd, bnbr)`
2. Edge opens pre-authenticated via one-shot trampoline — no cookie injection needed

### Can I use OAuth or SAML instead?

Not in current sample. Forms Auth only. For OAuth/SAML consider:
- Azure AD B2C for social login
- Okta federation
- Custom `IAuthenticationExtension2` implementation

### How do I audit report access?

Implement logging in `Authorization.cs`:

```csharp
SecurityLog.Info("ReportAccess", $"User {userId} accessed {reportPath}");
```

Then query Windows Event Log: `Get-EventLog -LogName Application -Source BP360Security`.

---

## Troubleshooting Quick Links

- **HTTP 500 "Unable to validate data"** → [MachineKey mismatch](TROUBLESHOOTING.md#unable-to-validate-data-http-500)
- **"Cannot connect to SQL Server"** → [Service account permissions](TROUBLESHOOTING.md#cannot-connect-to-sql-server--connection-timeout)
- **UILogon showing HTTP 401** → [Invalid key](TROUBLESHOOTING.md#invalid-key-presented-uilogon-http-401)
- **Login hangs** → [Check SQL / SSRS service](TROUBLESHOOTING.md#troubleshooting-quick-links)
- **No Event Log entries** → [Register event source](TROUBLESHOOTING.md#windows-event-log-shows-no-auth-entries)

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for full error guide.

---

## Roadmap & Future Enhancements

### Not Yet Implemented

- OAuth/SAML support
- Multi-factor authentication (MFA)
- Password expiration / reset flow
- User lockout after N failed attempts
- Rate limiting on login endpoint

### Possible Improvements

- bcrypt hashing instead of SHA1
- Azure Key Vault integration for MachineKey storage
- Role-based access control (RBAC) at DB level
- Graphical admin console for user management
- API to programmatically manage UILogon keys
