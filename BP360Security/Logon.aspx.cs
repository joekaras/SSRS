#region
// Copyright (c) 2016 Microsoft Corporation. All Rights Reserved.
// Licensed under the MIT License (MIT)
/*============================================================================
  File:     Logon.aspx.cs
  Summary:  The code-behind for a logon page that supports Forms
            Authentication in a custom security extension    
--------------------------------------------------------------------
  This file is part of Microsoft SQL Server Code Samples.
    
 This source code is intended only as a supplement to Microsoft
 Development Tools and/or on-line documentation. See these other
 materials for detailed information regarding Microsoft code 
 samples.

 THIS CODE AND INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF 
 ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO 
 THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A
 PARTICULAR PURPOSE.
===========================================================================*/
#endregion

using System;
using System.Collections;
using System.ComponentModel;
using System.Configuration;
using System.Data;
using System.Drawing;
using System.Web;
using System.Web.SessionState;
using System.Web.UI;
using System.Web.UI.WebControls;
using System.Web.UI.HtmlControls;
using System.Data.SqlClient;
using System.Security.Cryptography;
using System.Web.Security;
using Microsoft.ReportingServices.Interfaces;
using BancPac.ReportingServices.BP360.App_LocalResources;
using System.Globalization;

namespace BancPac.ReportingServices.BP360
{
   public class Logon : System.Web.UI.Page
   {
      protected System.Web.UI.WebControls.Label LblUser;
      protected System.Web.UI.WebControls.TextBox TxtPwd;
      protected System.Web.UI.WebControls.TextBox TxtUser;
      protected System.Web.UI.WebControls.Button BtnRegister;
      protected System.Web.UI.WebControls.Button BtnLogon;
      protected System.Web.UI.WebControls.Label lblMessage;
      protected System.Web.UI.WebControls.Label Label1;
      protected System.Web.UI.WebControls.Label LblPwd;

      private void Page_Load(object sender, System.EventArgs e)
      {
         // UILogon API path: WPF client POSTs UID/PWD/BNBR/KEY to logon.aspx.
         // Logon.aspx is the Forms Auth loginUrl and is always reachable without
         // auth — the only reliable way to expose a pre-auth endpoint in SSRS.
         if (Request.HttpMethod.Equals("POST", StringComparison.OrdinalIgnoreCase)
             && !string.IsNullOrEmpty(Request.Form["KEY"]))
         {
            HandleApiLogon();
         }
      }

      // -----------------------------------------------------------------------
      // UILogon API handler (WPF / server-to-server)
      // Accepts: POST UID / PWD / BNBR / KEY
      // Returns: 200 {"success":true} on success, 401 {"success":false,...} on failure
      // -----------------------------------------------------------------------
      [System.Diagnostics.CodeAnalysis.SuppressMessage(
          "Microsoft.Design", "CA1031:DoNotCatchGeneralExceptionTypes")]
      private void HandleApiLogon()
      {
         string uid  = Request.Form["UID"]  ?? string.Empty;
         string pwd  = Request.Form["PWD"]  ?? string.Empty;
         string bnbr = Request.Form["BNBR"] ?? string.Empty;
         string key  = Request.Form["KEY"]  ?? string.Empty;

         if (string.IsNullOrEmpty(uid) || string.IsNullOrEmpty(pwd)
             || string.IsNullOrEmpty(bnbr))
         {
            ApiDeny("Required fields missing.");
            return;
         }

         // ConfigurationManager.AppSettings reads web.config in the web app context.
         // UILogon keys are stored in the DLL's own .config file; read it explicitly.
         string key1 = ReadDllAppSetting("UILogon.Key1");
         string key2 = ReadDllAppSetting("UILogon.Key2");

         if (string.IsNullOrEmpty(key1) && string.IsNullOrEmpty(key2))
         {
            ApiDeny("Server configuration error.");
            return;
         }

         string rsUser = ResolveApiUsername(key, key1, key2, uid, bnbr);
         if (rsUser == null)
         {
            ApiDeny("Access denied.");
            return;
         }

         try
         {
            if (!AuthenticationUtilities.VerifyUser(rsUser)
                || !AuthenticationUtilities.VerifyPassword(rsUser, pwd))
            {
               ApiDeny("Access denied.");
               return;
            }
         }
         catch (Exception)
         {
            ApiDeny("Authentication error.");
            return;
         }

         FormsAuthentication.SetAuthCookie(rsUser, false);
         // Suppress the FormsAuthentication 302 redirect on success so the
         // WPF HttpClient sees the 200 + Set-Cookie directly.
         Response.SuppressFormsAuthenticationRedirect = true;
         Response.StatusCode  = 200;
         Response.ContentType = "application/json";
         Response.Write("{\"success\":true}");
         Response.End();
      }

      private static string ResolveApiUsername(
          string postedKey, string key1, string key2,
          string uid, string bnbr)
      {
         if (!string.IsNullOrEmpty(key1) && ApiSecureEquals(postedKey, key1))
            return string.Format(CultureInfo.InvariantCulture, "{0}-{1}", bnbr, uid);
         if (!string.IsNullOrEmpty(key2) && ApiSecureEquals(postedKey, key2))
            return uid;
         return null;
      }

      private static bool ApiSecureEquals(string a, string b)
      {
         if (a == null || b == null) return false;
         int diff = a.Length ^ b.Length;
         int len  = Math.Min(a.Length, b.Length);
         for (int i = 0; i < len; i++) diff |= a[i] ^ b[i];
         return diff == 0;
      }

      /// <summary>
      /// Reads an appSetting from BancPac.ReportingServices.BP360.dll.config.
      /// In an ASP.NET web app, ConfigurationManager.AppSettings reads web.config,
      /// so the DLL's own config must be opened explicitly.
      /// </summary>
      private static string ReadDllAppSetting(string key)
      {
         try
         {
            // Assembly.Location returns the shadow-copy path in ASP.NET, not the bin dir.
            // Use HttpRuntime.BinDirectory which always points to the physical bin folder.
            string cfgPath = System.IO.Path.Combine(
                HttpRuntime.BinDirectory,
                "BancPac.ReportingServices.BP360.dll.config");
            if (!System.IO.File.Exists(cfgPath)) return string.Empty;
            var map = new System.Configuration.ExeConfigurationFileMap { ExeConfigFilename = cfgPath };
            var cfg = ConfigurationManager.OpenMappedExeConfiguration(
                map, System.Configuration.ConfigurationUserLevel.None);
            return cfg.AppSettings.Settings[key]?.Value ?? string.Empty;
         }
         catch
         {
            return string.Empty;
         }
      }

      private void ApiDeny(string reason)
      {
         // SuppressFormsAuthenticationRedirect prevents the FormsAuthentication
         // module from converting this 401 into a 302 redirect to logon.aspx.
         Response.SuppressFormsAuthenticationRedirect = true;
         Response.StatusCode  = 401;
         Response.ContentType = "application/json";
         Response.Write("{\"success\":false,\"reason\":\""
             + HttpUtility.JavaScriptStringEncode(reason) + "\"}");
         Response.End();
      }

      #region Web Form Designer generated code
      override protected void OnInit(EventArgs e)
      {
            InitializeComponent();
            base.OnInit(e);
      }
      
      private void InitializeComponent()
      {    
         this.BtnLogon.Click += new System.EventHandler(this.ServerBtnLogon_Click);
         this.BtnRegister.Click += new System.EventHandler(this.BtnRegister_Click);
         this.Load += new System.EventHandler(this.Page_Load);

      }
      #endregion

       [System.Diagnostics.CodeAnalysis.SuppressMessage("Microsoft.Design", "CA1031:DoNotCatchGeneralExceptionTypes")]
      private void BtnRegister_Click(object sender, 
         System.EventArgs e)
      {
         string salt = AuthenticationUtilities.CreateSalt(5);
         string passwordHash =
            AuthenticationUtilities.CreatePasswordHash(TxtPwd.Text, salt);
         if (AuthenticationUtilities.ValidateUserName(TxtUser.Text))
         {
            try
            {
               AuthenticationUtilities.StoreAccountDetails(
                  TxtUser.Text, passwordHash, salt);
            }
            catch(Exception ex)
            {
              lblMessage.Text = string.Format(CultureInfo.InvariantCulture, ex.Message);
            }
         }
         else
         {

           lblMessage.Text = string.Format(CultureInfo.InvariantCulture,
               Logon_aspx.UserNameError);
         }
      }

       [System.Diagnostics.CodeAnalysis.SuppressMessage("Microsoft.Design", "CA1031:DoNotCatchGeneralExceptionTypes")]
      private void ServerBtnLogon_Click(object sender, 
         System.EventArgs e)
      {
         bool passwordVerified = false;
         try
         {
            passwordVerified = 
               AuthenticationUtilities.VerifyPassword(TxtUser.Text,TxtPwd.Text);
            if (passwordVerified)
            {
               FormsAuthentication.RedirectFromLoginPage(
                  TxtUser.Text, false);
            }
            else
            {
               Response.Redirect("logon.aspx");
            }
         }
         catch(Exception ex)
         {
           lblMessage.Text = string.Format(CultureInfo.InvariantCulture, ex.Message);
            return;
         }
         if (passwordVerified == true )
         {
            // The user is authenticated
            // At this point, an authentication ticket is normally created
            // This can subsequently be used to generate a GenericPrincipal
            // object for .NET authorization purposes
            // For details, see "How To: Use Forms authentication with 
            // GenericPrincipal objects
           lblMessage.Text = string.Format(CultureInfo.InvariantCulture,
              Logon_aspx.LoginSuccess);
           BtnRegister.Enabled = false;
         }
         else
         {
           lblMessage.Text = string.Format(CultureInfo.InvariantCulture,
             Logon_aspx.InvalidUsernamePassword);
         }
      }
   }
}
