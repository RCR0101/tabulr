import 'package:flutter/material.dart';
import '../services/data/auth_service.dart';
import '../services/ui/toast_service.dart';
import '../utils/design_constants.dart';
import '../widgets/disclaimer_widget.dart';
import '../widgets/error_dialog.dart';

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
  _AuthAction? _activeAction;

  bool get _isLoading => _activeAction != null;

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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 200,
                    maxHeight: 200,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'images/full_logo_bg.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ).motionEntry(duration: AppDesign.motionEmphasized),
                const SizedBox(height: 16),
                Text(
                  'Create and manage your class timetables',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ).motionFadeIn(delay: const Duration(milliseconds: 200)),
                const SizedBox(height: 48),
                Semantics(
                  label: 'Sign in with Google',
                  button: true,
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton.icon(
                      key: const ValueKey('google-sign-in-button'),
                      onPressed: _isLoading ? null : _signInWithGoogle,
                      icon:
                          _activeAction == _AuthAction.google
                              ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.login),
                      label: Text(
                        _activeAction == _AuthAction.google
                            ? 'Signing in...'
                            : 'Sign in with Google',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: AppDesign.cardBorderRadius(context),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.star_rounded,
                            color: Theme.of(context).colorScheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Why sign in?',
                            style: Theme.of(
                              context,
                            ).textTheme.titleSmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '• CGPA calculator & acad drives\n'
                        '• Find exam seating & professor details\n'
                        '• Share timetables & sync across devices',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: Divider(
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withValues(alpha: 0.5),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'OR',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Divider(
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Semantics(
                  label: 'Continue as Guest',
                  button: true,
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton.icon(
                      key: const ValueKey('guest-sign-in-button'),
                      onPressed: _isLoading ? null : _continueAsGuest,
                      icon:
                          _activeAction == _AuthAction.guest
                              ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.person_outline),
                      label: Text(
                        _activeAction == _AuthAction.guest
                            ? 'Opening Tabulr...'
                            : 'Continue as Guest',
                        style: const TextStyle(fontSize: 16),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const GuestModeDisclaimerWidget(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
