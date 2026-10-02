import 'log_sink.dart';

/// Web has no `dart:io` file system, so entries go to the developer console
/// only. The in-memory ring buffer in `AppLog` still backs the in-app viewer,
/// so the log screen remains useful in a browser.
Future<LogSink> createLogSink() async => const NoopSink();
