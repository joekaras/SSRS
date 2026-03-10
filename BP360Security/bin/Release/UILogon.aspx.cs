using System;
using System.Configuration;
using System.Globalization;
using System.Web;
using System.Web.Security;
using System.Web.UI;
using System.Web.UI.WebControls;
using BancPac.ReportingServices.BP360.Logging;

namespace BancPac.ReportingServices.BP360
{
    /// <summary>
    /// Server-to-server logon endpoint for the BancPac 360 WPF client.
    ///
    /// The WPF client POSTs four fields:
    ///   UID  - user ID
    ///   PWD  - password (the "keyp")
    ///   BNBR - bank number
    ///   KEY  - shared secret that controls username format
    ///
    /// Two valid KEY values are defined in the DLL config under appSettings:
    ///   UILogon.Key1  => username is formed as "BNBR-UID" (bank-scoped user)
    ///   UILogon.Key2  => username is formed as "UID" only
    ///
    /// On success, a Forms Authentication cookie (sqlAuthCookie) is written to
    /// the HTTP response.  The WPF client captures that cookie (HttpClient with
    /// AllowAutoRedirect=false) and injects it into its WebView2 control before
    /// navigating to the report URL.
    ///
    /// If a ReturnUrl query parameter is present (browser flow), the page
    /// redirects there after issuing the cookie.  Otherwise it returns HTTP 200
    /// so the WPF client can detect success by status code alone.
    /// </summary>
    public class UILogon : Page
    {
        protected Label lblMessage;

        protected override void OnInit(EventArgs e)
        {
            this.Load += Page_Load;
            base.OnInit(e);
        }

        [System.Diagnostics.CodeAnalysis.SuppressMessage(
            "Microsoft.Design", "CA1031:DoNotCatchGeneralExceptionTypes")]
        private void Page_Load(object sender, EventArgs e)
        {
            // Only accept POST requests.
            if (!Request.HttpMethod.Equals("POST", StringComparison.OrdinalIgnoreCase))
            {
                Deny("Method not allowed.");
                return;
            }

            string uid  = Request.Form["UID"]  ?? string.Empty;
            string pwd  = Request.Form["PWD"]  ?? string.Empty;
            string bnbr = Request.Form["BNBR"] ?? string.Empty;
            string key  = Request.Form["KEY"]  ?? string.Empty;

            if (string.IsNullOrEmpty(uid) || string.IsNullOrEmpty(pwd)
                || string.IsNullOrEmpty(bnbr) || string.IsNullOrEmpty(key))
            {
                Deny("Required fields missing.");
                return;
            }

            // Resolve configured keys. Keys live in the DLL's .config appSettings
            // so they can be rotated without recompiling.
            string key1 = ConfigurationManager.AppSettings["UILogon.Key1"] ?? string.Empty;
            string key2 = ConfigurationManager.AppSettings["UILogon.Key2"] ?? string.Empty;

            if (string.IsNullOrEmpty(key1) && string.IsNullOrEmpty(key2))
            {
                SecurityLog.Warn("UILogon: UILogon.Key1 and UILogon.Key2 are not configured.");
                Deny("Server configuration error.");
                return;
            }

            // Build the SSRS username from the posted key.
            string rsUser = ResolveUsername(key, key1, key2, uid, bnbr);
            if (rsUser == null)
            {
                SecurityLog.Info("UILogon", $"Invalid KEY presented for UID={uid} BNBR={bnbr}");
                Deny("Access denied.");
                return;
            }

            try
            {
                // Confirm account exists before attempting password check.
                if (!AuthenticationUtilities.VerifyUser(rsUser))
                {
                    SecurityLog.Info("UILogon", $"Unknown user: {rsUser}");
                    Deny("Access denied.");
                    return;
                }

                if (!AuthenticationUtilities.VerifyPassword(rsUser, pwd))
                {
                    SecurityLog.Info("UILogon", $"Invalid password for user: {rsUser}");
                    Deny("Access denied.");
                    return;
                }
            }
            catch (Exception ex)
            {
                SecurityLog.Error("UILogon.Page_Load", ex, $"Credential check failed for {rsUser}");
                Deny("Authentication error.");
                return;
            }

            // Credentials valid -- issue the Forms Auth cookie.
            SecurityLog.Info("UILogon", $"Authenticated: {rsUser}");
            FormsAuthentication.SetAuthCookie(rsUser, false);

            // If a ReturnUrl is present (browser-initiated flow), redirect there.
            // Otherwise return HTTP 200 so the WPF HttpClient can detect success.
            string returnUrl = Request.QueryString["ReturnUrl"];
            if (!string.IsNullOrEmpty(returnUrl) && IsLocalUrl(returnUrl))
            {
                Response.Redirect(returnUrl, false);
            }
            else
            {
                Response.StatusCode = 200;
                Response.ContentType = "application/json";
                Response.Write("{\"success\":true}");
                Response.End();
            }
        }

        /// <summary>
        /// Maps the posted KEY to a username format.
        /// Returns null if the key is not recognized.
        /// </summary>
        private static string ResolveUsername(
            string postedKey, string key1, string key2,
            string uid, string bnbr)
        {
            // Constant-time string comparison to resist timing attacks.
            if (!string.IsNullOrEmpty(key1) && SecureEquals(postedKey, key1))
                return string.Format(CultureInfo.InvariantCulture, "{0}-{1}", bnbr, uid);

            if (!string.IsNullOrEmpty(key2) && SecureEquals(postedKey, key2))
                return uid;

            return null;
        }

        /// <summary>
        /// XOR-based constant-time string comparison so key validation
        /// does not leak key length via timing.
        /// </summary>
        private static bool SecureEquals(string a, string b)
        {
            if (a == null || b == null) return false;
            int diff = a.Length ^ b.Length;
            int len  = Math.Min(a.Length, b.Length);
            for (int i = 0; i < len; i++)
                diff |= a[i] ^ b[i];
            return diff == 0;
        }

        private void Deny(string reason)
        {
            Response.StatusCode  = 401;
            Response.ContentType = "application/json";
            Response.Write(
                "{\"success\":false,\"reason\":"
                + "\"" + HttpUtility.JavaScriptStringEncode(reason) + "\"}");
            Response.End();
        }

        /// <summary>Guards against open-redirect attacks on ReturnUrl.</summary>
        private static bool IsLocalUrl(string url)
        {
            if (string.IsNullOrEmpty(url)) return false;
            return (url[0] == '/' && (url.Length == 1 || (url[1] != '/' && url[1] != '\\')))
                || (url.Length > 1 && url[0] == '~' && url[1] == '/');
        }
    }
}
