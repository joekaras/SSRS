Public Class Helper
    Public Const SECURITY_EXTENSION_LOG As String = "BP360 Security Extension"
    Public Const SOURCE_SECURITY_EXTENSION_LOG As String = "SecurityExtension"
    Private Shared securityExtension As LogWriter = Nothing
    Public Shared ReadOnly Property BancPac360SecurityExtension As LogWriter
        Get
            If securityExtension Is Nothing Then
                securityExtension = New LogWriter(SECURITY_EXTENSION_LOG, SOURCE_SECURITY_EXTENSION_LOG, True)
            End If
            Return securityExtension
        End Get
    End Property
End Class
