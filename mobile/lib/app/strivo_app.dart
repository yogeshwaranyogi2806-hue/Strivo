import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import 'router.dart';
import 'theme.dart';

class StrivoApp extends ConsumerWidget {
  const StrivoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    final theme = buildStrivoTheme();

    if (client == null) {
      return MaterialApp(
        title: 'Strivo',
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: const ConfigurationRequiredPage(),
      );
    }

    return MaterialApp.router(
      title: 'Strivo',
      debugShowCheckedModeBanner: false,
      theme: theme,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

class ConfigurationRequiredPage extends StatelessWidget {
  const ConfigurationRequiredPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _BrandMark(),
                  const SizedBox(height: 28),
                  Text('Connect your Strivo workspace',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 10),
                  Text(
                    'Add your Supabase project URL and publishable key when launching the app.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: StrivoColors.muted,
                          height: 1.5,
                        ),
                  ),
                  const SizedBox(height: 18),
                  const SelectableText(
                    'SUPABASE_URL\nSUPABASE_ANON_KEY',
                    style: TextStyle(
                      color: StrivoColors.navy,
                      fontFamily: 'monospace',
                      height: 1.7,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.all_inclusive_rounded,
            color: StrivoColors.coral, size: 32),
        const SizedBox(width: 8),
        Text('Strivo',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: StrivoColors.deepNavy,
                  fontWeight: FontWeight.w800,
                )),
      ],
    );
  }
}
