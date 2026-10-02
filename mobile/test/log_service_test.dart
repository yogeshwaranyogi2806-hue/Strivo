import 'package:flutter_test/flutter_test.dart';
import 'package:strivo/core/services/log_event.dart';
import 'package:strivo/core/services/log_service.dart';
import 'package:strivo/core/services/log_storage_io.dart';

void main() {
  group('log file rotation', () {
    test('names files by calendar day', () {
      expect(
        FileLogSink.fileNameFor(DateTime(2026, 10, 2, 9, 30)),
        'strivo-2026-10-02.log',
      );
    });

    test('zero pads month and day', () {
      expect(FileLogSink.fileNameFor(DateTime(2026, 1, 5)),
          'strivo-2026-01-05.log');
    });

    test('crossing midnight produces a different file', () {
      final beforeMidnight =
          FileLogSink.fileNameFor(DateTime(2026, 10, 2, 23, 59));
      final afterMidnight =
          FileLogSink.fileNameFor(DateTime(2026, 10, 3, 0, 1));
      expect(beforeMidnight, isNot(afterMidnight));
    });

    test('retention window is seven days', () {
      expect(FileLogSink.retentionDays, 7);
    });
  });

  group('LogEvent', () {
    test('omits fields that are absent', () {
      final event = LogEvent(
        level: LogLevel.info,
        kind: LogKind.app,
        event: 'app.start',
        sessionId: 'abc123',
      );
      final json = event.toJson();
      expect(json['event'], 'app.start');
      expect(json['session'], 'abc123');
      expect(json.containsKey('error'), isFalse);
      expect(json.containsKey('stack'), isFalse);
      expect(json.containsKey('detail'), isFalse);
    });

    test('quotes a detail value containing spaces', () {
      final event = LogEvent(
        level: LogLevel.warn,
        kind: LogKind.app,
        event: 'x',
        detail: 'two words',
      );
      expect(event.toLine(), contains('detail="two words"'));
    });

    test('leaves an unspaced detail value unquoted', () {
      final event = LogEvent(
        level: LogLevel.info,
        kind: LogKind.app,
        event: 'x',
        detail: 'method=email',
      );
      expect(event.toLine(), contains('detail=method=email'));
    });

    test('carries the stack trace through to the serialised form', () {
      final event = LogEvent(
        level: LogLevel.error,
        kind: LogKind.error,
        event: 'boom',
        error: 'Bad state',
        stackTrace: '#0 main',
      );
      expect(event.toLine(), contains('error="Bad state"'));
      expect(event.toLine(), contains('stack="#0 main"'));
    });
  });

  group('sanitise', () {
    test('redacts token-shaped strings', () {
      expect(sanitise('failed eyJhbGciOiJIUzI1NiJ9abcdef'), 'failed <token>');
    });

    test('redacts credential assignments regardless of case', () {
      expect(sanitise('Password=hunter2'), 'Password=<redacted>');
      expect(sanitise('api_key: abc123'), 'api_key=<redacted>');
    });

    test('leaves ordinary detail untouched', () {
      expect(sanitise('method=email'), 'method=email');
      expect(sanitise(null), '');
    });
  });

  group('AppLog buffer', () {
    test('keeps the newest entry at the front', () {
      AppLog.info('test.first');
      AppLog.info('test.second');
      expect(AppLog.recent.first.event, 'test.second');
      expect(AppLog.recent.any((e) => e.event == 'test.first'), isTrue);
    });

    test('stamps entries with the current session', () {
      AppLog.info('test.session');
      expect(AppLog.recent.first.sessionId, AppLog.sessionId);
    });

    test('export renders every buffered entry', () {
      AppLog.info('test.exportable');
      expect(AppLog.exportRecent(), contains('test.exportable'));
      expect(AppLog.exportRecentJson(), contains('test.exportable'));
    });
  });
}
