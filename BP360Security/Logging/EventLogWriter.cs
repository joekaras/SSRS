using System;
using System.Diagnostics;
using System.Text;

namespace BancPac.ReportingServices.BP360.Logging
{
    /// <summary>
    /// Writes structured entries to the Windows Application Event Log.
    /// The log source is created on first use if it does not already exist.
    /// Requires the process to have rights to create event sources (typically
    /// true for the SSRS service account on first deployment).
    /// </summary>
    internal sealed class EventLogWriter
    {
        private readonly EventLog _eventLog;

        /// <param name="logName">Event log name (e.g. "BP360 Security Extension").</param>
        /// <param name="source">Source name shown in Event Viewer.</param>
        /// <param name="maxKilobytes">Optional custom log size cap. Defaults to 400 MB.</param>
        internal EventLogWriter(string logName, string source, int maxKilobytes = 400_000)
        {
            _eventLog = new EventLog();

            if (!EventLog.SourceExists(source))
            {
                EventLog.CreateEventSource(source, logName);
                _eventLog.Log = logName;
                _eventLog.MaximumKilobytes = maxKilobytes;
            }
            else
            {
                _eventLog.Log = logName;
            }

            _eventLog.Source = source;
        }

        /// <summary>Writes a simple message.</summary>
        internal void WriteEntry(
            string message,
            EventLogEntryType type = EventLogEntryType.Information,
            int eventId = 0)
        {
            _eventLog.WriteEntry(message, type, eventId);
        }

        /// <summary>Writes a message tagged with a location (method / class).</summary>
        internal void WriteEntry(
            string location,
            string message,
            EventLogEntryType type = EventLogEntryType.Information,
            int eventId = 0)
        {
            var sb = new StringBuilder();
            sb.AppendLine(location);
            sb.AppendLine();
            sb.AppendLine(message);
            _eventLog.WriteEntry(sb.ToString().Trim(), type, eventId);
        }

        /// <summary>
        /// Writes an exception with full inner-exception chain and stack trace.
        /// </summary>
        internal void WriteException(
            string location,
            Exception ex,
            string additionalMessage = "",
            EventLogEntryType type = EventLogEntryType.Error,
            int eventId = 0)
        {
            var sb = new StringBuilder();
            sb.AppendLine(location);
            sb.AppendLine();

            if (!string.IsNullOrEmpty(additionalMessage))
            {
                sb.AppendLine(additionalMessage);
                sb.AppendLine();
            }

            Exception current = ex;
            while (current != null)
            {
                sb.AppendLine(current.Message);
                current = current.InnerException;
            }

            sb.AppendLine();
            sb.AppendLine("Stack trace:");
            sb.AppendLine(ex.StackTrace);

            _eventLog.WriteEntry(sb.ToString().Trim(), type, eventId);
        }
    }
}
