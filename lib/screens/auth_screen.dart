import 'dart:async';

import 'package:flutter/material.dart';
import '../services/data/auth_service.dart';
import '../services/ui/toast_service.dart';
import '../utils/design_constants.dart';
import '../widgets/disclaimer_widget.dart';
import '../widgets/error_dialog.dart';
import '../widgets/common/tabulr_surface.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.signInWithGoogle, this.continueAsGuest});

  final Future<AuthSignInResult> Function()? signInWithGoogle;
  final Future<void> Function()? continueAsGuest;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

enum _AuthAction { google, guest }

class _AuthScreenState extends State<AuthScreen> {
  final AuthService _authService = AuthService();
  StreamSubscription<void>? _authErrorSubscription;
  _AuthAction? _activeAction;

  bool get _isLoading => _activeAction != null;

  @override
  void initState() {
    super.initState();
    _authErrorSubscription = _authService.authErrorEvents.listen((_) {
      _showPendingRedirectError();
    });
    _showPendingRedirectError();
  }

  void _showPendingRedirectError() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final error = _authService.takePendingAuthError();
      if (error != null) _showErrorDialog(error.message, translate: false);
    });
  }

  @override
  void dispose() {
    _authErrorSubscription?.cancel();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    if (_isLoading) return;
    setState(() => _activeAction = _AuthAction.google);

    try {
      final result =
          await (widget.signInWithGoogle ?? _authService.signInWithGoogle)();
      switch (result) {
        case AuthSignInResult.signedIn:
          // AuthWrapper completes account setup before showing the app.
          break;
        case AuthSignInResult.cancelled:
          ToastService.showInfo('Sign-in cancelled.');
          break;
        case AuthSignInResult.redirecting:
          // The browser is leaving this page; do not report a cancellation.
          break;
      }
    } catch (e) {
      final message =
          e is AuthFlowException
              ? e.message
              : 'Failed to sign in with Google. Please try again.';
      _showErrorDialog(message, translate: false);
    } finally {
      // On success AuthWrapper navigates away and disposes this screen before
      // the finally runs, so guard the rebuild.
      if (mounted) {
        setState(() => _activeAction = null);
      }
    }
  }

  Future<void> _continueAsGuest() async {
    if (_isLoading) return;
    setState(() => _activeAction = _AuthAction.guest);

    try {
      await (widget.continueAsGuest ?? _authService.signInAsGuest)();
      // Guest mode set, AuthWrapper will handle navigation
    } catch (e) {
      _showErrorDialog('Could not start guest mode. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _activeAction = null);
      }
    }
  }

  void _showErrorDialog(String message, {bool translate = true}) {
    ErrorDialog.show(context, message, translate: translate);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: ColoredBox(
        color: scheme.surfaceContainerLowest,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 860;
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: wide ? 40 : 14,
                  vertical: wide ? 44 : 24,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child:
                        wide
                            ? Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(child: _buildBrandStory()),
                                const SizedBox(width: 72),
                                SizedBox(width: 420, child: _buildAuthPanel()),
                              ],
                            )
                            : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildCompactBrand(),
                                const SizedBox(height: 26),
                                _buildAuthPanel(compact: true),
                              ],
                            ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBrandStory() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _logo(),
        const SizedBox(height: 42),
        Text(
          'Plan the semester.\nSee the whole week.',
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -1.1,
            height: 1.08,
          ),
        ),
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(
            'Timetables, academic progress, exams, and campus resources in one precise workspace.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.55,
            ),
          ),
        ),
        const SizedBox(height: 34),
        const _SchedulePreview(),
      ],
    ).motionEntry(duration: AppDesign.motionEmphasized);
  }

  Widget _buildCompactBrand() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _logo(),
        const SizedBox(height: 24),
        Text(
          'Your academic week,\nunder control.',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -.7,
            height: 1.12,
          ),
        ),
      ],
    ).motionEntry();
  }

  Widget _logo() {
    return SizedBox(
      width: 174,
      height: 58,
      child: Image.asset('images/full_logo_bg.png', fit: BoxFit.contain),
    );
  }

  Widget _buildAuthPanel({bool compact = false}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return TabulrSurface(
      level: compact ? TabulrSurfaceLevel.canvas : TabulrSurfaceLevel.raised,
      padding: EdgeInsets.all(compact ? 14 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Continue to Tabulr',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -.45,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Sign in to sync your plans, or explore locally as a guest.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 26),
          Semantics(
            label: 'Sign in with Google',
            button: true,
            child: SizedBox(
              height: 52,
              child: FilledButton.icon(
                key: const ValueKey('google-sign-in-button'),
                onPressed: _isLoading ? null : _signInWithGoogle,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                icon:
                    _activeAction == _AuthAction.google
                        ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.login_rounded),
                label: Text(
                  _activeAction == _AuthAction.google
                      ? 'Signing in...'
                      : 'Sign in with Google',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'YOUR WORKSPACE INCLUDES',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.05,
            ),
          ),
          const SizedBox(height: 12),
          _valueRow(Icons.view_week_outlined, 'Timetables and weekly planning'),
          _valueRow(Icons.school_outlined, 'Grades and degree progress'),
          _valueRow(Icons.event_seat_outlined, 'Exams and campus resources'),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(child: Divider(color: scheme.outlineVariant)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'or continue locally',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(child: Divider(color: scheme.outlineVariant)),
            ],
          ),
          const SizedBox(height: 22),
          Semantics(
            label: 'Continue as Guest',
            button: true,
            child: SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                key: const ValueKey('guest-sign-in-button'),
                onPressed: _isLoading ? null : _continueAsGuest,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                icon:
                    _activeAction == _AuthAction.guest
                        ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.person_outline_rounded),
                label: Text(
                  _activeAction == _AuthAction.guest
                      ? 'Opening Tabulr...'
                      : 'Continue as Guest',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const GuestModeDisclaimerWidget(),
        ],
      ),
    ).motionEntry(
      duration: AppDesign.motionEmphasized,
      delay: const Duration(milliseconds: 100),
    );
  }

  Widget _valueRow(IconData icon, String label) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 19, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _SchedulePreview extends StatelessWidget {
  const _SchedulePreview();

  static const _loads = <List<double>>[
    [0.05, 0.36, 0.62],
    [0.22, 0.52, 0.78],
    [0.08, 0.43, 0.7],
    [0.3, 0.6, 0.88],
    [0.14, 0.48, 0.74],
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const days = ['M', 'T', 'W', 'T', 'F'];

    return Semantics(
      label: 'Example balanced weekly timetable',
      image: true,
      child: TabulrSurface(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  'WEEK 04',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                const Spacer(),
                Text(
                  'Balanced load',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (var index = 0; index < days.length; index++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        days[index],
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SizedBox(
                        height: 24,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final width = constraints.maxWidth;
                            return Stack(
                              children: [
                                Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: scheme.surfaceContainer,
                                      borderRadius: AppDesign.borderRadiusXs,
                                    ),
                                  ),
                                ),
                                for (var slot = 0; slot < 3; slot++)
                                  Positioned(
                                    left: width * _loads[index][slot],
                                    width: width * (slot == 1 ? .17 : .12),
                                    top: 2,
                                    bottom: 2,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: AppDesign.timetableColors(
                                          context,
                                        )[(index + slot) %
                                            6].withValues(alpha: .82),
                                        borderRadius: AppDesign.borderRadiusXs,
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
