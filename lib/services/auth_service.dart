import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'config_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final ConfigService _config = ConfigService();
  late final GoogleSignIn _googleSignIn;
  
  // Session-only guest mode tracker (not persisted)
  bool _isCurrentlyGuest = false;
  
  // Stream controller for auth state changes including guest mode
  final StreamController<bool> _authStateController = StreamController<bool>.broadcast();
  
  User? get currentUser => _firebaseAuth.currentUser;
  bool get isAuthenticated => _firebaseAuth.currentUser != null;
  bool get isGuest => _isCurrentlyGuest && !isAuthenticated;
  bool get hasChosenAuthMethod => isAuthenticated || _isCurrentlyGuest;
  
  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();
  Stream<bool> get authMethodChosenStream => _authStateController.stream;

  // Initialize the service
  Future<void> initialize() async {
    try {
      // Validate Google Web Client ID for web
      if (kIsWeb && !_config.isValidConfiguration) {
        throw Exception('Invalid configuration. Missing: GOOGLE_WEB_CLIENT_ID');
      }

      // Initialize GoogleSignIn with web client ID if on web
      if (kIsWeb) {
        _googleSignIn = GoogleSignIn(
          clientId: _config.googleWebClientId,
        );
      } else {
        _googleSignIn = GoogleSignIn();
      }

      // Print configuration in debug mode
      _config.printConfiguration();

      // Initialize SharedPreferences for web compatibility
      if (kIsWeb) {
        try {
          SharedPreferences.setMockInitialValues({});
        } catch (e) {
          print('SharedPreferences mock already set or not needed: $e');
        }
        
        // Check for redirect result on web
        try {
          final redirectResult = await _firebaseAuth.getRedirectResult();
          if (redirectResult.user != null) {
            print('Google Sign-In redirect successful for user: ${redirectResult.user!.email}');
            // Store auth preference
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('is_authenticated', true);
            await prefs.remove('is_guest');
          } else {
            print('No redirect result found');
          }
        } catch (e) {
          print('No redirect result or error: $e');
        }
      }

      // Check if user was previously authenticated
      final prefs = await SharedPreferences.getInstance();
      final wasAuthenticated = prefs.getBool('is_authenticated') ?? false;
      
      // Wait a moment for Firebase to initialize properly
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Check current Firebase auth state
      if (currentUser != null) {
        print('Current user found: ${currentUser!.email}');
        if (!wasAuthenticated) {
          // User is signed in but not marked as authenticated in our app
          print('Marking user as authenticated in preferences');
          await prefs.setBool('is_authenticated', true);
        }
      } else {
        print('No current user found');
        if (wasAuthenticated) {
          // Clear stale auth preference
          await prefs.remove('is_authenticated');
        }
      }
    } catch (e) {
      print('Error initializing AuthService: $e');
    }
  }

  Future<UserCredential?> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        // Web authentication - use redirect method which is more reliable
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        
        // Add scopes
        googleProvider.addScope('email');
        googleProvider.addScope('profile');
        googleProvider.setCustomParameters({
          'prompt': 'select_account',
        });
        
        UserCredential? userCredential;
        
        try {
          // Try popup first (more reliable for testing)
          print('Starting Google Sign-In popup...');
          userCredential = await _firebaseAuth.signInWithPopup(googleProvider);
          
          if (userCredential?.user == null) {
            return null;
          }
          
          print('Google Sign-In popup successful for user: ${userCredential!.user!.email}');
          
          // Store auth preference
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('is_authenticated', true);
          await prefs.remove('is_guest');
          
          return userCredential;
        } catch (popupError) {
          print('Popup sign-in failed: $popupError');
          
          // If popup fails, try redirect
          try {
            print('Trying redirect fallback...');
            await _firebaseAuth.signInWithRedirect(googleProvider);
            
            // The app will reload after redirect, so this won't execute
            // The redirect result will be handled in the initialize method
            return null;
          } catch (redirectError) {
            print('Redirect also failed: $redirectError');
            throw Exception('Google Sign-In failed. Please ensure this domain is authorized in Firebase Console and try again.');
          }
        }
      } else {
        // Mobile authentication
        final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
        if (googleUser == null) {
          return null; // User cancelled the sign-in
        }

        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        final userCredential = await _firebaseAuth.signInWithCredential(credential);
        
        // Store auth preference
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_authenticated', true);
        await prefs.remove('is_guest');
        
        return userCredential;
      }
    } catch (e) {
      print('Error signing in with Google: $e');
      // Return more specific error information
      if (e.toString().contains('popup')) {
        throw Exception('Sign-in popup was blocked. Please allow popups for this site and try again.');
      } else if (e.toString().contains('network')) {
        throw Exception('Network error. Please check your internet connection and try again.');
      } else {
        throw Exception('Sign-in failed: ${e.toString()}');
      }
    }
  }

  Future<void> signInAsGuest() async {
    try {
      // Set session-only guest mode (not persisted across app restarts)
      _isCurrentlyGuest = true;
      
      // Clear any existing auth preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('is_authenticated');
      await prefs.remove('is_guest');
      
      // Notify listeners that auth method has been chosen
      _authStateController.add(true);
      
      print('Guest mode activated for this session only');
    } catch (e) {
      print('Error setting guest mode: $e');
    }
  }

  Future<void> signOut() async {
    try {
      // Reset guest mode
      _isCurrentlyGuest = false;
      
      // Notify listeners about auth state change
      _authStateController.add(false);
      
      // Sign out from Google (only for mobile)
      if (!kIsWeb) {
        await _googleSignIn.signOut();
      }
      
      // Sign out from Firebase
      await _firebaseAuth.signOut();
      
      // Clear session guest mode
      _isCurrentlyGuest = false;
      
      // Clear preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('is_authenticated');
      await prefs.remove('is_guest');
      
      print('User signed out successfully');
    } catch (e) {
      print('Error signing out: $e');
    }
  }

  Future<bool> isGuestMode() async {
    // Return the current session guest mode status
    return _isCurrentlyGuest;
  }

  String? get userEmail => currentUser?.email;
  String? get userName => currentUser?.displayName;
  String? get userPhotoUrl => currentUser?.photoURL;

  // Check if user has valid authentication state
  Future<bool> isValidAuthState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isAuthenticated = prefs.getBool('is_authenticated') ?? false;
      final isGuest = prefs.getBool('is_guest') ?? false;
      
      return isAuthenticated || isGuest;
    } catch (e) {
      print('Error checking auth state: $e');
      return false;
    }
  }

  // Clear all auth data
  Future<void> clearAuthData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('is_authenticated');
      await prefs.remove('is_guest');
    } catch (e) {
      print('Error clearing auth data: $e');
    }
  }
}