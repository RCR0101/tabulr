import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';
import '../services/secure_logger.dart';

/// State class for authentication
class AuthState {
  final bool isAuthenticated;
  final bool isGuest;
  final bool isLoading;
  final String? error;
  final String? userEmail;

  const AuthState({
    this.isAuthenticated = false,
    this.isGuest = false,
    this.isLoading = false,
    this.error,
    this.userEmail,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isGuest,
    bool? isLoading,
    String? error,
    String? userEmail,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isGuest: isGuest ?? this.isGuest,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      userEmail: userEmail ?? this.userEmail,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthState &&
          runtimeType == other.runtimeType &&
          isAuthenticated == other.isAuthenticated &&
          isGuest == other.isGuest &&
          isLoading == other.isLoading &&
          error == other.error &&
          userEmail == other.userEmail;

  @override
  int get hashCode =>
      isAuthenticated.hashCode ^
      isGuest.hashCode ^
      isLoading.hashCode ^
      error.hashCode ^
      userEmail.hashCode;
}

/// Auth service provider
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

/// Auth state notifier
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._authService) : super(const AuthState()) {
    _initialize();
  }

  final AuthService _authService;

  Future<void> _initialize() async {
    state = state.copyWith(isLoading: true);
    
    try {
      await _authService.initialize();
      _updateAuthState();
      
      // Listen to auth changes
      _authService.authStateChanges.listen((_) {
        _updateAuthState();
      });
    } catch (error) {
      SecureLogger.error('AUTH', 'Failed to initialize auth service', error);
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to initialize authentication',
      );
    }
  }

  void _updateAuthState() {
    state = state.copyWith(
      isAuthenticated: _authService.isAuthenticated,
      isGuest: _authService.isGuest,
      isLoading: false,
      error: null,
      userEmail: _authService.currentUser?.email,
    );
  }

  /// Sign in with Google
  Future<bool> signInWithGoogle() async {
    state = state.copyWith(isLoading: true, error: null);
    
    try {
      final userCredential = await _authService.signInWithGoogle();
      final success = userCredential != null;
      
      SecureLogger.authEvent(
        success ? 'Google sign-in successful' : 'Google sign-in cancelled',
        {'success': success},
      );
      
      _updateAuthState();
      return success;
    } catch (error) {
      SecureLogger.error('AUTH', 'Google sign-in failed', error);
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to sign in with Google',
      );
      return false;
    }
  }

  /// Sign in as guest
  Future<bool> signInAsGuest() async {
    state = state.copyWith(isLoading: true, error: null);
    
    try {
      await _authService.signInAsGuest();
      
      SecureLogger.authEvent('Guest mode activated');
      
      _updateAuthState();
      return true;
    } catch (error) {
      SecureLogger.error('AUTH', 'Guest sign-in failed', error);
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to continue as guest',
      );
      return false;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    state = state.copyWith(isLoading: true);
    
    try {
      await _authService.signOut();
      
      SecureLogger.authEvent('User signed out');
      
      _updateAuthState();
    } catch (error) {
      SecureLogger.error('AUTH', 'Sign out failed', error);
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to sign out',
      );
    }
  }

  /// Clear error
  void clearError() {
    state = state.copyWith(error: null);
  }
}

/// Main auth state provider
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  return AuthNotifier(authService);
});

/// Convenience providers
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isAuthenticated;
});

final isGuestProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isGuest;
});

final isLoadingProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isLoading;
});

final authErrorProvider = Provider<String?>((ref) {
  return ref.watch(authProvider).error;
});

final userEmailProvider = Provider<String?>((ref) {
  return ref.watch(authProvider).userEmail;
});