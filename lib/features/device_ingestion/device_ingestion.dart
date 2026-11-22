/// Device Ingestion Feature module.
///
/// Responsible for capturing background telemetry and personal signals:
/// - Android UsageStatsManager (App usage, screen time, foreground sessions)
/// - CallLog and SMS event streams
/// - System Notifications listener
///
/// Ingested data is filtered, sanitized, and stored locally into encrypted [MemoryNode] entries.
class DeviceIngestionModule {
  const DeviceIngestionModule();
}
