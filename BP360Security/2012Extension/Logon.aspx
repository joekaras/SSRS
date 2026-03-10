<%@ Page Language="vb" Codebehind="Logon.aspx.vb" AutoEventWireup="false" Inherits="BP360Security.Logon, BP360Security" meta:resourcekey="PageResource1" Culture="Auto" UICulture="Auto" %>
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0 Transitional//EN">
<HTML>
   <HEAD>
      <title>BancPac 360 Reporting Services Logon</title>
      <meta name="GENERATOR" Content="Microsoft Visual Studio .NET 7.1">
      <meta name="CODE_LANGUAGE" Content="Visual Basic .NET 7.1">
      <meta name="vs_defaultClientScript" content="JavaScript">
      <meta name="vs_targetSchema" content="http://schemas.microsoft.com/intellisense/ie5">
   </HEAD>
   <body MS_POSITIONING="GridLayout">
      <form id="Form1" method="post" runat="server">
         <asp:Label id="LblUser" style="Z-INDEX: 101; LEFT: 176px; POSITION: absolute; TOP: 152px" runat="server"
            Width="96px" Font-Size="X-Small" Font-Names="Verdana" Font-Bold="True" meta:resourcekey="LblUserResource1" Visible="False">UserName:</asp:Label>
         <asp:Button id="BtnLogon" style="Z-INDEX: 106; LEFT: 352px; POSITION: absolute; TOP: 224px"
            runat="server" Width="104px" Text="Logon" tabIndex="3" meta:resourcekey="BtnLogonResource1" Visible="False"></asp:Button>
         <asp:TextBox id="TxtPwd" style="Z-INDEX: 103; LEFT: 296px; POSITION: absolute; TOP: 184px" runat="server"
            tabIndex="2" Width="160px" TextMode="KeyP" meta:resourcekey="TxtPwdResource1" Visible="False"></asp:TextBox>
         <asp:Label id="LblPwd" style="Z-INDEX: 102; LEFT: 176px; POSITION: absolute; TOP: 192px" runat="server"
            Width="96px" Font-Size="X-Small" Font-Names="Verdana" Font-Bold="True" meta:resourcekey="LblPwdResource1" Visible="False">KeyP:</asp:Label>&nbsp;
         <asp:TextBox id="TxtUser" style="Z-INDEX: 104; LEFT: 296px; POSITION: absolute; TOP: 152px" runat="server"
            tabIndex="1" Width="160px" meta:resourcekey="TxtUserResource1" Visible="False"></asp:TextBox>
         <asp:Button id="BtnRegister" style="Z-INDEX: 105; LEFT: 232px; POSITION: absolute; TOP: 224px"
            runat="server" Width="104px" Text="Register User" tabIndex="4" meta:resourcekey="BtnRegisterResource1" Visible="False"></asp:Button>
         <asp:Label id="lblMessage" style="Z-INDEX: 107; LEFT: 168px; POSITION: absolute; TOP: 272px"
            runat="server" Width="321px" meta:resourcekey="lblMessageResource1"></asp:Label>
         <asp:Label id="Label1" style="Z-INDEX: 108; LEFT: 120px; POSITION: absolute; TOP: 96px" runat="server"
            Width="416px" Height="32px" Font-Size="Medium" Font-Names="Verdana" meta:resourcekey="Label1Resource1" Text="BancPac 360 - Report Server"></asp:Label>
      </form>
   </body>
</HTML>
