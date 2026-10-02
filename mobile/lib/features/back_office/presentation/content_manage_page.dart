import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme.dart';
import '../../../core/services/content_service.dart';

/// Coach-side content management. Create a draft, attach a link to material
/// hosted anywhere, then publish it to the student library.
class ContentManagePage extends StatefulWidget {
  const ContentManagePage({super.key});

  @override
  State<ContentManagePage> createState() => _ContentManagePageState();
}

class _ContentManagePageState extends State<ContentManagePage> {
  late Future<List<ContentItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = ContentService.allForCoach();
  }

  void _reload() => setState(() => _future = ContentService.allForCoach());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Content')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: FutureBuilder<List<ContentItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final error = snapshot.error;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  error is ContentException
                      ? error.message
                      : 'Could not load your content.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final items = snapshot.data ?? const <ContentItem>[];
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.video_library_outlined,
                        size: 34, color: StrivoColors.muted),
                    SizedBox(height: 12),
                    Text(
                      'Nothing here yet. Add a video, article or document and '
                      'publish it to your students.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              itemCount: items.length,
              itemBuilder: (context, index) => _CoachContentCard(
                item: items[index],
                onChanged: _reload,
              ),
            ),
          );
        },
      ),
    );
  }

  void _create() {
    final title = TextEditingController();
    final description = TextEditingController();
    final url = TextEditingController();
    var type = ContentType.video;
    var publish = true;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 18,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 18,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Add material',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 14),
                TextField(
                  controller: title,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: description,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Description (optional)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: url,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Link to the file or video',
                    helperText:
                        'Any public link. Uploaded files are not supported yet.',
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final option in ContentType.values)
                      ChoiceChip(
                        label: Text(option.label),
                        selected: type == option,
                        onSelected: (_) => setSheetState(() => type = option),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: publish,
                  onChanged: (value) => setSheetState(() => publish = value),
                  title: const Text('Publish to students now'),
                ),
                const SizedBox(height: 6),
                FilledButton(
                  onPressed: () async {
                    final parsed = Uri.tryParse(url.text.trim());
                    final hasLink = parsed != null && parsed.hasScheme;
                    try {
                      await ContentService.create(
                        title: title.text,
                        description: description.text,
                        type: type,
                        fileUrl: hasLink ? parsed.toString() : null,
                        publish: publish,
                      );
                      if (!sheetContext.mounted) return;
                      Navigator.of(sheetContext).pop();
                      _reload();
                    } on ContentException catch (error) {
                      if (!sheetContext.mounted) return;
                      ScaffoldMessenger.of(sheetContext)
                          .showSnackBar(SnackBar(content: Text(error.message)));
                    }
                  },
                  child: Text(publish ? 'Publish' : 'Save as draft'),
                ),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      title.dispose();
      description.dispose();
      url.dispose();
    });
  }
}

class _CoachContentCard extends StatelessWidget {
  const _CoachContentCard({required this.item, required this.onChanged});

  final ContentItem item;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _Tag(
                        label: item.type.label,
                        colour: StrivoColors.navy,
                      ),
                      const SizedBox(width: 6),
                      _Tag(
                        label: item.isPublished ? 'Live' : 'Draft',
                        colour: item.isPublished
                            ? const Color(0xFF2E9E68)
                            : StrivoColors.muted,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Switch(
              value: item.isPublished,
              onChanged: (value) async {
                try {
                  await ContentService.setPublished(item.id, value);
                  onChanged();
                } on ContentException catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(error.message)));
                }
              },
            ),
            IconButton(
              tooltip: 'Copy link',
              icon: const Icon(Icons.link, size: 20),
              onPressed: item.hasFile
                  ? () {
                      Clipboard.setData(ClipboardData(text: item.fileUrl!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link copied.')),
                      );
                    }
                  : null,
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => _confirmDelete(context, item, onChanged),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, ContentItem item, VoidCallback reload) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this item?'),
        content: Text(
          '"${item.title}" will be removed for everyone. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await ContentService.delete(item.id);
              } on ContentException catch (error) {
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(error.message)));
                return;
              }
              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop();
              reload();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.colour});

  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colour),
      ),
    );
  }
}
