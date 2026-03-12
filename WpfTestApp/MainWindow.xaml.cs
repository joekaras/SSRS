using System;
using System.Collections.Generic;
using System.Configuration;
using System.Net;
using System.Net.Http;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Input;
using BancPac.WpfClient.Auth;
using Microsoft.Web.WebView2.Core;

namespace WpfTestApp
{
    public partial class MainWindow : Window
    {
        // Captured after a successful Step 1 POST.
        private string _capturedCookieValue;

        public MainWindow()
        {
            InitializeComponent();
            Loaded += Window_Loaded;
        }

        // ----------------------------------------------------------------
        // Startup
        // ----------------------------------------------------------------
        private async void Window_Loaded(object sender, RoutedEventArgs e)
        {
            // Pre-fill fields from App.config appSettings.
            var cfg = ConfigurationManager.AppSettings;
            if (!string.IsNullOrEmpty(cfg["SSRS.BaseUrl"]))     TxtBaseUrl.Text      = cfg["SSRS.BaseUrl"];
            if (!string.IsNullOrEmpty(cfg["SSRS.UILogonPath"])) TxtUILogonPath.Text  = cfg["SSRS.UILogonPath"];
            if (!string.IsNullOrEmpty(cfg["SSRS.ReportUrl"]))   TxtReportUrl.Text    = cfg["SSRS.ReportUrl"];
            if (!string.IsNullOrEmpty(cfg["SSRS.UID"]))         TxtUid.Text          = cfg["SSRS.UID"];
            if (!string.IsNullOrEmpty(cfg["SSRS.BNBR"]))        TxtBnbr.Text         = cfg["SSRS.BNBR"];
            if (!string.IsNullOrEmpty(cfg["UILogon.Key"]))      TxtKey.Password       = cfg["UILogon.Key"];
            if (!string.IsNullOrEmpty(cfg["SSRS.PWD"]))         TxtPwd.Password       = cfg["SSRS.PWD"];

            Log("Initializing WebView2...");
            try
            {
                await WebView.EnsureCoreWebView2Async();
                WebView.CoreWebView2.Settings.AreDefaultContextMenusEnabled = true;
                WebView.CoreWebView2.Settings.AreDevToolsEnabled            = true;
                Log("WebView2 ready. Runtime: " +
                    WebView.CoreWebView2.Environment.BrowserVersionString);
            }
            catch (Exception ex)
            {
                Log($"ERROR initializing WebView2: {ex.Message}");
                Log("Is the WebView2 runtime installed on this machine?");
            }
        }

        // ----------------------------------------------------------------
        // Step 1 — POST to UILogon.aspx via HttpClient only (no WebView2)
        // ----------------------------------------------------------------
        private async void BtnStep1_Click(object sender, RoutedEventArgs e)
        {
            await RunStep1();
        }

        private async Task<bool> RunStep1()
        {
            _capturedCookieValue = null;
            BtnStep2.IsEnabled   = false;
            SetStatus("Posting credentials to UILogon.aspx...", "#1565C0");

            string baseUrl    = TxtBaseUrl.Text.TrimEnd('/');
            string logonPath  = TxtUILogonPath.Text;
            string uid        = TxtUid.Text.Trim();
            string pwd        = TxtPwd.Password;
            string bnbr       = TxtBnbr.Text.Trim();
            string key        = TxtKey.Password;
            string uiLogonUrl = baseUrl + logonPath;

            Log($"--- Step 1: POST to {uiLogonUrl}");
            Log($"    UID={uid}  BNBR={bnbr}  KEY={(string.IsNullOrEmpty(key) ? "<empty>" : new string('*', key.Length))}");

            var cookieContainer = new CookieContainer();
            var handler = new HttpClientHandler
            {
                CookieContainer   = cookieContainer,
                AllowAutoRedirect = false,
                UseCookies        = true,
            };

            try
            {
                using (var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(30) })
                {
                    var fields = new[]
                    {
                        new KeyValuePair<string,string>("UID",  uid),
                        new KeyValuePair<string,string>("PWD",  pwd),
                        new KeyValuePair<string,string>("BNBR", bnbr),
                        new KeyValuePair<string,string>("KEY",  key),
                    };

                    var response = await client.PostAsync(
                        uiLogonUrl, new FormUrlEncodedContent(fields));

                    string body = await response.Content.ReadAsStringAsync();
                    Log($"    Response: HTTP {(int)response.StatusCode} {response.StatusCode}");
                    Log($"    Body: {body.Trim()}");

                    // Log all Set-Cookie headers for diagnostics.
                    if (response.Headers.TryGetValues("Set-Cookie", out var setCookies))
                        foreach (var sc in setCookies)
                            Log($"    Set-Cookie: {sc}");

                    // Look for sqlAuthCookie in the CookieContainer.
                    var ssrsUri    = new Uri(baseUrl);
                    var cookies    = cookieContainer.GetCookies(ssrsUri);
                    var authCookie = cookies["sqlAuthCookie"];

                    if (authCookie != null)
                    {
                        _capturedCookieValue = authCookie.Value;
                        int len = _capturedCookieValue.Length;
                        Log($"    sqlAuthCookie captured ({len} chars): " +
                            _capturedCookieValue.Substring(0, Math.Min(40, len)) + "...");
                        TxtCookieState.Text       = $"Captured ({len} chars)";
                        TxtCookieState.Foreground = System.Windows.Media.Brushes.Green;
                        BtnStep2.IsEnabled        = true;
                        SetStatus("Step 1 succeeded — cookie captured. Run Step 2 to load WebView2.", "#2E7D32");
                        return true;
                    }
                    else
                    {
                        Log("    sqlAuthCookie NOT found in response.");
                        Log("    Check: UILogon.Key1/Key2 configured in dll.config? Credentials correct?");
                        TxtCookieState.Text       = "Not captured";
                        TxtCookieState.Foreground = System.Windows.Media.Brushes.Red;
                        SetStatus($"Step 1 failed — HTTP {(int)response.StatusCode}. See log.", "#C62828");
                        return false;
                    }
                }
            }
            catch (Exception ex)
            {
                Log($"    EXCEPTION: {ex.GetType().Name}: {ex.Message}");
                SetStatus("Step 1 failed — network error. See log.", "#C62828");
                return false;
            }
        }

        // ----------------------------------------------------------------
        // Step 2 — inject captured cookie into WebView2, then navigate
        // ----------------------------------------------------------------
        private async void BtnStep2_Click(object sender, RoutedEventArgs e)
        {
            await RunStep2();
        }

        private async Task<bool> RunStep2()
        {
            if (string.IsNullOrEmpty(_capturedCookieValue))
            {
                Log("Step 2: no cookie to inject — run Step 1 first.");
                return false;
            }

            string baseUrl    = TxtBaseUrl.Text.TrimEnd('/');
            string reportUrl  = TxtReportUrl.Text;
            var    ssrsUri    = new Uri(baseUrl);

            Log($"--- Step 2: Inject cookie into WebView2, navigate to {reportUrl}");

            try
            {
                await WebView.EnsureCoreWebView2Async();
                var manager = WebView.CoreWebView2.CookieManager;

                // Remove stale auth cookies first.
                manager.DeleteCookiesWithDomainAndPath("sqlAuthCookie", ssrsUri.Host, "/");

                var cookie    = manager.CreateCookie("sqlAuthCookie", _capturedCookieValue, ssrsUri.Host, "/");
                cookie.IsHttpOnly = true;
                cookie.IsSecure   = ssrsUri.Scheme.Equals("https", StringComparison.OrdinalIgnoreCase);

                manager.AddOrUpdateCookie(cookie);
                Log($"    Cookie injected: domain={ssrsUri.Host} path=/ httpOnly=true secure={cookie.IsSecure}");

                WebView.CoreWebView2.Navigate(reportUrl);
                TxtAddress.Text = reportUrl;
                SetStatus("Step 2: navigating WebView2 with injected cookie...", "#1565C0");
                return true;
            }
            catch (Exception ex)
            {
                Log($"    EXCEPTION: {ex.GetType().Name}: {ex.Message}");
                SetStatus("Step 2 failed. See log.", "#C62828");
                return false;
            }
        }

        // ----------------------------------------------------------------
        // Full flow — Step 1 then Step 2
        // ----------------------------------------------------------------
        private async void BtnFullFlow_Click(object sender, RoutedEventArgs e)
        {
            Log("=== Full Flow Start ===");
            bool ok = await RunStep1();
            if (ok) await RunStep2();
            Log("=== Full Flow End ===");
        }

        // ----------------------------------------------------------------
        // Launch browser (Edge/default) with pre-authenticated SSRS session
        // ----------------------------------------------------------------
        private async void BtnLaunchBrowser_Click(object sender, RoutedEventArgs e)
        {
            string baseUrl   = TxtBaseUrl.Text.TrimEnd('/');
            string logonPath = TxtUILogonPath.Text;
            string uid       = TxtUid.Text.Trim();
            string pwd       = TxtPwd.Password;
            string bnbr      = TxtBnbr.Text.Trim();
            string key       = TxtKey.Password;
            string returnPath = new Uri(TxtReportUrl.Text).AbsolutePath;

            Log($"--- Launch Browser: trampoline → UILogon.aspx → {returnPath}");

            var launcher = new SsrsEdgeLauncher(baseUrl, logonPath, key, returnPath);
            try
            {
                SetStatus("Launching browser with pre-authenticated session...", "#1565C0");
                await launcher.LaunchAsync(uid, pwd, bnbr);
                Log("    Trampoline page served — browser continuing on its own.");
                SetStatus("Browser launched. Check Edge/default browser.", "#2E7D32");
            }
            catch (Exception ex)
            {
                Log($"    EXCEPTION: {ex.GetType().Name}: {ex.Message}");
                SetStatus("Browser launch failed. See log.", "#C62828");
            }
        }

        // ----------------------------------------------------------------
        // Navigate WebView2 directly WITHOUT auth (should redirect to logon.aspx)
        // ----------------------------------------------------------------
        private void BtnNavigateDirect_Click(object sender, RoutedEventArgs e)
        {
            string url = TxtReportUrl.Text;
            Log($"--- Direct navigate (no auth): {url}");
            Log("    Expect: redirect to logon.aspx (Forms Auth challenge)");
            WebView.CoreWebView2?.Navigate(url);
            TxtAddress.Text = url;
            SetStatus("Navigating without auth cookie — expect logon.aspx redirect.", "#E65100");
        }

        // ----------------------------------------------------------------
        // Clear all WebView2 cookies for the SSRS domain
        // ----------------------------------------------------------------
        private async void BtnClearCookies_Click(object sender, RoutedEventArgs e)
        {
            await WebView.EnsureCoreWebView2Async();

            string host = TxtBaseUrl.Text.TrimEnd('/');
            WebView.CoreWebView2.CookieManager.DeleteAllCookies();

            _capturedCookieValue      = null;
            BtnStep2.IsEnabled        = false;
            TxtCookieState.Text       = "Cleared";
            TxtCookieState.Foreground = System.Windows.Media.Brushes.Gray;

            Log($"--- All WebView2 cookies cleared.");
            SetStatus("Cookies cleared.", "#555");
        }

        private void BtnClearLog_Click(object sender, RoutedEventArgs e)
        {
            TxtLog.Text = string.Empty;
        }

        // ----------------------------------------------------------------
        // Address bar navigation
        // ----------------------------------------------------------------
        private void BtnGo_Click(object sender, RoutedEventArgs e) => NavigateToAddress();

        private void TxtAddress_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Enter) NavigateToAddress();
        }

        private void NavigateToAddress()
        {
            string url = TxtAddress.Text.Trim();
            if (!string.IsNullOrEmpty(url))
            {
                if (!url.StartsWith("http")) url = "http://" + url;
                WebView.CoreWebView2?.Navigate(url);
            }
        }

        // ----------------------------------------------------------------
        // WebView2 events
        // ----------------------------------------------------------------
        private void WebView_NavigationStarting(object sender, CoreWebView2NavigationStartingEventArgs e)
        {
            TxtAddress.Text = e.Uri;
            Log($"    WebView2 → {e.Uri}");
        }

        private void WebView_NavigationCompleted(object sender, CoreWebView2NavigationCompletedEventArgs e)
        {
            string url = WebView.Source?.ToString() ?? "";

            if (e.IsSuccess)
            {
                // Check if we ended up on logon.aspx — means the cookie wasn't accepted.
                if (url.IndexOf("logon.aspx", StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    Log("    ⚠  Redirected to logon.aspx — cookie not accepted or expired.");
                    SetStatus("Redirected to logon.aspx. Re-run Step 1.", "#E65100");
                }
                else
                {
                    Log($"    ✓ Navigation succeeded: {url}");
                    SetStatus("Navigation succeeded.", "#2E7D32");
                }
            }
            else
            {
                Log($"    ✗ Navigation failed (error {e.WebErrorStatus}): {url}");
                SetStatus($"Navigation failed: {e.WebErrorStatus}", "#C62828");
            }
        }

        private void WebView_SourceChanged(object sender, CoreWebView2SourceChangedEventArgs e)
        {
            TxtAddress.Text = WebView.Source?.ToString() ?? "";
        }

        // ----------------------------------------------------------------
        // Helpers
        // ----------------------------------------------------------------
        private void Log(string message)
        {
            string line = $"[{DateTime.Now:HH:mm:ss.fff}] {message}\n";
            TxtLog.Text += line;
            // Auto-scroll to bottom.
            LogScroller.ScrollToEnd();
        }

        private void SetStatus(string message, string hexColor)
        {
            TxtStatus.Text       = message;
            TxtStatus.Foreground = (System.Windows.Media.Brush)
                new System.Windows.Media.BrushConverter().ConvertFromString(hexColor);
        }
    }
}
