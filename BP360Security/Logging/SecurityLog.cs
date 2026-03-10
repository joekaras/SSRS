using System.Diagnostics;

namespace BancPac.ReportingServices.BP360.Logging
{
    /// <summary>
    /// Provides a lazily-initialized shared <see cref="EventLogWriter"/> for
    /// the BP360 Security Extension. All components write through this singleton
    /// so that the event log source is created only once.
    /// </summary>
    internal static class SecurityLog
    {
        private const string LogName    = "BP360 Security Extension";
        private const string SourceName = "SecurityExtension";

        private static EventLogWriter _instance;
        private static readonly object _lock = new object();

        /// <summary>
        /// The shared <see cref="EventLogWriter"/> instance.
        /// Thread-safe lazy initialization.
        /// </summary>
        internal static EventLogWriter Writer
        {
            get
            {
                if (_instance == null)
                {
                    lock (_lock)
                    {
                        if (_instance == null)
                            _instance = new EventLogWriter(LogName, SourceName);
                    }
                }
                return _instance;
            }
        }

        // Convenience pass-throughs so call sites stay concise.

        internal static void Info(string message)
            => Writer.WriteEntry(message, EventLogEntryType.Information);

        internal static void Info(string location, string message)
            => Writer.WriteEntry(location, message, EventLogEntryType.Information);

        internal static void Warn(string message)
            => Writer.WriteEntry(message, EventLogEntryType.Warning);

        internal static void Error(string location, System.Exception ex, string message = "")
            => Writer.WriteException(location, ex, message, EventLogEntryType.Error);
    }
}
