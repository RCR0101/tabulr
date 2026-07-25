import 'package:flutter/material.dart';
import '../../services/ui/secure_logger.dart';
import 'shimmer_loading.dart';

/// Loads a `deferred as` library before building the screen inside it.
///
/// On web the compiler emits a separate part file, fetched only when
/// [loadLibrary] is first awaited — worth it for anything large that most
/// sessions never open. The runtime caches the load, so a second visit to a
/// deferred screen resolves immediately and shows no loading state.
class DeferredScreen extends StatefulWidget {
  /// The generated `loadLibrary` of the deferred import.
  final Future<void> Function() load;

  /// Called only once [load] completes, so it may reference deferred types.
  final Widget Function() builder;

  /// Shown while the part file is in flight; defaults to the app's skeleton.
  final Widget? placeholder;

  const DeferredScreen({
    super.key,
    required this.load,
    required this.builder,
    this.placeholder,
  });

  @override
  State<DeferredScreen> createState() => _DeferredScreenState();
}

class _DeferredScreenState extends State<DeferredScreen> {
  late Future<void> _future;

  @override
  void initState() {
    super.initState();
    // In initState, not build: a Future made in build re-fires every rebuild.
    _future = widget.load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return widget.placeholder ??
              const Scaffold(body: TimetableListSkeleton());
        }
        if (snapshot.hasError) {
          SecureLogger.error(
              'DEFERRED', 'Failed to load deferred screen', snapshot.error);
          return _DeferredLoadFailed(onRetry: () {
            setState(() => _future = widget.load());
          });
        }
        return widget.builder();
      },
    );
  }
}

/// A part file can fail to load on a flaky connection, or when a deploy has
/// replaced the file the running bundle expects. Retrying re-requests it.
class _DeferredLoadFailed extends StatelessWidget {
  final VoidCallback onRetry;

  const _DeferredLoadFailed({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined,
                  size: 40, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text("Couldn't load this section",
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Check your connection and try again.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}
