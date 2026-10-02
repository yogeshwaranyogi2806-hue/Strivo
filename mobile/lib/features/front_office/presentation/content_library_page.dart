import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme.dart';
import '../../../core/services/content_service.dart';

/// Student-facing content library. Only published items reach this list; the
/// `is_published` filter is applied in the query and again by row level
/// security, so an unpublished draft cannot be surfaced by editing a filter.
class ContentLibraryPage extends ConsumerStatefulWidget {
  const ContentLibraryPage({super.key});

  @override
  ConsumerState<ContentLibraryPage> createState() => _ContentLibraryPageState();
}

class _ContentLibraryPageState extends ConsumerState<ContentLibraryPage> {
  ContentType? _filter;
  late Future<List<ContentItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = ContentService.publishedLibrary();
  }

  void _reload() {
    setState(() => _future = ContentService.publishedLibrary());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                _FilterChip(
                  label: 'All',
                  selected: _filter == null,
                  onTap: () => setState(() => _filter = null),
                ),
                for (final type in ContentType.values)
                  _FilterChip(
                    label: type.label,
                    selected: _filter == type,
                    onTap: () => setState(() => _filter = type),
                  ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<ContentItem>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  final error = snapshot.error;
                  final message = error is ContentException
                      ? error.message
                      : 'Could not load the library.';
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text(message, textAlign: TextAlign.center),
                    ),
                  );
                }
                final all = snapshot.data ?? const <ContentItem>[];
                final items = _filter == null
                    ? all
                    : all.where((i) => i.type == _filter).toList();
                if (items.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(28),
                      child: Text(
                        'Nothing here yet. Your coach will add material as it is ready.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  itemCount: items.length,
                  itemBuilder: (context, index) =>
                      _ContentCard(item: items[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _ContentCard extends StatelessWidget {
  const _ContentCard({required this.item});

  final ContentItem item;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: StrivoColors.navy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_iconFor(item.type),
                    size: 20, color: StrivoColors.navy),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    if (item.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: StrivoColors.muted),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      <String>[
                        item.type.label,
                        if (item.hasFile) item.fileName ?? 'Attachment',
                        if (item.fileSize != null) _fileSize(item.fileSize!),
                      ].join(' · '),
                      style: const TextStyle(
                          fontSize: 11, color: StrivoColors.muted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: StrivoColors.muted),
            ],
          ),
        ),
      ),
    );
  }

  void _openDetail(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          children: [
            Row(
              children: [
                Icon(_iconFor(item.type), color: StrivoColors.navy),
                const SizedBox(width: 8),
                Text(item.type.label,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 10),
            Text(item.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (item.description.isNotEmpty)
              Text(item.description,
                  style: const TextStyle(fontSize: 14, height: 1.5)),
            if (item.publishedAt != null) ...[
              const SizedBox(height: 14),
              Text('Posted ${_stamp(item.publishedAt!)}',
                  style:
                      const TextStyle(fontSize: 12, color: StrivoColors.muted)),
            ],
            const SizedBox(height: 22),
            if (item.hasFile)
              FilledButton.icon(
                onPressed: () => _openAttachment(sheetContext, item),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(item.fileName ?? 'Open'),
              )
            else
              const Text('No file attached to this item.',
                  style: TextStyle(fontSize: 13, color: StrivoColors.muted)),
          ],
        ),
      ),
    );
  }
}

/// Hands the attachment to the platform browser or viewer. Nothing is
/// downloaded into app storage, so a revoked link stops working immediately.
Future<void> _openAttachment(BuildContext context, ContentItem item) async {
  final url = Uri.tryParse(item.fileUrl ?? '');
  if (url == null || !url.hasScheme) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That file link is not usable.')),
      );
    }
    return;
  }
  final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open that file.')),
    );
  }
}

IconData _iconFor(ContentType type) => switch (type) {
      ContentType.article => Icons.article_outlined,
      ContentType.video => Icons.play_circle_outline,
      ContentType.document => Icons.description_outlined,
      ContentType.image => Icons.image_outlined,
    };

String _fileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _stamp(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${value.day} ${months[value.month - 1]} ${value.year}';
}
