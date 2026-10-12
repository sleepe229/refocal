import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../bootstrap/engine.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _picking = false;

  Future<void> _pick() async {
    final engine = await ref.read(engineProvider.future);
    setState(() => _picking = true);
    try {
      final picked = await ref.read(platformApiProvider).pickImage(engine.inboxDir);
      if (picked != null && mounted) context.push('/editor', extra: picked.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not open the photo: $e')));
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final engine = ref.watch(engineProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Refocal')),
      body: Center(
        child: engine.when(
          loading: () => const CircularProgressIndicator(),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Native core unavailable: $e'),
          ),
          data: (e) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_fix_high, size: 64),
                const SizedBox(height: 16),
                Text(
                  'Bring your photos back into focus.',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Everything runs on this phone. Photos never leave it.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (!e.modelReady)
                  const Text(
                    'The enhancement model is missing from this build.',
                    style: TextStyle(color: Colors.red),
                  )
                else
                  FilledButton.icon(
                    onPressed: _picking ? null : _pick,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Choose a photo'),
                  ),
                const SizedBox(height: 24),
                Text('Core ${e.native.version}', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
