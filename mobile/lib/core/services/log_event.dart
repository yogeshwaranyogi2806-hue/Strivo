/// Severity of a single log entry.
enum LogLevel { debug, info, warn, error }

/// What sort of entry this is.
///
/// [action] entries are the ones mirrored to the database audit trail, so
/// keep their names stable and machine-readable (`student.added`, not
/// "added the student").
enum LogKind { app, action, error }

/// One structured log entry. Serialises to a single JSON object on one line
/// so the file stays greppable while staying readable in a text editor.
class LogEvent {
  LogEvent({
    required this.level,
    required this.kind,
    required this.event,
    this.detail,
    this.error,
    this.stackTrace,
    this.sessionId = '',
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final DateTime timestamp;
  final LogLevel level;
  final LogKind kind;
  final String event;
  final String? detail;
  final String? error;
  final String? stackTrace;
  final String sessionId;

  Map<String, Object?> toJson() => <String, Object?>{
        'ts': timestamp.toUtc().toIso8601String(),
        'level': level.name,
        'kind': kind.name,
        'event': event,
        if (sessionId.isNotEmpty) 'session': sessionId,
        if (detail != null) 'detail': detail,
        if (error != null) 'error': error,
        if (stackTrace != null) 'stack': stackTrace,
      };

  String toLine() {
    final buffer = StringBuffer();
    for (final entry in toJson().entries) {
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write('${entry.key}=');
      final value = entry.value;
      if (value is! String || !value.contains(' ')) {
        buffer.write(value);
      } else {
        buffer.write('"${value.replaceAll('"', '\\"')}"');
      }
    }
    return buffer.toString();
  }

  /// A single-line human summary for the in-app viewer.
  String describe() {
    final time = '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';
    final message = error == null ? event : '$event — $error';
    return detail == null
        ? '$time  [$level] $message'
        : '$time  [$level] $message  ·  $detail';
  }
}

/// Removes anything that looks like a credential before it reaches a log
/// file. This is a backstop, not a guarantee: never pass a password, OTP or
/// access token in the first place.
String sanitise(String? value) {
  if (value == null) return '';
  var cleaned = value.replaceAll(RegExp(r'eyJ[A-Za-z0-9_-]{8,}'), '<token>');
// replaceAll does not expand capture groups, so the matched keyword is read
// back off the match to keep the original casing (Password, PASSWORD, ...).
  cleaned = cleaned.replaceAllMapped(
    RegExp(
      r'\b(password|pass|otp|token|secret|api[_-]?key)\b\s*[:=]\s*\S+',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}=<redacted>',
  );
  return cleaned;
}
