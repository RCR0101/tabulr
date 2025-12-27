import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import '../models/course.dart';

part 'search_filter_provider.freezed.dart';

/// State class for search and filter functionality
@freezed
class SearchFilterState with _$SearchFilterState {
  const factory SearchFilterState({
    @Default('') String searchQuery,
    @Default('') String instructor,
    @Default('') String courseCode,
    DateTime? midSemDate,
    DateTime? endSemDate,
    int? minCredits,
    int? maxCredits,
    @Default([]) List<DayOfWeek> selectedDays,
    @Default(false) bool showAdvancedFilters,
  }) = _SearchFilterState;
}

/// Main search filter provider
final searchFilterProvider = StateNotifierProvider<SearchFilterNotifier, SearchFilterState>((ref) {
  return SearchFilterNotifier();
});

/// Provider for filtered courses based on search and filters
final filteredCoursesProvider = Provider.family<List<Course>, List<Course>>((ref, allCourses) {
  final filterState = ref.watch(searchFilterProvider);
  return _applyFilters(allCourses, filterState);
});

/// Convenience providers for individual filter states
final searchQueryProvider = Provider<String>((ref) {
  return ref.watch(searchFilterProvider).searchQuery;
});

final instructorFilterProvider = Provider<String>((ref) {
  return ref.watch(searchFilterProvider).instructor;
});

final courseCodeFilterProvider = Provider<String>((ref) {
  return ref.watch(searchFilterProvider).courseCode;
});

final showAdvancedFiltersProvider = Provider<bool>((ref) {
  return ref.watch(searchFilterProvider).showAdvancedFilters;
});

final hasActiveFiltersProvider = Provider<bool>((ref) {
  final state = ref.watch(searchFilterProvider);
  return state.searchQuery.isNotEmpty ||
         state.instructor.isNotEmpty ||
         state.courseCode.isNotEmpty ||
         state.midSemDate != null ||
         state.endSemDate != null ||
         state.minCredits != null ||
         state.maxCredits != null ||
         state.selectedDays.isNotEmpty;
});

/// Search filter state notifier
class SearchFilterNotifier extends StateNotifier<SearchFilterState> {
  SearchFilterNotifier() : super(const SearchFilterState());

  /// Update search query
  void updateSearchQuery(String query) {
    state = state.copyWith(searchQuery: query.trim());
  }

  /// Update instructor filter
  void updateInstructor(String instructor) {
    state = state.copyWith(instructor: instructor.trim());
  }

  /// Update course code filter
  void updateCourseCode(String courseCode) {
    state = state.copyWith(courseCode: courseCode.trim());
  }

  /// Update mid-sem exam date filter
  void updateMidSemDate(DateTime? date) {
    state = state.copyWith(midSemDate: date);
  }

  /// Update end-sem exam date filter
  void updateEndSemDate(DateTime? date) {
    state = state.copyWith(endSemDate: date);
  }

  /// Update credit range filters
  void updateCreditRange({int? minCredits, int? maxCredits}) {
    state = state.copyWith(
      minCredits: minCredits,
      maxCredits: maxCredits,
    );
  }

  /// Update selected days filter
  void updateSelectedDays(List<DayOfWeek> days) {
    state = state.copyWith(selectedDays: [...days]);
  }

  /// Add a day to selected days
  void addSelectedDay(DayOfWeek day) {
    if (!state.selectedDays.contains(day)) {
      final newDays = [...state.selectedDays, day];
      state = state.copyWith(selectedDays: newDays);
    }
  }

  /// Remove a day from selected days
  void removeSelectedDay(DayOfWeek day) {
    final newDays = state.selectedDays.where((d) => d != day).toList();
    state = state.copyWith(selectedDays: newDays);
  }

  /// Toggle day selection
  void toggleDay(DayOfWeek day) {
    if (state.selectedDays.contains(day)) {
      removeSelectedDay(day);
    } else {
      addSelectedDay(day);
    }
  }

  /// Toggle advanced filters visibility
  void toggleAdvancedFilters() {
    state = state.copyWith(showAdvancedFilters: !state.showAdvancedFilters);
  }

  /// Set advanced filters visibility
  void setShowAdvancedFilters(bool show) {
    state = state.copyWith(showAdvancedFilters: show);
  }

  /// Clear all filters and search
  void clearAll() {
    state = const SearchFilterState();
  }

  /// Clear only advanced filters, keep basic search
  void clearAdvancedFilters() {
    state = state.copyWith(
      instructor: '',
      courseCode: '',
      midSemDate: null,
      endSemDate: null,
      minCredits: null,
      maxCredits: null,
      selectedDays: [],
    );
  }

  /// Update multiple filters at once
  void updateFilters({
    String? searchQuery,
    String? instructor,
    String? courseCode,
    DateTime? midSemDate,
    DateTime? endSemDate,
    int? minCredits,
    int? maxCredits,
    List<DayOfWeek>? selectedDays,
  }) {
    state = state.copyWith(
      searchQuery: searchQuery ?? state.searchQuery,
      instructor: instructor ?? state.instructor,
      courseCode: courseCode ?? state.courseCode,
      midSemDate: midSemDate,
      endSemDate: endSemDate,
      minCredits: minCredits,
      maxCredits: maxCredits,
      selectedDays: selectedDays ?? state.selectedDays,
    );
  }
}

/// Helper function to apply filters to courses
List<Course> _applyFilters(List<Course> courses, SearchFilterState filterState) {
  List<Course> filtered = courses;

  // Apply search query filter
  if (filterState.searchQuery.isNotEmpty) {
    final query = filterState.searchQuery.toLowerCase();
    filtered = filtered.where((course) {
      return course.courseCode.toLowerCase().contains(query) ||
             course.courseTitle.toLowerCase().contains(query) ||
             course.sections.any((section) => 
                 section.instructor.toLowerCase().contains(query));
    }).toList();
  }

  // Apply instructor filter
  if (filterState.instructor.isNotEmpty) {
    final instructorQuery = filterState.instructor.toLowerCase();
    filtered = filtered.where((course) {
      return course.sections.any((section) => 
          section.instructor.toLowerCase().contains(instructorQuery));
    }).toList();
  }

  // Apply course code filter
  if (filterState.courseCode.isNotEmpty) {
    final codeQuery = filterState.courseCode.toLowerCase();
    filtered = filtered.where((course) {
      return course.courseCode.toLowerCase().contains(codeQuery);
    }).toList();
  }

  // Apply credit range filters
  if (filterState.minCredits != null) {
    filtered = filtered.where((course) {
      return course.totalCredits >= filterState.minCredits!;
    }).toList();
  }

  if (filterState.maxCredits != null) {
    filtered = filtered.where((course) {
      return course.totalCredits <= filterState.maxCredits!;
    }).toList();
  }

  // Apply selected days filter
  if (filterState.selectedDays.isNotEmpty) {
    filtered = filtered.where((course) {
      return course.sections.any((section) {
        return section.schedule.any((scheduleEntry) {
          return scheduleEntry.days.any((day) => 
              filterState.selectedDays.contains(day));
        });
      });
    }).toList();
  }

  // Apply exam date filters
  if (filterState.midSemDate != null) {
    filtered = filtered.where((course) {
      return course.midSemExam?.date != null &&
             _isSameDate(course.midSemExam!.date, filterState.midSemDate!);
    }).toList();
  }

  if (filterState.endSemDate != null) {
    filtered = filtered.where((course) {
      return course.endSemExam?.date != null &&
             _isSameDate(course.endSemExam!.date, filterState.endSemDate!);
    }).toList();
  }

  return filtered;
}

/// Helper function to compare dates (ignoring time)
bool _isSameDate(DateTime date1, DateTime date2) {
  return date1.year == date2.year &&
         date1.month == date2.month &&
         date1.day == date2.day;
}