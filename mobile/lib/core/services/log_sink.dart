import 'log_event.dart';

/// Metadata for one log file on disk.
class LogFileInfo {
  const LogFileInfo({
    required this.name,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  final String name;
  final int sizeBytes;
  final DateTime modifiedAt;

  String get readableSize {
    if (sizeBytes < 1024) {
      return '$sizeBytes B';
    }
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Destination for log entries.
///
/// The concrete implementation is chosen at compile time by `log_storage.dart`,
/// so `dart:io` is never referenced on web.
abstract class LogSink {
  const LogSink();

  /// Appends one entry. Implementations must never throw.
  Future<void> append(LogEvent event) async {}

  /// Log files currently on disk, newest first.
  Future<List<LogFileInfo>> listFiles() async {
    return const <LogFileInfo>[];
  }

  /// Reads one file by [name].
  Future<String> readFile(String name) async => '';

  /// Deletes every log file.
  Future<void> clearAll() async {}

  /// True when this sink actually persists to disk.
  bool get persistsToDisk => false;
}

/// Used on web, and as the fallback when file storage cannot be opened.
class NoopSink extends LogSink {
  const NoopSink();
}
