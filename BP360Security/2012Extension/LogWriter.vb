Imports System.Text

Public Class LogWriter
    Private source As String = String.Empty
    Private logName As String = String.Empty
    Private eventLog As EventLog = Nothing
    Private runningEntries As Dictionary(Of Integer, StringBuilder) = New Dictionary(Of Integer, StringBuilder)()
    Private runningEntryTypes As Dictionary(Of Integer, EventLogEntryType) = New Dictionary(Of Integer, EventLogEntryType)()

    Public Sub New(ByVal logName As String, ByVal source As String, ByVal Optional specifyCustomSize As Boolean = False)
        Me.source = source
        Me.logName = logName
        Me.eventLog = New EventLog()

        If EventLog.SourceExists(source) = False Then
            EventLog.CreateEventSource(source, logName)

            If specifyCustomSize = True Then
                Me.eventLog.Log = logName
                eventLog.MaximumKilobytes = 400000
            End If
        Else
            Me.eventLog.Log = logName
        End If

        Me.eventLog.Source = source
    End Sub

    Public Sub WriteEntry(ByVal what As String, ByVal Optional type As EventLogEntryType = EventLogEntryType.Information, ByVal Optional eventID As Integer = 0)
        Me.eventLog.WriteEntry(what, type, eventID)
    End Sub

    Public Sub WriteEntry(ByVal where As String, ByVal what As String, ByVal Optional type As EventLogEntryType = EventLogEntryType.Information, ByVal Optional eventID As Integer = 0)
        Dim sb As StringBuilder = New StringBuilder()
        sb.AppendLine(where)
        sb.AppendLine()
        sb.AppendLine(what)
        Me.eventLog.WriteEntry(sb.ToString().Trim(), type, eventID)
    End Sub

    Public Sub WriteException(ByVal where As String, ByVal ex As Exception, ByVal Optional message As String = "", ByVal Optional type As EventLogEntryType = EventLogEntryType.[Error], ByVal Optional eventID As Integer = 0)
        Dim sb As StringBuilder = New StringBuilder()
        sb.AppendLine(where)
        sb.AppendLine()

        If String.IsNullOrEmpty(message) = False Then
            sb.AppendLine(message)
            sb.AppendLine()
        End If

        Dim exceptionLevel As Integer = 1
        Dim testEx As Exception = ex

        While testEx IsNot Nothing
            sb.AppendLine(testEx.Message)
            exceptionLevel += 1
            testEx = testEx.InnerException
        End While

        sb.AppendLine()
        sb.AppendLine("Stack trace:")
        sb.AppendLine(ex.StackTrace)
        Me.WriteEntry(where, sb.ToString().Trim(), type, eventID)
    End Sub
End Class
