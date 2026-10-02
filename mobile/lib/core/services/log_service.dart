import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'log_event.dart';
import 'log_sink.dart';
import 'log_storage.dart';

/// Application-wide structured logging.
///
/// Every entry goes to three places: a capped in-memory ring buffer that backs
/// the in-app viewer, the developer console, and a daily rotating file on
/// Android/iOS. Nothing in here is allowed to throw.
abstract final class AppLog {
  /// Entries kept in memory for the in-app viewer.
  static const int bufferLimit = 200;

  /// Guards against the same error arriving twice when an uncaught async error
  /// hits both `PlatformDispatcher.onError` and the error zone.
  static const Duration _dedupeWindow = Duration(seconds: 2);

  static final Queue<LogEvent> _buffer = Queue<LogEvent>();
  static final Random _random = Random();

  static LogSink _sink = const NoopSink();
  static String _sessionId = 'uninitialised';
  static Object? _lastError;
  static DateTime? _lastErrorAt;

  /// Identifies this run of the app, so interleaved logs can be separated.
  static String get sessionId => _sessionId;

  /// True when entries are being written to a real file on disk.
  static bool get persistsToDisk => _sink.persistsToDisk;

  /// Newest entries first, for the in-app viewer.
  static List<LogEvent> get recent => _buffer.toList().reversed.toList();

  /// Opens the log file and records that the app started.
  static Future<void> init() async {
    _sessionId = _generateSessionId();
    _sink = await createLogSink();
    info('app.start', detail: 'file_logging=${_sink.persistsToDisk}');
  }

  static String _generateSessionId() {
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final noise = _random.nextInt(0xFFFFFF).toRadixString(36).padLeft(4, '0');
    return '$stamp$noise';
  }

  static void debug(String event, {String? detail}) => _record(LogEvent(
      level: LogLevel.debug,
      kind: LogKind.app,
      event: event,
      detail: sanitise(detail)));

  static void info(String event, {String? detail}) => _record(LogEvent(
      level: LogLevel.info,
      kind: LogKind.app,
      event: event,
      detail: sanitise(detail)));

  static void warn(String event, {String? detail, Object? error}) => _record(
        LogEvent(
          level: LogLevel.warn,
          kind: LogKind.error,
          event: event,
          detail: sanitise(detail),
          error: error == null ? null : sanitise(error.toString()),
        ),
      );

  static void error(String event, Object error, StackTrace stackTrace,
      {String? detail}) {
    final now = DateTime.now();
    if (identical(error, _lastError) &&
        _lastErrorAt != null &&
        now.difference(_lastErrorAt!) < _dedupeWindow) {
      return;
    }
    _lastError = error;
    _lastErrorAt = now;
    _record(LogEvent(
      level: LogLevel.error,
      kind: LogKind.error,
      event: event,
      detail: sanitise(detail),
      error: sanitise(error.toString()),
      stackTrace: sanitise(stackTrace.toString()),
    ));
  }

  /// Records a business action — something a person did that matters later.
  /// Mirrored to the database audit trail by `AuditService`.
  static void action(String event, {String? detail}) => _record(
        LogEvent(
            level: LogLevel.info,
            kind: LogKind.action,
            event: event,
            detail: sanitise(detail)),
      );

  static void _record(LogEvent event) {
    final entry = event.sessionId.isEmpty
        ? LogEvent(
            level: event.level,
            kind: event.kind,
            event: event.event,
            detail: event.detail,
            error: event.error,
            stackTrace: event.stackTrace,
            sessionId: _sessionId,
          )
        : event;

    _buffer.addLast(entry);
    while (_buffer.length > bufferLimit) {
      _buffer.removeFirst();
    }

    try {
      final line = entry.toLine();
      developer.log(line, name: 'strivo', level: _developerLevel(entry.level));
    } catch (_) {
      // Console output is best effort.
    }

    unawaited(_write(entry));
  }

  static Future<void> _write(LogEvent event) async {
    try {
      await _sink.append(event);
    } catch (_) {
      // A full or unavailable disk must never break the app.
    }
  }

  static int _developerLevel(LogLevel level) => switch (level) {
        LogLevel.debug => 500,
        LogLevel.info => 800,
        LogLevel.warn => 900,
        LogLevel.error => 1000,
      };

  /// Routes framework and uncaught async errors into the log.
  static void installGlobalHandlers() {
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      error('flutter.error', details.exception,
          details.stack ?? StackTrace.current,
          detail: details.library);
      previousOnError?.call(details);
    };

    PlatformDispatcher.instance.onError = (error, stackTrace) {
      AppLog.error('async.error', error, stackTrace);
      return true;
    };
  }

  /// Log files currently on disk, newest first.
  static Future<List<LogFileInfo>> listFiles() async {
    try {
      return await _sink.listFiles();
    } catch (_) {
      return const <LogFileInfo>[];
    }
  }

  static Future<String> readFile(String name) async {
    try {
      return await _sink.readFile(name);
    } catch (_) {
      return '';
    }
  }

  static Future<void> clearFiles() async {
    try {
      await _sink.clearAll();
      info('log.cleared', detail: 'requested_by_user');
    } catch (_) {
      // Ignored.
    }
  }

  /// Everything currently in memory, as shareable text.
  static String exportRecent() {
    final buffer = StringBuffer()
      ..writeln('Strivo log · session $_sessionId')
      ..writeln('Exported ${DateTime.now().toIso8601String()}')
      ..writeln('---');
    for (final entry in recent) {
      buffer.writeln(entry.toLine());
    }
    return buffer.toString();
  }

  /// JSON array of the buffer, for anyone who wants to parse it.
  static String exportRecentJson() => const JsonEncoder.withIndent('  ')
      .convert(recent.map((e) => e.toJson()).toList());
}
