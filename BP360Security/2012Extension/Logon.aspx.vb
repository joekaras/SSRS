
#Region "Copyright Microsoft Corporation. All rights reserved."
'============================================================================
'  File:     Logon.aspx.vb
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
Imports System.Web.SessionState
Imports System.Web.UI
Imports System.Web.UI.WebControls
Imports System.Web.UI.HtmlControls
Imports System.Data.SqlClient
Imports System.Security.Cryptography
Imports System.Web.Security
Imports Microsoft.ReportingServices.Interfaces
Imports System.Globalization

Public Class Logon
    Inherits System.Web.UI.Page
    Protected LblUser As System.Web.UI.WebControls.Label
    Protected TxtPwd As System.Web.UI.WebControls.TextBox
    Protected TxtUser As System.Web.UI.WebControls.TextBox
    Protected WithEvents BtnRegister As System.Web.UI.WebControls.Button
    Protected WithEvents BtnLogon As System.Web.UI.WebControls.Button
    Protected lblMessage As System.Web.UI.WebControls.Label
    Protected Label1 As System.Web.UI.WebControls.Label
    Protected LblPwd As System.Web.UI.WebControls.Label
    
    
    Private Sub Page_Load(ByVal sender As Object, ByVal e As System.EventArgs)  Handles MyBase.Load
        lblMessage.Text = "Access denied to the BancPac 360 Report Server"
    End Sub
    
    
    #Region "Web Form Designer generated code"
    
    Protected Overrides Sub OnInit(ByVal e As EventArgs) 
        InitializeComponent()
        MyBase.OnInit(e)
    
    End Sub 'OnInit
    
    
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
    '        lblMessage.Text = "Invalid user name"
    '    End If

    'End Sub


    Private Sub ServerBtnLogon_Click(ByVal sender As Object, ByVal e As System.EventArgs) Handles BtnLogon.Click
        Dim keypVerified As Boolean = False
        Try
            keypVerified = AuthenticationUtilities.VerifyPassword(TxtUser.Text, TxtPwd.Text)
            If keypVerified Then
                FormsAuthentication.RedirectFromLoginPage(TxtUser.Text, False)
            Else
                Response.Redirect("logon.aspx")
            End If
        Catch ex As Exception
            lblMessage.Text = String.Format(CultureInfo.InvariantCulture, ex.Message)
            Return
        End Try
        If keypVerified = True Then
            ' The user is authenticated
            ' At this point, an authentication ticket is normally created
            ' This can subsequently be used to generate a GenericPrincipal
            ' object for .NET authorization purposes
            ' For details, see "How To: Use Forms authentication with 
            ' GenericPrincipal objects
            'lblMessage.Text = String.Format(CultureInfo.InvariantCulture, My.Resources.CustomSecurity.LoginSuccess)
            lblMessage.Text = "Login Successful"
        Else
            'lblMessage.Text = String.Format(CultureInfo.InvariantCulture, My.Resources.CustomSecurity.InvalidUsernameKeyP)
            lblMessage.Text = "Invalid user name or keyp"
        End If
    
    End Sub
End Class