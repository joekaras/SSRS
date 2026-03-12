# Troubleshooting Guide

Common errors, root causes, and solutions.

## "Unable to validate data" (HTTP 500)

**Cause**: MachineKey mismatch between config files.

**Root**: RSPortal running as separate OWIN process cannot decrypt Forms Auth cookie. MachineKey in `RSPortal.exe.config` doesn't match `rsreportserver.config` and `web.config`.

**Solution**:

1. Verify all three files have **identical** validationKey and decryptionKey:
   ```
   rsreportserver.config:   <MachineKey validationKey="ABC123..." decryptionKey="DEF456..." />
   web.config:              <machineKey validationKey="ABC123..." decryptionKey="DEF456..." />
   RSPortal.exe.config:     <machineKey validationKey="ABC123..." decryptionKey="DEF456..." />
   ```

2. Regenerate keys if unsure:
   ```powershell
   .\scripts\Generate-MachineKeys.ps1
   ```

3. Restart SSRS service:
   ```powershell
   Restart-Service SQLServerReportingServices
   ```

4. Clear browser cache and retry login.

## "Cannot connect to SQL Server" / "Connection timeout"

**Cause**: Service account lacks SQL login or database permission.

**Check**:

1. Verify service account:
   ```
   Services → SQLServerReportingServices → Properties → Log On tab
   Note the account name (e.g., VMLENOVO\ssrssvc)
   ```

2. Test SQL login:
   ```sql
   -- In SQL Server Management Studio
   SELECT 1 FROM sys.server_principals WHERE name = 'VMLENOVO\ssrssvc';  -- Must return 1
   ```

3. Grant database access:
   ```sql
   USE UserAccounts;
   CREATE USER [VMLENOVO\ssrssvc] FOR LOGIN [VMLENOVO\ssrssvc];
   GRANT EXECUTE ON dbo.LookupUser   TO [VMLENOVO\ssrssvc];
   GRANT EXECUTE ON dbo.RegisterUser TO [VMLENOVO\ssrssvc];
   ```

4. Verify connection string in `dll.config`:
   ```xml
   <add key="Database_ConnectionString" value="Server=localhost;Database=UserAccounts;Integrated Security=true;" />
   ```

5. Restart SSRS service.

## "Required fields missing" (UILogon HTTP 400)

**Cause**: WPF client not sending all four POST fields.

**Check UILogon expects**:
- `UID` — user ID
- `PWD` — password
- `BNBR` — bank number
- `KEY` — shared secret (UILogon.Key1 or UILogon.Key2)

**Solution**:

1. Test manually:
   ```powershell
   .\scripts\Test-UILogon.ps1 -UID testuser -PWD Test@123 -BNBR 532
   ```

2. Check WPF code: Ensure all four fields are POSTed.

3. Check `UILogon.Key` in WPF `App.config` matches server `dll.config`.

## "Invalid KEY presented" (UILogon HTTP 401)

**Cause**: WPF is posting wrong shared key.

**Check**:

1. Read key from server:
   ```powershell
   # Run on deployment server
   $dllConfigPath = "C:\Program Files\Microsoft SQL Server Reporting Services\SSRS\ReportServer\bin\BancPac.ReportingServices.BP360.dll.config"
   [xml]$cfg = Get-Content $dllConfigPath
   $cfg.SelectSingleNode("//appSettings/add[@key='UILogon.Key1']").value
   ```

2. Verify WPF `App.config` uses same value:
   ```xml
   <add key="UILogon.Key" value="[same as server]" />
   ```

3. If keys mismatch, either:
   - Update WPF App.config
   - Regenerate and deploy new keys:
     ```powershell
     .\scripts\Configure-CustomSecurity.ps1
     ```

## "User already exists" / Duplicate User Registration

**Cause**: `RegisterUser` stored procedure doesn't support upserts; inserts fail on duplicate.

**Workaround**: Use `IF NOT EXISTS` (already built into `Setup-Users.ps1`):

```sql
IF EXISTS (SELECT 1 FROM Users WHERE UserName = 'testuser')
    UPDATE Users SET BankNumber = 532 WHERE UserName = 'testuser'
ELSE
    EXEC RegisterUser @userName = 'testuser', @passwordHash = '...', @salt = '...'
```

**To re-register an existing user**:

```powershell
-- Manually delete and re-add
DELETE FROM UserAccounts.dbo.Users WHERE UserName = 'testuser';
.\scripts\Setup-Users.ps1 -CreateTestUsers -Integrated
```

## "Cannot drop database 'UserAccounts' because it is currently in use"

**Cause**: Open connection to database (SQL Server browser, SSMS, or SSRS caching).

**Solution**: Force single-user mode before drop (already in `RestoreDatabase.sql`):

```sql
ALTER DATABASE UserAccounts SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE UserAccounts;
```

If still fails:
1. Kill all SSMS windows
2. Close SQL Server Management Studio
3. Restart SQL Server service
4. Retry drop

## Portal Shows "Access Denied" (HTTP 401)

**Cause**: User authenticated but authorization check failed.

**Check**:

1. User exists:
   ```sql
   SELECT * FROM UserAccounts.dbo.Users WHERE UserName = 'testuser';
   ```

2. User has SSRS role assigned:
   - Portal → Settings → Site Settings → Security
   - Verify user is in a role (e.g., Content Manager)

3. Report permissions:
   - Portal → Manage → Report
   - Set role assignment for user

## Windows Event Log Shows No Auth Entries

**Cause**: Logging not initialized or event source not registered.

**Fix**:

1. Create event source (run as admin):
   ```powershell
   New-EventLog -LogName "Application" -Source "BancPac.ReportingServices.BP360"
   ```

2. Restart SSRS service.

3. Check logs:
   ```powershell
   Get-EventLog -LogName "Application" -Source "BancPac.ReportingServices.BP360" | Select-Object -First 10
   ```

## Report Parameter Tampering (Security)

**Cause**: Client submitting unexpected parameter values.

**Mitigation** (must be in code, not config):

```csharp
// Whitelist allowed values
var allowedReportIds = new[] { 1, 2, 3, 5, 8 };
if (!allowedReportIds.Contains(reportId))
    return HttpStatusCode.Forbidden;

// Validate parameter types
if (!int.TryParse(yearParam, out int year) || year < 2000 || year > 2100)
    return HttpStatusCode.BadRequest;
```

## DLL Not Loading / "Extension not found"

**Cause**: Extension DLL not copied to correct location or version mismatch.

**Check**:

1. DLL exists in both locations:
   - `C:\Program Files\Microsoft SQL Server Reporting Services\SSRS\ReportServer\bin\BancPac.ReportingServices.BP360.dll`
   - `C:\Program Files\Microsoft SQL Server Reporting Services\SSRS\Portal\BancPac.ReportingServices.BP360.dll`

2. DLL version matches rsreportserver.config declaration:
   ```xml
   <Extension Name="CustomAuthentication" Type="BancPac.ReportingServices.BP360.AuthenticationExtension,BancPac.ReportingServices.BP360" />
   ```

3. Code-access security policy allows the DLL:
   - `rssrvpolicy.config` must include FullTrust grant for the DLL path

4. Restart SSRS service after copying new DLL.

## Performance Issues (Slow Login)

**Cause**: Password hashing is CPU-intensive (SHA1 + salt).

**Baseline**: < 1 second per login. If > 5 seconds:

1. Check for SQL network latency:
   ```powershell
   sqlcmd -S localhost -E -Q "SELECT @@VERSION"  -- Should respond in < 100ms
   ```

2. Check SSRS service health:
   ```powershell
   Get-Service SQLServerReportingServices | Select-Object Status
   ```

3. Consider connection pooling improvements in future versions.

## Rollback Failed

**Cause**: Backup files missing or currupted.

**Recovery**:

1. Check backup location:
   ```
   BP360Security/backups/
   ```

2. If no backups, manually restore from version control:
   ```powershell
   git checkout HEAD -- BP360Security/scripts/  # Restore original scripts
   ```

3. Manually restore config files from known-good state:
   ```powershell
   Copy-Item "C:\known-good-rsreportserver.config" "C:\Program Files\Microsoft SQL Server Reporting Services\SSRS\ReportServer\rsreportserver.config" -Force
   ```

4. Restart SSRS service.

## Need More Help?

1. Check Windows Event Log: `Get-EventLog -LogName "Application" -Newest 50`
2. Check SSRS logs: `C:\Program Files\Microsoft SQL Server Reporting Services\SSRS\LogFiles\`
3. Review [CLAUDE.md § Architecture Overview](../CLAUDE.md) data flow diagram
4. Consult [CLAUDE.md § Hard Rules](../CLAUDE.md) non-negotiables checklist
