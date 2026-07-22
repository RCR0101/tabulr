import 'package:flutter/material.dart';
import '../services/ui/toast_service.dart';

/// Full-screen "Tabulr is down" state shown by the maintenance kill switch.
///
/// Purely presentational: it takes the message to display and a retry callback.
/// The decision to show it lives in the root gate (see `MaintenanceGate`).
class MaintenanceScreen extends StatefulWidget {
  final String message;

  /// Invoked when the user taps "Try again". Should re-check the kill switch
  /// and return whether the app is now available.
  final Future<bool> Function() onRetry;

  const MaintenanceScreen({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  bool _checking = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The maintenance gate renders this screen *instead of* the app shell,
    // which is where ToastService is normally initialized. Wire it to this
    // screen's overlay so retry feedback can surface here too.
    ToastService.init(context);
  }

  Future<void> _retry() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final available = await widget.onRetry();
      if (!available && mounted) {
        ToastService.showWarning('Still down — please check back later.');
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off_rounded,
                  size: 64,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(height: 24),
                Text(
                  'Tabulr is down',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  widget.message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: _checking ? null : _retry,
                  icon: _checking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  label: Text(_checking ? 'Checking…' : 'Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
