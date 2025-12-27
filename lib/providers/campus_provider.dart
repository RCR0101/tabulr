import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/campus_service.dart';
import '../services/secure_logger.dart';

/// Campus state class
class CampusState {
  final Campus currentCampus;
  final bool isLoading;
  final String? error;

  const CampusState({
    required this.currentCampus,
    this.isLoading = false,
    this.error,
  });

  CampusState copyWith({
    Campus? currentCampus,
    bool? isLoading,
    String? error,
  }) {
    return CampusState(
      currentCampus: currentCampus ?? this.currentCampus,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CampusState &&
          runtimeType == other.runtimeType &&
          currentCampus == other.currentCampus &&
          isLoading == other.isLoading &&
          error == other.error;

  @override
  int get hashCode =>
      currentCampus.hashCode ^ isLoading.hashCode ^ error.hashCode;
}

/// Campus service provider
final campusServiceProvider = Provider<CampusService>((ref) {
  return CampusService();
});

/// Campus state notifier
class CampusNotifier extends StateNotifier<CampusState> {
  CampusNotifier()
      : super(CampusState(
          currentCampus: CampusService.currentCampus,
        )) {
    _initialize();
  }

  Future<void> _initialize() async {
    state = state.copyWith(isLoading: true);
    
    try {
      await CampusService.initializeCampus();
      
      state = state.copyWith(
        currentCampus: CampusService.currentCampus,
        isLoading: false,
        error: null,
      );
      
      SecureLogger.info('CAMPUS', 'Campus service initialized', {
        'current_campus': CampusService.getCampusDisplayName(CampusService.currentCampus),
      });
    } catch (error) {
      SecureLogger.error('CAMPUS', 'Failed to initialize campus service', error);
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to initialize campus',
      );
    }
  }

  /// Set campus
  Future<void> setCampus(Campus campus) async {
    state = state.copyWith(isLoading: true, error: null);
    
    try {
      await CampusService.setCampus(campus);
      
      state = state.copyWith(
        currentCampus: campus,
        isLoading: false,
      );
      
      SecureLogger.userAction('Campus changed', {
        'campus': CampusService.getCampusDisplayName(campus),
      });
    } catch (error) {
      SecureLogger.error('CAMPUS', 'Failed to set campus', error);
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to set campus',
      );
    }
  }

  /// Get campus display name
  String getCampusDisplayName() {
    return CampusService.getCampusDisplayName(state.currentCampus);
  }

  /// Get available campuses
  List<Campus> getAvailableCampuses() {
    return Campus.values;
  }

  /// Clear error
  void clearError() {
    state = state.copyWith(error: null);
  }
}

/// Main campus provider
final campusProvider = StateNotifierProvider<CampusNotifier, CampusState>((ref) {
  return CampusNotifier();
});

/// Convenience providers
final currentCampusProvider = Provider<Campus>((ref) {
  return ref.watch(campusProvider).currentCampus;
});

final campusDisplayNameProvider = Provider<String>((ref) {
  final campus = ref.watch(campusProvider).currentCampus;
  return CampusService.getCampusDisplayName(campus);
});

final campusLoadingProvider = Provider<bool>((ref) {
  return ref.watch(campusProvider).isLoading;
});

final campusErrorProvider = Provider<String?>((ref) {
  return ref.watch(campusProvider).error;
});

final availableCampusesProvider = Provider<List<Campus>>((ref) {
  return Campus.values;
});