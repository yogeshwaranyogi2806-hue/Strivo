import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/services/log_event.dart';
import '../../core/services/log_service.dart';
import '../../core/services/log_sink.dart';

/// Read-only view of the device log, so a coach can copy a stack trace out of
/// their phone and send it to a developer.
class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key});

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

enum _Filter { all, problems, actions }

class _LogViewerPageState extends State<LogViewerPage> {
  static const Duration _refreshInterval = Duration(seconds: 2);

  List<LogEvent> _entries = const <LogEvent>[];
  List<LogFileInfo> _files = const <LogFileInfo>[];
  _Filter _filter = _Filter.all;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(_refreshInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final files = await AppLog.listFiles();
    if (!mounted) return;
    setState(() {
      _entries = AppLog.recent;
      _files = files;
    });
  }

  List<LogEvent> get _visibleEntries => switch (_filter) {
        _Filter.all => _entries,
        _Filter.problems => _entries
            .where((e) => e.level == LogLevel.error || e.level == LogLevel.warn)
            .toList(),
        _Filter.actions =>
          _entries.where((e) => e.kind == LogKind.action).toList(),
      };

  Widget _filterChip(_Filter option, String label) => FilterChip(
        label: Text(label),
        selected: _filter == option,
        onSelected: (_) => setState(() => _filter = option),
      );

  @override
  Widget build(BuildContext context) {
    final visible = _visibleEntries;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity log'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StatusCard(entries: _entries.length, files: _files),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _entries.isEmpty ? null : _copySessionLog,
                    icon: const Icon(Icons.copy_all_outlined, size: 18),
                    label: const Text('Copy log'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _files.isEmpty ? null : _confirmClearFiles,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Delete files'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _SectionTitle(
                title: 'This session', trailing: '${visible.length} entries'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                _filterChip(_Filter.all, 'All'),
                _filterChip(_Filter.problems, 'Problems'),
                _filterChip(_Filter.actions, 'Actions'),
              ],
            ),
            const SizedBox(height: 16),
            if (visible.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('Nothing recorded yet.'),
              )
            else
              ...visible.map(_EntryTile.new),
            const SizedBox(height: 22),
            const _SectionTitle(title: 'Log files', trailing: 'kept 7 days'),
            const SizedBox(height: 4),
            Text(
              AppLog.persistsToDisk
                  ? 'One file per day, stored in app-private storage.'
                  : 'File logging is unavailable on this platform. Entries above are held in memory only.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: StrivoColors.muted),
            ),
            const SizedBox(height: 10),
            if (_files.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No log files yet.'),
              )
            else
              ..._files.map(_FileTile.new),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Future<void> _copySessionLog() async {
    await Clipboard.setData(ClipboardData(text: AppLog.exportRecent()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied ${_entries.length} entries.')),
    );
  }

  Future<void> _confirmClearFiles() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete log files?'),
        content:
            Text('${_files.length} file(s) will be removed from this device. '
                'Entries still in this session are kept.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AppLog.clearFiles();
    await _refresh();
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile(this.entry);

  final LogEvent entry;

  @override
  Widget build(BuildContext context) {
    final colour = switch (entry.level) {
      LogLevel.error => const Color(0xFFD92D20),
      LogLevel.warn => const Color(0xFFB54708),
      LogLevel.info => StrivoColors.navy,
      LogLevel.debug => StrivoColors.muted,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: entry.stackTrace == null ? null : () => _showStack(context),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE5E9EF)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 4, right: 10),
                width: 7,
                height: 7,
                decoration:
                    BoxDecoration(color: colour, shape: BoxShape.circle),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.event,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    if (entry.detail != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          entry.detail!,
                          style: const TextStyle(
                              fontSize: 12,
                              color: StrivoColors.muted,
                              height: 1.4),
                        ),
                      ),
                    if (entry.stackTrace != null)
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Text(
                          'Tap for stack trace',
                          style: TextStyle(
                              fontSize: 11, color: StrivoColors.coral),
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                entry.describe().substring(0, 8),
                style: const TextStyle(fontSize: 11, color: StrivoColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showStack(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stack trace'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              '${entry.error ?? ''}\n\n${entry.stackTrace}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile(this.file);

  final LogFileInfo file;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: const Icon(Icons.description_outlined, color: StrivoColors.navy),
      title: Text(file.name, style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        '${file.readableSize} · ${file.modifiedAt.year}-'
        '${file.modifiedAt.month.toString().padLeft(2, '0')}-'
        '${file.modifiedAt.day.toString().padLeft(2, '0')} '
        '${file.modifiedAt.hour.toString().padLeft(2, '0')}:'
        '${file.modifiedAt.minute.toString().padLeft(2, '0')}',
        style: const TextStyle(fontSize: 11),
      ),
      onTap: () => _open(context),
    );
  }

  Future<void> _open(BuildContext context) async {
    final contents = await AppLog.readFile(file.name);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(file.name),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              contents.isEmpty ? 'This file is empty.' : contents,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.entries, required this.files});

  final int entries;
  final List<LogFileInfo> files;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  AppLog.persistsToDisk
                      ? Icons.sd_storage_outlined
                      : Icons.info_outline,
                  color: StrivoColors.coral,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    AppLog.persistsToDisk
                        ? 'Writing to a daily log file'
                        : 'In-memory logging only',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Session ${AppLog.sessionId}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
            const SizedBox(height: 4),
            Text(
              '$entries entries buffered · ${files.length} file(s) on device',
              style: const TextStyle(fontSize: 12, color: StrivoColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing = ''});

  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        if (trailing.isNotEmpty)
          Text(trailing,
              style: const TextStyle(fontSize: 12, color: StrivoColors.muted)),
      ],
    );
  }
}
