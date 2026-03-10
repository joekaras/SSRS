Imports System
Imports System.Web
Imports System.Net
Imports System.Xml
Imports System.Security.Cryptography
Imports System.IO
Imports System.Text
Imports System.Configuration
Imports System.Collections.Specialized

Public Class ConnectionProxy
    Private mCSP As New RijndaelManaged
    Dim str As String
    Dim rsPd As String
    Dim dBConnection As String
    Dim doc As New XmlDocument()
    ReadOnly Property ConnString() As String
        Get
            str = "http://10.96.150.64/ReportServer/ReportService2005.asmx"
            doc.Load("bancpac360.xml")
            Dim child As XmlNode
            If doc IsNot Nothing AndAlso doc.DocumentElement IsNot Nothing Then
                For Each child In doc.DocumentElement.ChildNodes
                    If child.Name = "BP360ConnectionString" Then
                        str = child.InnerText
                    End If
                Next child
            End If
            Return str
        End Get
    End Property
    ReadOnly Property PwdStr() As String
        Get
            rsPd = String.Empty
            doc.Load("bancpac360.xml")
            Dim child As XmlNode
            If doc IsNot Nothing AndAlso doc.DocumentElement IsNot Nothing Then
                For Each child In doc.DocumentElement.ChildNodes
                    If child.Name = "thomrs" Then
                        rsPd = DecryptString(child.InnerText)
                    End If
                Next child
            End If
            Return rsPd
        End Get
    End Property

    ReadOnly Property DBConnectionStr() As String
        Get
            dBConnection = "Server=localhost;Integrated Security=SSPI;database=UserAccounts"

            Dim myDllConfig As Configuration = ConfigurationManager.OpenExeConfiguration(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Bin\BP360Security.dll"))
            Dim myDllConfigAppSettings As AppSettingsSection = DirectCast(myDllConfig.GetSection("appSettings"), AppSettingsSection)
            Dim exePath As String = System.IO.Path.Combine(Environment.CurrentDirectory, "BP360Security.dll.config")

            If (myDllConfigAppSettings.Settings("DBConnectionString") IsNot Nothing) Then
                dBConnection = myDllConfigAppSettings.Settings("DBConnectionString").Value
            End If
            Return dBConnection
        End Get
    End Property

    ReadOnly Property InstanceNameStr() As String
        Get
            Dim InstanceName As String = String.Empty

            Dim myDllConfig As Configuration = ConfigurationManager.OpenExeConfiguration(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Bin\BP360Security.dll"))
            Dim myDllConfigAppSettings As AppSettingsSection = DirectCast(myDllConfig.GetSection("appSettings"), AppSettingsSection)

            If (myDllConfigAppSettings.Settings("InstanceName") IsNot Nothing) Then
                InstanceName = myDllConfigAppSettings.Settings("InstanceName").Value
            End If
            Return InstanceName
        End Get
    End Property


    Public Shared Function DecryptString(ByVal encryptedText As String) As String
        Dim cipherTextBytes As Byte() = Convert.FromBase64String(encryptedText)

        Dim Hash As String = String.Empty
        Dim SaltKey As String = String.Empty
        Dim VIKey As String = String.Empty
        Dim secureSection = TryCast(ConfigurationManager.GetSection("SecureSection"), NameValueCollection)

        If secureSection IsNot Nothing Then
            Hash = secureSection("Hash").ToString()
            SaltKey = secureSection("SaltKey").ToString()
            VIKey = secureSection("VIKey").ToString()
        End If

        Dim keyBytes As Byte() = New Rfc2898DeriveBytes(Hash, Encoding.ASCII.GetBytes(SaltKey)).GetBytes(256 / 8)
        Dim symmetricKey = New RijndaelManaged() With {
        .Mode = CipherMode.CBC,
        .Padding = PaddingMode.PKCS7
    }
        Dim decryptor = symmetricKey.CreateDecryptor(keyBytes, Encoding.ASCII.GetBytes(VIKey))
        Dim memoryStream = New MemoryStream(cipherTextBytes)
        Dim cryptoStream = New CryptoStream(memoryStream, decryptor, CryptoStreamMode.Read)
        Dim plainTextBytes As Byte() = New Byte(cipherTextBytes.Length - 1) {}
        Dim decryptedByteCount As Integer = cryptoStream.Read(plainTextBytes, 0, plainTextBytes.Length)
        memoryStream.Close()
        cryptoStream.Close()
        Return Encoding.UTF8.GetString(plainTextBytes, 0, decryptedByteCount).TrimEnd(vbNullChar.ToCharArray())
    End Function
End Class
