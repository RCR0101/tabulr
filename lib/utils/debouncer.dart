import 'dart:async';
import 'dart:ui';

/// Collapses a burst of calls into a single deferred one — the last call within
/// [duration] wins.
///
/// Replaces the `Timer? _debounce; _debounce?.cancel(); _debounce = Timer(...)`
/// boilerplate that was copy-pasted across five search and admin screens, each
/// re-deriving the same cancel-and-reschedule dance. The duration stays a
/// per-site choice (search fields debounce tighter than admin reloads), so this
/// only removes the plumbing, not the tuning.
///
/// Always call [dispose] from the owner's `dispose()` so a pending callback
/// cannot fire after the widget is gone.
class Debouncer {
  Debouncer({this.duration = const Duration(milliseconds: 300)});

  final Duration duration;
  Timer? _timer;

  /// Schedules [action], cancelling any call still waiting.
  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  /// Drops a pending call without running it.
  void cancel() => _timer?.cancel();

  bool get isActive => _timer?.isActive ?? false;

  void dispose() => _timer?.cancel();
}
