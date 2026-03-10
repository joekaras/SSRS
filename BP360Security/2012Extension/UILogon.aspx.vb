
#Region "Copyright Microsoft Corporation. All rights reserved."
'============================================================================
'  File:     UILogon.aspx.vb
'  Summary:  The code-behind for a logon page that supports Forms
'            Authentication in a custom security extension    
'--------------------------------------------------------------------
'  This file is part of Microsoft SQL Server Code Samples.
'    
' This source code is intended only as a supplement to Microsoft
' Development Tools and/or on-line documentation. See these other
' materials for detailed information regarding Microsoft code 
' samples.
'
' THIS CODE AND INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF 
' ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO 
' THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A
' PARTICULAR PURPOSE.
'===========================================================================
#End Region

Imports System
Imports System.Collections
Imports System.ComponentModel
Imports System.Data
Imports System.Drawing
Imports System.Web
Imports System.Net
Imports System.Web.Services
Imports System.Web.SessionState
Imports System.Web.UI
Imports System.Web.UI.WebControls
Imports System.Web.UI.HtmlControls
Imports System.Data.SqlClient
Imports System.Security.Cryptography
Imports System.Web.Security
Imports System.Xml
Imports System.Globalization



'<summary>
'Summary description for WebForm1.
'</summary>

Public Class UILogon
    Inherits System.Web.UI.Page
    Protected LblUser As System.Web.UI.WebControls.Label
    Protected TxtPwd As System.Web.UI.WebControls.TextBox
    Protected TxtUser As System.Web.UI.WebControls.TextBox
    Protected WithEvents BtnRegister As System.Web.UI.WebControls.Button
    Protected WithEvents BtnLogon As System.Web.UI.WebControls.Button
    Protected lblMessage As System.Web.UI.WebControls.Label
    Protected Label1 As System.Web.UI.WebControls.Label
    Protected LblPwd As System.Web.UI.WebControls.Label
    Protected LblPwd2 As System.Web.UI.WebControls.Label
    Protected TxtPwd2 As System.Web.UI.WebControls.TextBox

    Private fUid As String
    Public fKeyp As String
    Private fBnbr As String
    Private fKey As String
    Public RSBankUser As String

    Private Sub Page_Load(ByVal sender As Object, ByVal e As System.EventArgs) Handles MyBase.Load

        fUid = Request.Form("UID")
        If fUid = "" Then
            'Response.Write("Access denied to the BancPac 360 Report Manager")
            lblMessage.Text = "Access denied (UID=" + HttpUtility.HtmlEncode(fUid) + ", use hostname?) to the BancPac 360 Report Manager - 48607986"
            Exit Sub
        End If
        fKeyp = Request.Form("PWD")
        If fKeyp = "" Then
            'Response.Write("Access denied to the BancPac 360 Report Manager")
            lblMessage.Text = "Access denied to the BancPac 360 Report Manager - 48607988"
            Exit Sub
        End If
        fBnbr = Request.Form("BNBR")
        If fBnbr = "" Then
            'Response.Write("Access denied to the BancPac 360 Report Manager")
            lblMessage.Text = "Access denied to the BancPac 360 Report Manager - 48607990"
            Exit Sub
        End If
        fKey = Request.Form("KEY")
        If fKey = "" Then
            'Response.Write("Access denied to the BancPac 360 Report Manager")
            lblMessage.Text = "Access denied to the BancPac 360 Report Manager - 48607992"
            Exit Sub
        End If
        RSBankUser = ""
        If fKey = "bP3*6s$8!RdL-7^Ka~p9%zCG47#RtL(izi#58Be" Then
            RSBankUser = fBnbr + "-" + fUid
        End If
        If fKey = "jhI)6hI7^gtf{UF4YfHflLkj5$376579*^*P*gf" Then
            RSBankUser = fUid
        End If
        If RSBankUser = "" Then
            'Response.Write("Access denied to the BancPac 360 Report Manager")
            lblMessage.Text = "Access denied to the BancPac 360 Report Manager - 48607994"
            Exit Sub
        End If
        'lblMessage.Text = RSBankUser + " " + fKeyp
        TxtUser.Text = RSBankUser
        'TxtPwd.Text = fKeyp

        ' next, check if the user is valid
        Helper.BancPac360SecurityExtension.WriteEntry("Verifying User: " + RSBankUser, EventLogEntryType.Information)
        If AuthenticationUtilities.VerifyUser(RSBankUser) = False Then
            lblMessage.Text = "Access denied to the BancPac 360 Report Manager - 48607996"
            Exit Sub
        End If

        Helper.BancPac360SecurityExtension.WriteEntry("Authenticating User: " + RSBankUser, EventLogEntryType.Information)
        If AuthenticationUtilities.VerifyPassword(RSBankUser, fKeyp) = True Then
            AutoLogon()
            Exit Sub
        End If
        'LblUser.Visible = True
        'TxtUser.Visible = True
        'LblPwd.Visible = True
        'TxtPwd.Visible = True
        'LblPwd2.Visible = True
        'TxtPwd2.Visible = True
        'BtnLogon.Visible = True
        'lblMessage.Text = "Your BancPac keyp has changed. " + "Please enter your new one." '+ " fpwd:" + fKeyp
        'TxtPwd.Focus()

        lblMessage.Text = "Access denied to the BancPac 360 Report Manager - 48607998"
        'lblMessage.Text = fKeyp

    End Sub

#Region "Web Form Designer generated code"

    Protected Overrides Sub OnInit(ByVal e As EventArgs)
        '
        ' CODEGEN: This call is required by the ASP.NET Web Form Designer.
        '
        InitializeComponent()
        MyBase.OnInit(e)

    End Sub 'OnInit


    '/ <summary>
    '/ Required method for Designer support - do not modify
    '/ the contents of this method with the code editor.
    '/ </summary>
    Private Sub InitializeComponent()

    End Sub 'InitializeComponent

#End Region


    'Private Sub BtnRegister_Click(ByVal sender As Object, ByVal e As System.EventArgs)  Handles BtnRegister.Click
    '    Dim salt As String = AuthenticationUtilities.CreateSalt(5)
    '    Dim keypHash As String = AuthenticationUtilities.CreateKeyPHash(TxtPwd.Text, salt)
    '    If AuthenticationUtilities.ValidateUserName(TxtUser.Text) Then
    '        Try
    '            AuthenticationUtilities.StoreAccountDetails(TxtUser.Text, keypHash, salt)
    '        Catch ex As Exception
    '            lblMessage.Text = String.Format(CultureInfo.InvariantCulture, ex.Message)
    '        End Try
    '    Else
    '        'lblMessage.Text = String.Format(CultureInfo.InvariantCulture, My.Resources.CustomSecurity.UserNameError)
    '        lblMessage.Text = "User name contains invalid characters"
    '    End If

    'End Sub


    'Private Sub BtnLogon_Click(ByVal sender As Object, ByVal e As System.EventArgs)  Handles BtnLogon.Click

    '    If TxtPwd.Text <> fKeyp Then
    '        lblMessage.Text = "The keyp you entered does not match the BancPac keyp" '+ " fpwd:" + fKeyp + " text:" + TxtPwd.Text
    '        TxtPwd.Focus()
    '        Exit Sub
    '    End If

    '    If TxtPwd.Text <> TxtPwd2.Text Then
    '        lblMessage.Text = "The BancPac keyps you entered do not match. Please re-enter the BancPac keyps"
    '        TxtPwd.Focus()
    '        Exit Sub
    '    End If

    '    Dim salt As String = AuthenticationUtilities.CreateSalt(5)
    '    Dim keypHash As String = AuthenticationUtilities.CreateKeyPHash(fKeyp, salt)

    '    Try
    '        AuthenticationUtilities.UpdateAccountDetails(RSBankUser, keypHash, salt)
    '    Catch ex As Exception
    '        lblMessage.Text = String.Format(CultureInfo.InvariantCulture, ex.Message)
    '        Exit Sub
    '    End Try

    '    AutoLogon()

    'End Sub
    Private Sub AutoLogon()
        Dim keypVerified As Boolean = False
        Try
            Dim server As New ReportServerProxy()
            ' Get the server URL from the Report Manager configuration file
            server.Url = AuthenticationUtilities.GetReportServerUrl("localhost")
            Helper.BancPac360SecurityExtension.WriteEntry("Server URL: " + server.Url, EventLogEntryType.Information)
            Helper.BancPac360SecurityExtension.WriteEntry("Login RS User: " + RSBankUser, EventLogEntryType.Information)
            server.LogonUser(RSBankUser, fKeyp, Nothing)

            keypVerified = True

        Catch ex As Exception
            Helper.BancPac360SecurityExtension.WriteException("AutoLogin: ", ex, EventLogEntryType.Error)
            lblMessage.Text = String.Format(CultureInfo.InvariantCulture, ex.Message)
            Return
        End Try
        If keypVerified = True Then
            'lblMessage.Text = String.Format(CultureInfo.InvariantCulture, My.Resources.CustomSecurity.LoginSuccess)
            lblMessage.Text = "Login Successful"
            Dim redirectUrl As String = Request.QueryString("ReturnUrl")
            If Not (redirectUrl Is Nothing) Then
                If (IsLocalUrl(redirectUrl)) Then
                    Helper.BancPac360SecurityExtension.WriteEntry("Redirect URL: " + redirectUrl, EventLogEntryType.Information)
                    HttpContext.Current.Response.Redirect(redirectUrl, False)
                End If
            Else
                HttpContext.Current.Response.Redirect("./Folder.aspx", False)
            End If
        Else
            'lblMessage.Text = String.Format(CultureInfo.InvariantCulture, My.Resources.CustomSecurity.InvalidUsernameKeyP)
            lblMessage.Text = "Invalid user name or keyp"
        End If
    End Sub

    Private Function IsLocalUrl(ByVal url As String) As Boolean
        If String.IsNullOrEmpty(url) Then
            Return False
        Else
            Return ((url(0) = "/"c AndAlso (url.Length = 1 OrElse (url(1) <> "/"c AndAlso url(1) <> "\"c))) OrElse (url.Length > 1 AndAlso url(0) = "~"c AndAlso url(1) = "/"c))
        End If
    End Function

    Private Sub Page_LoadComplete(ByVal sender As Object, ByVal e As System.EventArgs) Handles Me.LoadComplete
        TxtPwd.Focus()
    End Sub
End Class

' Because the UILogon uses the Web service to connect to the report server
' you need to extend the server proxy to support authentication ticket
' (cookie) management

Public Class ReportServerProxy
    Inherits ReportingService2010

    Protected Overrides Function GetWebRequest(ByVal uri As Uri) As WebRequest
        Dim request As HttpWebRequest
        request = CType(HttpWebRequest.Create(uri), HttpWebRequest)
        ' Create a cookie jar to hold the request cookie
        Dim cookieJar As New CookieContainer()
        request.CookieContainer = cookieJar
        Dim rsAuthCookie As Cookie = AuthCookie
        ' if the client already has an auth cookie
        ' place it in the request's cookie container
        If Not (AuthCookie Is Nothing) Then
            request.CookieContainer.Add(rsAuthCookie)
        End If
        request.Timeout = -1
        request.Headers.Add("Accept-Language", HttpContext.Current.Request.Headers("Accept-Language"))
        Return request

    End Function


    Protected Overrides Function GetWebResponse(ByVal request As WebRequest) As WebResponse
        Dim response As WebResponse = MyBase.GetWebResponse(request)
        Dim cookieName As String = response.Headers("RSAuthenticationHeader")
        ' If the response contains an auth header, store the cookie
        If Not (cookieName Is Nothing) Then
            Utilities.CustomAuthCookieName = cookieName
            Dim webResponse As HttpWebResponse = CType(response, HttpWebResponse)
            Dim authCookie As Cookie = webResponse.Cookies(cookieName)
            ' If the auth cookie is null, throw an exception
            If authCookie Is Nothing Then
                Throw New Exception("Authorization ticket not received by LogonUser")
            End If
            ' otherwise save it for this request
            authCookie = authCookie
            ' and send it to the client
            Utilities.RelayCookieToClient(authCookie)
        End If
        Return response

    End Function


    Private Property AuthCookie() As Cookie
        Get
            If m_Authcookie Is Nothing Then
                m_Authcookie = Utilities.TranslateCookie(HttpContext.Current.Request.Cookies(Utilities.CustomAuthCookieName))
            End If
            Return m_Authcookie
        End Get
        Set
            m_Authcookie = Value
        End Set
    End Property
    Private m_Authcookie As Cookie = Nothing
End Class


Friend NotInheritable Class Utilities

    Friend Shared Property CustomAuthCookieName() As String
        Get
            SyncLock m_cookieNamelockRoot
                Return m_cookieName
            End SyncLock
        End Get
        Set
            SyncLock m_cookieNamelockRoot
                m_cookieName = Value
            End SyncLock
        End Set
    End Property
    Private Shared m_cookieName As String
    Private Shared m_cookieNamelockRoot As New Object()


    Private Overloads Shared Function TranslateCookie(ByVal netCookie As Cookie) As HttpCookie
        If netCookie Is Nothing Then
            Return Nothing
        End If
        Dim webCookie As New HttpCookie(netCookie.Name, netCookie.Value)
        ' Add domain only if it is dotted - IE doesn't send back the cookie 
        ' if we set the domain otherwise
        If netCookie.Domain.IndexOf("."c) <> -1 Then
            webCookie.Domain = netCookie.Domain
        End If
        webCookie.Expires = netCookie.Expires
        webCookie.Path = netCookie.Path
        webCookie.Secure = netCookie.Secure
        Return webCookie

    End Function


    Friend Overloads Shared Function TranslateCookie(ByVal webCookie As HttpCookie) As Cookie
        If webCookie Is Nothing Then
            Return Nothing
        End If
        Dim netCookie As New Cookie(webCookie.Name, webCookie.Value)
        If webCookie.Domain Is Nothing Then
            netCookie.Domain = HttpContext.Current.Request.ServerVariables("SERVER_NAME")
        End If
        netCookie.Expires = webCookie.Expires
        netCookie.Path = webCookie.Path
        netCookie.Secure = webCookie.Secure
        Return netCookie
    
    End Function
    
    
    Friend Shared Sub RelayCookieToClient(ByVal cookie As Cookie) 
        ' add the cookie if not already in there
        If HttpContext.Current.Response.Cookies(cookie.Name) Is Nothing Then
            HttpContext.Current.Response.Cookies.Remove(cookie.Name)
        End If
        
        HttpContext.Current.Response.SetCookie(TranslateCookie(cookie))
    
    End Sub
End Class