using System;
using System.Configuration;
using System.Windows;
using System.Windows.Controls;
using BancPac.WpfClient.Auth;
using Microsoft.Web.WebView2.Core;   // Add via NuGet: Microsoft.Web.WebView2

namespace BancPac.WpfClient
{
    /// <summary>
    /// Sample WPF window that replaces the old WebBrowser (IE) control with
    /// WebView2 (Chromium/Edge) and authenticates via UILogon.aspx.
    ///
    /// Configuration keys expected in App.config appSettings:
    ///   SSRS.BaseUrl        http://vmlenovo
    ///   SSRS.UILogonPath    /ReportServer/UILogon.aspx
    ///   SSRS.ReportUrl      http://vmlenovo/Reports/report/MyReport
    ///   UILogon.Key         (the shared key value -- UILogon.Key1 or Key2)
    ///
    /// Keep UILogon.Key in a secrets store (DPAPI-protected config, environment
    /// variable, or user-secrets) rather than plain text in source control.
    /// </summary>
    public partial class SsrsWebView2Window : Window
    {
        private readonly SsrsAuthHelper _auth;
        private readonly string         _reportUrl;

        public SsrsWebView2Window()
        {
            InitializeComponent();

            string baseUrl    = ConfigurationManager.AppSettings["SSRS.BaseUrl"]     ?? "http://localhost";
            string logonPath  = ConfigurationManager.AppSettings["SSRS.UILogonPath"] ?? "/ReportServer/UILogon.aspx";
            string key        = ConfigurationManager.AppSettings["UILogon.Key"]      ?? string.Empty;
            _reportUrl        = ConfigurationManager.AppSettings["SSRS.ReportUrl"]   ?? baseUrl + "/Reports";

            _auth = new SsrsAuthHelper(baseUrl, logonPath, key);

            // Initialize WebView2 asynchronously on load.
            Loaded += Window_Loaded;
        }

        private async void Window_Loaded(object sender, RoutedEventArgs e)
        {
            // Initialize the WebView2 environment before first use.
            await WebView.EnsureCoreWebView2Async();
            WebView.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
        }

        private async void BtnLogin_Click(object sender, RoutedEventArgs e)
        {
            TxtError.Text   = string.Empty;
            BtnLogin.IsEnabled = false;
            LoadingOverlay.Visibility = Visibility.Visible;

            try
            {
                bool ok = await _auth.LoginAsync(
                    webView  : WebView,
                    uid      : TxtUid.Text.Trim(),
                    password : TxtPwd.Password,
                    bnbr     : TxtBnbr.Text.Trim());

                if (!ok)
                {
                    TxtError.Text = "Invalid credentials. Please try again.";
                    return;
                }

                // Auth succeeded - hide login panel, show WebView, navigate.
                LoginPanel.Visibility     = Visibility.Collapsed;
                LoadingOverlay.Visibility = Visibility.Collapsed;
                WebView.Visibility        = Visibility.Visible;
                WebView.CoreWebView2.Navigate(_reportUrl);
            }
            catch (SsrsAuthException ex)
            {
                TxtError.Text = $"Login error: {ex.Message}";
            }
            catch (Exception ex)
            {
                TxtError.Text = $"Unexpected error: {ex.Message}";
            }
            finally
            {
                BtnLogin.IsEnabled        = true;
                LoadingOverlay.Visibility = Visibility.Collapsed;
            }
        }

        private void WebView_NavigationCompleted(
            object sender, CoreWebView2NavigationCompletedEventArgs e)
        {
            if (!e.IsSuccess)
            {
                // Navigation failed - may indicate session expired.
                // Show login panel again so the user can re-authenticate.
                WebView.Visibility    = Visibility.Collapsed;
                LoginPanel.Visibility = Visibility.Visible;
                TxtError.Text         = "Session expired or navigation failed. Please log in again.";
            }
        }
    }
}
