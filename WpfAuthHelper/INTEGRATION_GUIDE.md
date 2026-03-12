# WPF + SSRS Integration Guide

Two integration modes are available:

| Mode | Class | When to use |
|------|-------|-------------|
| Embedded browser (in-process) | `SsrsAuthHelper` + `SsrsWebView2Window` | Report viewer embedded inside the WPF window |
| External browser launch | `SsrsEdgeLauncher` | Open Edge/default browser with a pre-authenticated SSRS session |

---

## External Browser Launch (`SsrsEdgeLauncher`)

Authenticates the user and opens Edge (or the default browser) already logged in
to SSRS — no WebView2 or cookie injection needed.

### How it works

```
WPF App
  |-- starts HttpListener on http://127.0.0.1:<random-port>/
  |-- launches Edge to that URL
  |
  v
Edge loads trampoline page (served from 127.0.0.1)
  |-- auto-submits hidden form POST → UILogon.aspx?ReturnUrl=/Reports
  |
  v
UILogon.aspx (SSRS server)
  |-- validates UID / PWD / BNBR / KEY
  |-- FormsAuthentication.SetAuthCookie()  ← sets sqlAuthCookie in Edge's cookie store
  |-- 302 redirect → /Reports
  |
  v
Edge navigates to /Reports (already authenticated)
```

The local listener serves exactly one request and then shuts down.

### Usage

```csharp
var launcher = new SsrsEdgeLauncher(
    ssrsBaseUrl : "http://vmlenovo",
    uiLogonPath : "/ReportServer/UILogon.aspx",
    key         : Settings.Default.UILogonKey,  // from protected config
    returnPath  : "/Reports");                  // relative path only

await launcher.LaunchAsync(uid, password, bnbr);
```

**`returnPath`** must be a relative URL (starts with `/`). UILogon.aspx rejects
absolute URLs to prevent open redirects.

**`bnbr`** must be non-empty even when using Key2 (UID-only) — pass `"000"` as a
placeholder if your flow has no bank number.

### No extra NuGet packages required

`SsrsEdgeLauncher` uses only BCL types (`HttpListener`, `Process`, `TcpListener`).
It targets .NET Framework 4.8.

---

## Embedded WebView2 (`SsrsAuthHelper` + `SsrsWebView2Window`)

Replaces the old `WebBrowser` (IE/Trident) control with `WebView2` (Chromium/Edge),
eliminating the need for Edge IE-compatibility mode.

---

## NuGet Packages (WPF project)

| Package | Min Version | Purpose |
|---------|-------------|---------|
| `Microsoft.Web.WebView2` | 1.0.2210.55 | WebView2 WPF control + managed API |

Install via Package Manager Console:
```
Install-Package Microsoft.Web.WebView2
```

### Runtime prerequisite (end-user machines)
WebView2 Runtime must be installed. It ships with Windows 11 and recent
Edge installs, but for guaranteed availability use the Evergreen bootstrapper:
```
https://go.microsoft.com/fwlink/p/?LinkId=2124703
```
Or embed the Fixed Version runtime in your installer (offline deployment).

---

## SSRS Server-Side Config (BP360Security DLL config)

### Key1 vs Key2 — when to use each

UILogon.aspx supports two shared keys that select different authentication flows:

| Key | Auth flow | Username stored in SSRS | When to use |
|-----|-----------|------------------------|-------------|
| `UILogon.Key1` | Full credential check — validates UID + PWD + BNBR against the `UserAccounts` DB | `BNBR-UID` (e.g. `532-testuser`) | WPF desktop client where the user types their password |
| `UILogon.Key2` | Trusted caller — no password check; caller asserts the user is already authenticated | `UID` only (no bank prefix) | Server-side backend that has already authenticated the user through its own mechanism |

UILogon.aspx selects the flow by checking which key value matches the `KEY` field in the POST:
- If `KEY` matches `UILogon.Key1` → run Key1 flow (verify password, prefix username with BNBR)
- If `KEY` matches `UILogon.Key2` → run Key2 flow (skip password, use UID as-is)

**Use Key1 for the WPF test app and production WPF client.** Key2 is for a trusted server process that manages its own auth — do not give Key2 to end-user clients.

### How keys are generated and where to find them

`Configure-CustomSecurity.ps1` (Step 6) auto-generates both keys on first deploy using
a cryptographically random 64-character hex string (32 random bytes):

```powershell
# From Configure-CustomSecurity.ps1 — New-HexString helper
$bytes = New-Object byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
($bytes | ForEach-Object { $_.ToString('X2') }) -join ''   # → 64-char hex
```

Keys are **not overwritten on subsequent deploys** so existing WPF clients keep working.

After each deploy the keys are saved to:
```
BP360Security/backups/MachineKey_<timestamp>.txt
```
Look for the `UILogon keys` section at the bottom of that file.

To read the live key directly from the server:
```powershell
Select-Xml -Path "C:\Program Files\Microsoft SQL Server Reporting Services\SSRS\ReportServer\bin\BancPac.ReportingServices.BP360.dll.config" `
    -XPath '//add[@key="UILogon.Key1"]' | Select-Object -ExpandProperty Node | Select-Object -ExpandProperty value
```

To rotate keys, update `dll.config` on the server and restart SSRS — then update `UILogon.Key` in the WPF `App.config`.

### dll.config entries

```xml
<appSettings>
  <!-- Key1: WPF client flow — validates password, username stored as BNBR-UID -->
  <add key="UILogon.Key1" value="REPLACE_WITH_KEY_FROM_BACKUPS_FOLDER" />
  <!-- Key2: trusted server flow — skips password check, username stored as UID only -->
  <add key="UILogon.Key2" value="REPLACE_WITH_KEY_FROM_BACKUPS_FOLDER" />
</appSettings>
```

---

## WPF App.config

```xml
<appSettings>
  <add key="SSRS.BaseUrl"     value="http://vmlenovo" />
  <add key="SSRS.UILogonPath" value="/ReportServer/UILogon.aspx" />
  <add key="SSRS.ReportUrl"   value="http://vmlenovo/Reports" />

  <!--
    UILogon.Key must match UILogon.Key1 or UILogon.Key2 on the server.
    IMPORTANT: Protect this value. Options:
      - DPAPI-encrypt it with aspnet_setreg or a custom ProtectedData wrapper
      - Read from an environment variable at startup
      - Use .NET user-secrets (development only)
    Never check the plaintext value into source control.
  -->
  <add key="UILogon.Key" value="REPLACE_WITH_KEY_FROM_SERVER_CONFIG" />
</appSettings>
```

---

## Auth Flow Diagram

```
WPF App (HttpClient, AllowAutoRedirect=false)
    |
    | POST UID / PWD / BNBR / KEY
    v
UILogon.aspx (ReportServer virtual dir)
    |-- validates KEY against appSettings
    |     KEY matches Key1 → full flow: VerifyUser() + VerifyPassword(), username = BNBR-UID
    |     KEY matches Key2 → trusted flow: skip password, username = UID only
    |-- FormsAuthentication.SetAuthCookie()
    |
    | HTTP 200 + Set-Cookie: sqlAuthCookie=<ticket>
    v
SsrsAuthHelper (WPF)
    |-- extracts sqlAuthCookie from CookieContainer
    |-- WebView2.CoreWebView2.CookieManager.AddOrUpdateCookie()
    |
    v
WebView2.Navigate(reportUrl)
    --> renders SSRS 2019 portal with valid auth cookie
```

---

## Minimal Integration (existing WPF window)

If you want to add WebView2 to an existing window rather than using
`SsrsWebView2Window`, the minimum required code is:

```csharp
// 1. Add WebView2 to your XAML:
//    xmlns:wv2="clr-namespace:Microsoft.Web.WebView2.Wpf;assembly=Microsoft.Web.WebView2.Wpf"
//    <wv2:WebView2 x:Name="WebView" />

// 2. In your code-behind:
var auth = new SsrsAuthHelper(
    ssrsBaseUrl : "http://vmlenovo",
    uiLogonPath : "/ReportServer/UILogon.aspx",
    key         : Settings.Default.UILogonKey);  // from protected config

bool ok = await auth.LoginAsync(WebView, uid, password, bnbr);
if (ok)
    WebView.CoreWebView2.Navigate("http://vmlenovo/Reports");
else
    MessageBox.Show("Invalid credentials.");
```

---

## UILogon.aspx POST fields

| Field | Description |
|-------|-------------|
| `UID`  | User ID |
| `PWD`  | Password |
| `BNBR` | Bank number (blank string if using Key2 / UID-only format) |
| `KEY`  | Shared secret matching UILogon.Key1 or UILogon.Key2 |

**Response codes:**

| Code | Meaning |
|------|---------|
| 200  | Success -- `sqlAuthCookie` set in response |
| 401  | Invalid credentials or invalid KEY |

---

## Security Notes

- UILogon keys should be at least 40 characters with mixed symbols.
- Rotate keys by updating both the server `appSettings` and the WPF config, then restart SSRS.
- The WPF app should never log `PWD` or `KEY` values.
- If HTTPS is available, the `sqlAuthCookie` will be marked `Secure` automatically by `SsrsAuthHelper`.
