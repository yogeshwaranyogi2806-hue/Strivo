import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/providers.dart';

class CoachHomePage extends ConsumerStatefulWidget {
  const CoachHomePage({super.key});

  @override
  ConsumerState<CoachHomePage> createState() => _CoachHomePageState();
}

class _CoachHomePageState extends ConsumerState<CoachHomePage> {
  int _selectedIndex = 0;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.space_dashboard_outlined),
      selectedIcon: Icon(Icons.space_dashboard),
      label: 'Overview',
    ),
    NavigationDestination(
      icon: Icon(Icons.calendar_month_outlined),
      selectedIcon: Icon(Icons.calendar_month),
      label: 'Classes',
    ),
    NavigationDestination(
      icon: Icon(Icons.groups_outlined),
      selectedIcon: Icon(Icons.groups),
      label: 'Students',
    ),
    NavigationDestination(
      icon: Icon(Icons.grid_view_rounded),
      selectedIcon: Icon(Icons.grid_view_rounded),
      label: 'More',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [
      const _OverviewPage(),
      const _FeaturePage(
        title: 'Classes',
        description: 'Organize coaching groups and session schedules.',
        icon: Icons.calendar_month_outlined,
      ),
      const _FeaturePage(
        title: 'Students',
        description: 'Keep each learner connected to their coaching group.',
        icon: Icons.groups_outlined,
      ),
      const _MorePage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const _AppBrand(),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async {
              await ref.read(supabaseClientProvider)!.auth.signOut();
              if (context.mounted) context.go('/login');
            },
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        destinations: _destinations,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
      ),
    );
  }
}

class _OverviewPage extends StatelessWidget {
  const _OverviewPage();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Text('Coach workspace',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: StrivoColors.deepNavy,
                  fontWeight: FontWeight.w800,
                )),
        const SizedBox(height: 7),
        Text(
          'Measure development through the skills your coaches observe.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: StrivoColors.muted,
                height: 1.45,
              ),
        ),
        const SizedBox(height: 24),
        const _WorkspaceSetupCard(),
        const SizedBox(height: 24),
        Text('Your coaching tools',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                )),
        const SizedBox(height: 12),
        const _FeatureLine(
          icon: Icons.fact_check_outlined,
          title: 'Assessments',
          description: 'Record skill ratings and coach observations.',
        ),
        const _FeatureLine(
          icon: Icons.insights_outlined,
          title: 'Progress',
          description: 'Follow skill development over time.',
        ),
        const _FeatureLine(
          icon: Icons.how_to_reg_outlined,
          title: 'Attendance',
          description: 'Keep a clear record of session attendance.',
        ),
      ],
    );
  }
}

class _WorkspaceSetupCard extends ConsumerStatefulWidget {
  const _WorkspaceSetupCard();

  @override
  ConsumerState<_WorkspaceSetupCard> createState() => _WorkspaceSetupCardState();
}

class _WorkspaceSetupCardState extends ConsumerState<_WorkspaceSetupCard> {
  bool _busy = false;
  String? _error;

  Future<void> _createWorkspace() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create your coaching workspace'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Studio or academy name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(supabaseClientProvider)!.rpc(
        'create_coach_workspace',
        params: {'workspace_name': name},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Workspace created.')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not create the workspace. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.add_business_outlined,
                color: StrivoColors.coral, size: 24),
            const SizedBox(height: 14),
            Text('Set up your studio',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    )),
            const SizedBox(height: 6),
            Text(
              'Create a private workspace for your classes, students, and coaching records.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: StrivoColors.muted,
                    height: 1.5,
                  ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _busy ? null : _createWorkspace,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add),
              label: const Text('Create workspace'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MorePage extends StatelessWidget {
  const _MorePage();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Development',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: StrivoColors.deepNavy,
                  fontWeight: FontWeight.w800,
                )),
        const SizedBox(height: 16),
        const _FeatureLine(
          icon: Icons.tune,
          title: 'Skill library',
          description: 'Define the capabilities your coaches assess.',
        ),
        const _FeatureLine(
          icon: Icons.fact_check_outlined,
          title: 'Assessments',
          description: 'Rate skills and add observations.',
        ),
        const _FeatureLine(
          icon: Icons.insights_outlined,
          title: 'Progress',
          description: 'Review development by student and skill.',
        ),
        const _FeatureLine(
          icon: Icons.how_to_reg_outlined,
          title: 'Attendance',
          description: 'Mark attendance for a class session.',
        ),
      ],
    );
  }
}

class _FeaturePage extends StatelessWidget {
  const _FeaturePage({
    required this.title,
    required this.description,
    required this.icon,
  });

  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: StrivoColors.navy, size: 36),
            const SizedBox(height: 14),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: StrivoColors.muted,
                    )),
            const SizedBox(height: 16),
            const Text('This coach workflow is next in the implementation sequence.'),
          ],
        ),
      ),
    );
  }
}

class _FeatureLine extends StatelessWidget {
  const _FeatureLine({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(icon, color: StrivoColors.navy),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(description),
    );
  }
}

class _AppBrand extends StatelessWidget {
  const _AppBrand();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.all_inclusive_rounded,
            color: StrivoColors.coral, size: 25),
        const SizedBox(width: 7),
        Text('Strivo',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: StrivoColors.deepNavy,
                  fontWeight: FontWeight.w800,
                )),
      ],
    );
  }
}