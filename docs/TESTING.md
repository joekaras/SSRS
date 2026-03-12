# Testing & Validation

Complete test strategy, smoke tests, and definition of done.

## Test Strategy

### Levels

1. **Unit**: C# code (hashing, validation logic)
2. **Integration**: Extension + SSRS + SQL Server
3. **System**: Full auth flow (browser, WPF, portal)
4. **Smoke**: Quick sanity checks (10 min)

### Test Environments

- **Local**: Developer machine, localhost SSRS
- **VMLENOVO**: Shared test server, production-like config
- **VWMAZBPTESTBP360**: QA server, multi-user testing

## Smoke Tests

Run these quickly after deploy to verify basics:

### 1. Endpoint Connectivity

```powershell
.\scripts\Test-SSRSEndpoints.ps1
```

Checks:
- ReportServer responds on port 80
- Portal responds on port 80
- sqlcmd can reach localhost

### 2. Browser Login

```powershell
.\scripts\SmokeTest-Logon.ps1
```

Manual:
1. Open `http://[host]/ReportServer/logon.aspx`
2. Enter: UID=`testuser`, PWD=`Test@123`
3. Click **Logon**
4. Should redirect to `http://[host]/Reports` (portal home)
5. Check browser console for any JavaScript errors

### 3. UILogon API (WPF Test)

```powershell
.\scripts\Test-UILogon.ps1 -UID testuser -PWD Test@123 -BNBR 532
```

Expected output:
```
SSRS UILogon Endpoint Test
========================
Endpoint: http://localhost/ReportServer/UILogon.aspx
Request: UID=testuser, PWD=***, BNBR=532, KEY=***
Result: PASS — sqlAuthCookie returned
```

### 4. Forms Auth Cookie Decryption

```powershell
.\scripts\Test-FormsAuth.ps1
```

Checks:
- Cookie can be encrypted by web.config MachineKey
- Cookie can be decrypted by RSPortal.exe.config MachineKey
- If mismatch: logs "Unable to validate data"

### 5. User Login

```powershell
.\scripts\Test-Login.ps1 -UID testuser -PWD Test@123
```

Checks:
- User exists in `UserAccounts.Users`
- Password hash matches (SHA1 + salt)
- Event log entries created

## Definition of Done

Feature is complete when:

1. **Code**
   - [ ] Compiles without warnings (C#)
   - [ ] No hardcoded secrets
   - [ ] Error handling present (try/catch)

2. **Configuration**
   - [ ] All three config files have identical MachineKey
   - [ ] `UILogon.Key1` and `UILogon.Key2` are strong random hex
   - [ ] Database connection string is correct
   - [ ] Service account has SQL permissions

3. **Testing**
   - [ ] All 5 smoke tests pass
   - [ ] Browser login works
   - [ ] UILogon endpoint works
   - [ ] WPF integration works (if applicable)
   - [ ] Windows Event Log shows auth entries

4. **Documentation**
   - [ ] Code comments updated
   - [ ] README/CLAUDE.md reflect new/changed behavior
   - [ ] New scripts added to Scripts table in CLAUDE.md

5. **Security**
   - [ ] Follows all Non-Negotiables (see [CLAUDE.md § Hard Rules](../CLAUDE.md))
   - [ ] No SQL injection vectors
   - [ ] No timing attacks on key comparison
   - [ ] Audit logging in place

## Test Cases

### Authentication

| Scenario | Input | Expected | Status |
|----------|-------|----------|--------|
| Valid credentials | UID=`testuser`, PWD=`Test@123` | HTTP 200 + cookie | |
| Invalid UID | UID=`baduser`, PWD=`Test@123` | HTTP 401 | |
| Invalid PWD | UID=`testuser`, PWD=`wrong` | HTTP 401 | |
| Missing UID | UID=`""`, PWD=`Test@123` | HTTP 400 | |
| Missing PWD | UID=`testuser`, PWD=`""` | HTTP 400 | |
| SQL injection attempt | UID=`' OR '1'='1`, PWD=`test` | HTTP 401 (safe) | |

### UILogon Key Validation

| Scenario | KEY | Expected |
|----------|-----|----------|
| Valid Key1 | `[UILogon.Key1 value]` | HTTP 200, username=`BNBR-UID` |
| Valid Key2 | `[UILogon.Key2 value]` | HTTP 200, username=`UID` |
| Invalid KEY | `wrongkey` | HTTP 401 |
| Missing KEY | `""` | HTTP 400 |

### Authorization

| User | Report | Expected |
|------|--------|----------|
| testuser | public_report | HTTP 200 (render) |
| testuser | admin_report | HTTP 401 (denied) |
| admin | admin_report | HTTP 200 (render) |

## Regression Test Checklist

Before each release, verify:

- [ ] Browser login still works
- [ ] UILogon endpoint still works
- [ ] Report rendering works (past reports still accessible)
- [ ] User registration works (Setup-Users.ps1)
- [ ] Rollback works (Rollback-CustomSecurity.ps1)
- [ ] Multiple user accounts don't interfere
- [ ] Service restart clears cache correctly

## Performance Baselines

Document expected performance:

|Operation | Expected | Notes |
|----------|----------|-------|
| Password hash (SHA1 + 6-byte salt) | < 1ms | Per login attempt |
| LookupUser stored proc | < 50ms | SQL query |
| Browser login (end-to-end) | < 2 sec | Includes redirect + portal load |
| UILogon.aspx (no rendering) | < 100ms | Just auth, returns JSON |
| Report render (simple report) | 5-30 sec | SSRS is slow; set timeout=60 |

## Monitoring & Alerts

Post-deploy, monitor:

1. **Windows Event Log**: Authentication failures (should be rare)
2. **SSRS Log Files**: `/Reporting Services/LogFiles/`
3. **SQL Server Logs**: Connection errors to UserAccounts DB
4. **Application Monitoring**: Response time, error rate trends

Alert on:
- Repeated (3+) failed login attempts from same IP
- MachineKey validation errors (HTTP 500)
- Database connection timeouts
- Service crash
