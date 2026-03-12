// SsrsEdgeLauncher.cs
// Launches Edge (or the system default browser) with a pre-authenticated
// SSRS session using a one-shot local trampoline page.
//
// Flow:
//   1. WPF calls LaunchAsync(uid, pwd, bnbr).
//   2. A local HttpListener starts on 127.0.0.1:<random-port>.
//   3. Edge is launched to http://127.0.0.1:<port>/.
//   4. Edge loads an HTML page that auto-POSTs credentials directly to
//      UILogon.aspx?ReturnUrl=<returnPath> on the SSRS server.
//   5. UILogon.aspx validates credentials, calls FormsAuthentication.SetAuthCookie()
//      which sets sqlAuthCookie in Edge's cookie store for the SSRS domain,
//      then redirects Edge to returnPath.
//   6. The local listener served one request and shuts down.
//
// Security note: credentials live in HTML served only on 127.0.0.1 for a
// single request.  The listener stops immediately after serving it.
// This is acceptable for an internal desktop app; use HTTPS for SSRS if
// the network is untrusted.
//
// .NET target: .NET Framework 4.8 (no extra NuGet packages required).
// -------------------------------------------------------------------------
// USAGE SUMMARY
// -------------------------------------------------------------------------
//   var launcher = new SsrsEdgeLauncher(
//       ssrsBaseUrl  : "http://vmlenovo",
//       uiLogonPath  : "/ReportServer/UILogon.aspx",
//       key          : Settings.Default.UILogonKey,  // from protected config
//       returnPath   : "/Reports");                  // relative path only
//
//   await launcher.LaunchAsync(uid, password, bnbr);
// -------------------------------------------------------------------------

using System;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace BancPac.WpfClient.Auth
{
    /// <summary>
    /// Launches Edge (or the default system browser) with a pre-authenticated
    /// SSRS session.  The browser performs the UILogon POST directly, so SSRS
    /// sets the <c>sqlAuthCookie</c> in the browser's own cookie store.
    /// No WebView2 or cookie injection is required.
    /// </summary>
    public sealed class SsrsEdgeLauncher
    {
        private readonly string _uiLogonBaseUrl;  // e.g. "http://vmlenovo/ReportServer/UILogon.aspx"
        private readonly string _sharedKey;
        private readonly string _returnPath;      // e.g. "/Reports"

        /// <param name="ssrsBaseUrl">
        ///   SSRS server root, e.g. "http://vmlenovo".
        /// </param>
        /// <param name="uiLogonPath">
        ///   Path to UILogon.aspx on the ReportServer virtual directory,
        ///   e.g. "/ReportServer/UILogon.aspx".
        /// </param>
        /// <param name="key">
        ///   Shared secret matching UILogon.Key1 or UILogon.Key2 on the server.
        ///   Keep this in your app's protected config — never hard-code it.
        /// </param>
        /// <param name="returnPath">
        ///   Relative path the browser navigates to after login, e.g. "/Reports"
        ///   or "/Reports/report/MyReport".  Must be a relative path (starts with '/').
        ///   UILogon.aspx rejects absolute URLs to prevent open redirects.
        /// </param>
        public SsrsEdgeLauncher(
            string ssrsBaseUrl,
            string uiLogonPath,
            string key,
            string returnPath = "/Reports")
        {
            string baseUrl   = ssrsBaseUrl.TrimEnd('/');
            _uiLogonBaseUrl  = baseUrl + uiLogonPath;
            _sharedKey       = key;
            _returnPath      = returnPath.StartsWith("/") ? returnPath : "/" + returnPath;
        }

        /// <summary>
        /// Starts a local HTTP listener, launches Edge (or default browser) to it,
        /// serves the one-shot trampoline page, then stops the listener.
        /// Returns once the page has been served; the browser continues on its own.
        /// </summary>
        /// <param name="uid">User ID.</param>
        /// <param name="password">User's password.</param>
        /// <param name="bnbr">
        ///   Bank number.  UILogon.aspx requires a non-empty value even when using
        ///   Key2 (UID-only format) — pass a placeholder such as "000" if not applicable.
        /// </param>
        /// <param name="ct">Optional cancellation token.</param>
        /// <exception cref="SsrsAuthException">
        ///   Thrown if the browser does not connect within 30 seconds, or if
        ///   the listener cannot start.
        /// </exception>
        public async Task LaunchAsync(
            string uid,
            string password,
            string bnbr = "",
            CancellationToken ct = default)
        {
            int port = GetFreePort();
            string localUrl = string.Format("http://127.0.0.1:{0}/", port);

            var listener = new HttpListener();
            try
            {
                listener.Prefixes.Add(localUrl);
                listener.Start();
            }
            catch (Exception ex)
            {
                throw new SsrsAuthException("Failed to start local HTTP listener.", ex);
            }

            try
            {
                LaunchBrowser(localUrl);

                // Wait up to 30 s for the browser's GET request.
                using (var linked = CancellationTokenSource.CreateLinkedTokenSource(ct))
                {
                    linked.CancelAfter(TimeSpan.FromSeconds(30));

                    HttpListenerContext ctx;
                    try
                    {
                        ctx = await GetContextAsync(listener, linked.Token)
                            .ConfigureAwait(false);
                    }
                    catch (OperationCanceledException)
                    {
                        // Browser didn't connect in time — silently give up.
                        return;
                    }
                    catch (HttpListenerException ex)
                    {
                        throw new SsrsAuthException("Local listener error.", ex);
                    }

                    byte[] bytes = Encoding.UTF8.GetBytes(
                        BuildTrampolinePage(uid, password, bnbr));

                    ctx.Response.ContentType     = "text/html; charset=utf-8";
                    ctx.Response.ContentLength64 = bytes.Length;
                    ctx.Response.Headers.Add("Cache-Control", "no-store");
                    ctx.Response.Headers.Add("Pragma",        "no-cache");

                    try
                    {
                        await ctx.Response.OutputStream
                            .WriteAsync(bytes, 0, bytes.Length, linked.Token)
                            .ConfigureAwait(false);
                    }
                    finally
                    {
                        ctx.Response.Close();
                    }
                }
            }
            finally
            {
                listener.Stop();
            }
        }

        // ----------------------------------------------------------------
        // Build the auto-submit trampoline page.
        // ----------------------------------------------------------------
        private string BuildTrampolinePage(string uid, string password, string bnbr)
        {
            // UILogon.aspx requires BNBR to be non-empty even for Key2 flows.
            string effectiveBnbr = string.IsNullOrEmpty(bnbr) ? "000" : bnbr;

            // ReturnUrl must be a relative path; UILogon.aspx validates it with IsLocalUrl.
            string action = HtmlEncode(
                _uiLogonBaseUrl + "?ReturnUrl=" + Uri.EscapeDataString(_returnPath));

            return string.Format(@"<!DOCTYPE html>
<html>
<head>
  <meta charset=""utf-8"">
  <title>Connecting to Reporting Services</title>
  <style>
    body {{ font-family: sans-serif; display: flex; align-items: center;
           justify-content: center; height: 100vh; margin: 0; background: #f0f4f8 }}
    p    {{ color: #555; font-size: 1.1rem }}
  </style>
</head>
<body>
  <p>Connecting to reporting services&hellip;</p>
  <form id=""f"" method=""POST"" action=""{0}"">
    <input type=""hidden"" name=""UID""  value=""{1}"">
    <input type=""hidden"" name=""PWD""  value=""{2}"">
    <input type=""hidden"" name=""BNBR"" value=""{3}"">
    <input type=""hidden"" name=""KEY""  value=""{4}"">
  </form>
  <script>document.getElementById('f').submit();</script>
</body>
</html>",
                action,
                HtmlEncode(uid),
                HtmlEncode(password),
                HtmlEncode(effectiveBnbr),
                HtmlEncode(_sharedKey));
        }

        // ----------------------------------------------------------------
        // Launch Edge; fall back to the OS default browser.
        // ----------------------------------------------------------------
        private static void LaunchBrowser(string url)
        {
            try
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName        = "msedge",
                    Arguments       = url,
                    UseShellExecute = true,
                });
                return;
            }
            catch (Exception) { /* Edge not in PATH — try default browser */ }

            // ShellExecute with a URL opens the default browser on Windows.
            Process.Start(new ProcessStartInfo
            {
                FileName        = url,
                UseShellExecute = true,
            });
        }

        // ----------------------------------------------------------------
        // HttpListener.GetContextAsync() has no CancellationToken overload
        // in .NET Framework 4.8; wrap BeginGetContext to honour one.
        // ----------------------------------------------------------------
        private static Task<HttpListenerContext> GetContextAsync(
            HttpListener listener, CancellationToken ct)
        {
            var tcs = new TaskCompletionSource<HttpListenerContext>(
                TaskCreationOptions.RunContinuationsAsynchronously);

            var reg = ct.Register(() =>
            {
                tcs.TrySetCanceled();
                try { listener.Stop(); } catch { /* listener may already be stopped */ }
            });

            listener.BeginGetContext(ar =>
            {
                reg.Dispose();
                try   { tcs.TrySetResult(listener.EndGetContext(ar)); }
                catch (Exception ex) { tcs.TrySetException(ex); }
            }, null);

            return tcs.Task;
        }

        // ----------------------------------------------------------------
        // Find a free local TCP port.
        // ----------------------------------------------------------------
        private static int GetFreePort()
        {
            var tcpListener = new TcpListener(IPAddress.Loopback, 0);
            tcpListener.Start();
            int port = ((IPEndPoint)tcpListener.LocalEndpoint).Port;
            tcpListener.Stop();
            return port;
        }

        private static string HtmlEncode(string s) =>
            WebUtility.HtmlEncode(s ?? string.Empty);
    }
}
