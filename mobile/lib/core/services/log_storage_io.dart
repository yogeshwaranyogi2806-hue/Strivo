import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'log_event.dart';
import 'log_sink.dart';

/// Writes one log file per calendar day into app-private storage.
///
/// Rotation falls out of the filename: a new day means a new file, so an
/// open app that runs past midnight rolls over on its next write. Files older
/// than [retentionDays] are deleted whenever the sink opens.
class FileLogSink extends LogSink {
  FileLogSink._(this._directory);

  /// How many days of history to keep on the device.
  static const int retentionDays = 7;

  static const String _prefix = 'strivo-';
  static const String _suffix = '.log';

  final Directory _directory;
  String? _activeName;

  @override
  bool get persistsToDisk => true;

  static String fileNameFor(DateTime timestamp) {
    final local = timestamp.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$_prefix${local.year}-$month-$day$_suffix';
  }

  @override
  Future<void> append(LogEvent event) async {
    try {
      final name = fileNameFor(event.timestamp);
      if (name != _activeName) {
        _activeName = name;
        await _purgeExpired(event.timestamp);
      }
      final line = '${event.toLine()}\n';
      final file = File('${_directory.path}${Platform.pathSeparator}$name');
      // flush: true so the entry survives a hard crash immediately after.
      await file.writeAsString(line, mode: FileMode.append, flush: true);
    } catch (_) {
      // Logging must never break the app. The in-memory buffer still has it.
    }
  }

  @override
  Future<List<LogFileInfo>> listFiles() async {
    try {
      final files = await _directory
          .list()
          .where((entry) =>
              entry is File &&
              entry.path.contains(_prefix) &&
              entry.path.endsWith(_suffix))
          .cast<File>()
          .toList();
      final info = <LogFileInfo>[];
      for (final file in files) {
        final stat = await file.stat();
        info.add(LogFileInfo(
          name: file.uri.pathSegments.last,
          sizeBytes: stat.size,
          modifiedAt: stat.modified,
        ));
      }
      info.sort((a, b) => b.name.compareTo(a.name));
      return info;
    } catch (_) {
      return const <LogFileInfo>[];
    }
  }

  @override
  Future<String> readFile(String name) async {
    try {
      final file = File('${_directory.path}${Platform.pathSeparator}$name');
      if (!await file.exists()) return '';
      return await file.readAsString();
    } catch (_) {
      return '';
    }
  }

  @override
  Future<void> clearAll() async {
    try {
      final files = await _directory
          .list()
          .where((entry) => entry is File)
          .cast<File>()
          .toList();
      for (final file in files) {
        await file.delete();
      }
    } catch (_) {
      // Ignored: a failed purge should not surface to the user.
    }
  }

  Future<void> _purgeExpired(DateTime now) async {
    final cutoff = now.subtract(const Duration(days: retentionDays));
    try {
      final files = await _directory
          .list()
          .where((entry) => entry is File)
          .cast<File>()
          .toList();
      for (final file in files) {
        final name = file.uri.pathSegments.last;
        if (!name.startsWith(_prefix) || !name.endsWith(_suffix)) continue;
        final day = _dateFromName(name);
        if (day == null || day.isAfter(cutoff)) continue;
        await file.delete();
      }
    } catch (_) {
      // Ignored.
    }
  }

  static DateTime? _dateFromName(String name) {
    final stamp = name.substring(_prefix.length, name.length - _suffix.length);
    final parts = stamp.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }
}

/// Opens the on-disk log directory.
Future<LogSink> createLogSink() async {
  try {
    final base = await getApplicationSupportDirectory();
    final directory = Directory('${base.path}${Platform.pathSeparator}logs');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final sink = FileLogSink._(directory);
    await sink._purgeExpired(DateTime.now());
    return sink;
  } catch (_) {
    return const NoopSink();
  }
}
