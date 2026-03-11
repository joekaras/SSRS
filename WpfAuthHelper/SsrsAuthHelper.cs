// SsrsAuthHelper.cs
// Reference implementation for authenticating a WPF app against the
// BP360 SSRS custom security extension via UILogon.aspx.
//
// NuGet packages required in the WPF project:
//   Microsoft.Web.WebView2          >= 1.0.2210   (WebView2 WPF control + runtime)
//   Microsoft.Web.WebView2.DevTools  (optional -- for DevTools in debug builds)
//
// .NET target: .NET Framework 4.8 or .NET 6+ (both supported by WebView2)
//
// -------------------------------------------------------------------------
// USAGE SUMMARY
// -------------------------------------------------------------------------
//   var helper = new SsrsAuthHelper(
//       ssrsBaseUrl : "http://vmlenovo/ReportServer",
//       uiLogonPath : "/logon.aspx",             // logon.aspx hosts the UILogon API (loginUrl = always reachable)
//       key         : "YOUR_KEY_FROM_CONFIG");   // UILogon.Key1 or Key2
//
//   await helper.LoginAsync(webView, uid, pwd, bnbr);
//   webView.CoreWebView2.Navigate("http://vmlenovo/Reports/report/MyReport");
// -------------------------------------------------------------------------

using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using System.Threading.Tasks;
using Microsoft.Web.WebView2.Wpf;   // Add via NuGet: Microsoft.Web.WebView2

namespace BancPac.WpfClient.Auth
{
    /// <summary>
    /// Authenticates a user against the BP360 SSRS UILogon endpoint and
    /// injects the resulting Forms Auth cookie into a WebView2 control so
    /// that subsequent report navigations are pre-authorized.
    /// </summary>
    public sealed class SsrsAuthHelper
    {
        private readonly Uri    _ssrsBaseUri;
        private readonly string _uiLogonUrl;
        private readonly string _sharedKey;

        /// <param name="ssrsBaseUrl">
        ///   Base URL of the SSRS server, e.g. "http://vmlenovo".
        ///   Used as the cookie domain when injecting into WebView2.
        /// </param>
        /// <param name="uiLogonPath">
        ///   Absolute path to UILogon.aspx on the ReportServer virtual directory,
        ///   e.g. "/ReportServer/UILogon.aspx".
        /// </param>
        /// <param name="key">
        ///   The shared key value (UILogon.Key1 or UILogon.Key2 from the server
        ///   config).  Keep this in your WPF app's config / secrets store --
        ///   never hard-code it in source.
        /// </param>
        public SsrsAuthHelper(string ssrsBaseUrl, string uiLogonPath, string key)
        {
            _ssrsBaseUri = new Uri(ssrsBaseUrl.TrimEnd('/'));
            _uiLogonUrl  = _ssrsBaseUri + uiLogonPath;
            _sharedKey   = key;
        }

        /// <summary>
        /// Posts credentials to UILogon.aspx, captures the sqlAuthCookie and
        /// injects it into <paramref name="webView"/> via its CookieManager.
        /// </summary>
        /// <param name="webView">The WebView2 control to authenticate.</param>
        /// <param name="uid">User ID (the BancPac UID field).</param>
        /// <param name="password">The user's password ("keyp").</param>
        /// <param name="bnbr">Bank number. Pass empty string if using UILogon.Key2.</param>
        /// <returns>True on success; false if credentials were rejected.</returns>
        /// <exception cref="SsrsAuthException">
        ///   Thrown for network errors or unexpected server responses.
        /// </exception>
        public async Task<bool> LoginAsync(
            WebView2 webView, string uid, string password, string bnbr = "")
        {
            if (webView == null) throw new ArgumentNullException(nameof(webView));

            string cookieValue = await FetchAuthCookieAsync(uid, password, bnbr)
                .ConfigureAwait(false);

            if (cookieValue == null)
                return false;

            await InjectCookieAsync(webView, cookieValue).ConfigureAwait(false);
            return true;
        }

        // ----------------------------------------------------------------
        // Step 1: POST to UILogon.aspx and capture the sqlAuthCookie value.
        // ----------------------------------------------------------------
        private async Task<string> FetchAuthCookieAsync(
            string uid, string password, string bnbr)
        {
            var cookieContainer = new CookieContainer();
            var handler = new HttpClientHandler
            {
                CookieContainer  = cookieContainer,
                AllowAutoRedirect = false,   // Capture the Set-Cookie header before any redirect.
                UseCookies       = true,
            };

            using (var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(30) })
            {
                var fields = new[]
                {
                    new KeyValuePair<string, string>("UID",  uid),
                    new KeyValuePair<string, string>("PWD",  password),
                    new KeyValuePair<string, string>("BNBR", bnbr),
                    new KeyValuePair<string, string>("KEY",  _sharedKey),
                };

                HttpResponseMessage response;
                try
                {
                    response = await client
                        .PostAsync(_uiLogonUrl, new FormUrlEncodedContent(fields))
                        .ConfigureAwait(false);
                }
                catch (Exception ex)
                {
                    throw new SsrsAuthException("Network error contacting UILogon.aspx.", ex);
                }

                // UILogon returns 200 on success, 401 on auth failure.
                if (response.StatusCode == HttpStatusCode.Unauthorized ||
                    response.StatusCode == HttpStatusCode.Forbidden)
                    return null;  // Invalid credentials -- caller shows error.

                if (!response.IsSuccessStatusCode &&
                    response.StatusCode != HttpStatusCode.Found &&      // 302
                    response.StatusCode != HttpStatusCode.Moved)        // 301
                {
                    string body = await response.Content.ReadAsStringAsync()
                        .ConfigureAwait(false);
                    throw new SsrsAuthException(
                        $"UILogon returned unexpected status {(int)response.StatusCode}: {body}");
                }

                // The cookie is on the SSRS base URI (the ReportServer host).
                Cookie authCookie = cookieContainer
                    .GetCookies(_ssrsBaseUri)["sqlAuthCookie"];

                if (authCookie == null)
                    throw new SsrsAuthException(
                        "sqlAuthCookie not returned by UILogon.aspx. " +
                        "Verify the MachineKey is configured correctly on the server.");

                return authCookie.Value;
            }
        }

        // ----------------------------------------------------------------
        // Step 2: Inject the cookie into the WebView2 CookieManager.
        // ----------------------------------------------------------------
        private async Task InjectCookieAsync(WebView2 webView, string cookieValue)
        {
            // EnsureCoreWebView2Async must be called from the UI thread.
            await webView.EnsureCoreWebView2Async().ConfigureAwait(true);

            var manager = webView.CoreWebView2.CookieManager;

            // Remove any stale auth cookie first.
            manager.DeleteCookiesWithDomainAndPath(
                "sqlAuthCookie", _ssrsBaseUri.Host, "/");

            var cookie = manager.CreateCookie(
                "sqlAuthCookie", cookieValue, _ssrsBaseUri.Host, "/");

            cookie.IsHttpOnly = true;
            // Set Secure = true when the server uses HTTPS.
            cookie.IsSecure = _ssrsBaseUri.Scheme.Equals(
                "https", StringComparison.OrdinalIgnoreCase);

            manager.AddOrUpdateCookie(cookie);
        }
    }

    /// <summary>
    /// Raised when SSRS authentication fails for a reason other than
    /// invalid credentials (which returns <c>false</c> from LoginAsync).
    /// </summary>
    public sealed class SsrsAuthException : Exception
    {
        public SsrsAuthException(string message) : base(message) { }
        public SsrsAuthException(string message, Exception inner) : base(message, inner) { }
    }
}
