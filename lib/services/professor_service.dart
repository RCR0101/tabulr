import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

enum ProfessorSortType {
  nameAsc,
  nameDesc,
  chamberAsc,
  chamberDesc,
}

/// Represents a single schedule entry for a professor's class
class ProfessorScheduleEntry {
  final String courseCode;
  final String courseTitle;
  final String sectionId;
  final String room;
  final List<String> days; // e.g., ['DayOfWeek.M', 'DayOfWeek.W']
  final List<int> hours; // e.g., [1, 2]

  ProfessorScheduleEntry({
    required this.courseCode,
    required this.courseTitle,
    required this.sectionId,
    required this.room,
    required this.days,
    required this.hours,
  });

  factory ProfessorScheduleEntry.fromJson(Map<String, dynamic> json) {
    return ProfessorScheduleEntry(
      courseCode: json['courseCode'] ?? '',
      courseTitle: json['courseTitle'] ?? '',
      sectionId: json['sectionId'] ?? '',
      room: json['room'] ?? '',
      days: List<String>.from(json['days'] ?? []),
      hours: List<int>.from(json['hours'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'courseCode': courseCode,
      'courseTitle': courseTitle,
      'sectionId': sectionId,
      'room': room,
      'days': days,
      'hours': hours,
    };
  }

  /// Get day abbreviations without the enum prefix
  List<String> get dayAbbreviations {
    return days.map((d) => d.replaceAll('DayOfWeek.', '')).toList();
  }

  /// Get formatted hour range string
  String get hourRangeString {
    if (hours.isEmpty) return '';

    const hourSlotNames = {
      1: '8:00-8:50 AM',
      2: '9:00-9:50 AM',
      3: '10:00-10:50 AM',
      4: '11:00-11:50 AM',
      5: '12:00-12:50 PM',
      6: '1:00-1:50 PM',
      7: '2:00-2:50 PM',
      8: '3:00-3:50 PM',
      9: '4:00-4:50 PM',
      10: '5:00-5:50 PM',
      11: '6:00-6:50 PM',
      12: '7:00-7:50 PM',
    };

    if (hours.length == 1) {
      return hourSlotNames[hours.first] ?? '';
    }

    final sortedHours = List<int>.from(hours)..sort();
    final startHour = sortedHours.first;
    final endHour = sortedHours.last;
    final startTime = hourSlotNames[startHour]?.split('-')[0] ?? '';
    final endTime = hourSlotNames[endHour]?.split('-')[1] ?? '';
    return '$startTime-$endTime';
  }

  /// Check if this schedule entry is happening at the given day and hour
  bool isAtDayAndHour(String dayAbbr, int hour) {
    final dayMatch = days.any((d) => d.replaceAll('DayOfWeek.', '') == dayAbbr);
    final hourMatch = hours.contains(hour);
    return dayMatch && hourMatch;
  }
}

class Professor {
  final String id;
  final String name;
  final String chamber;
  final List<ProfessorScheduleEntry> schedule;
  final DateTime createdAt;
  final DateTime updatedAt;

  Professor({
    required this.id,
    required this.name,
    required this.chamber,
    required this.schedule,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Professor.fromJson(Map<String, dynamic> json) {
    return Professor(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      chamber: json['chamber'] ?? 'Unavailable',
      schedule: (json['schedule'] as List<dynamic>?)
              ?.map((e) => ProfessorScheduleEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: json['createdAt'] is Timestamp
          ? (json['createdAt'] as Timestamp).toDate()
          : DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: json['updatedAt'] is Timestamp
          ? (json['updatedAt'] as Timestamp).toDate()
          : DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'chamber': chamber,
      'schedule': schedule.map((e) => e.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// Check if the professor is currently in a class
  bool isCurrentlyOccupied() {
    if (schedule.isEmpty) return false;

    final now = DateTime.now();
    final currentDayAbbr = _getDayAbbreviation(now.weekday);
    final currentHour = _getCurrentHourSlot(now);

    if (currentDayAbbr == null || currentHour == null) return false;

    return schedule.any((entry) => entry.isAtDayAndHour(currentDayAbbr, currentHour));
  }

  /// Get the current class info if professor is occupied
  ProfessorScheduleEntry? getCurrentClass() {
    if (schedule.isEmpty) return null;

    final now = DateTime.now();
    final currentDayAbbr = _getDayAbbreviation(now.weekday);
    final currentHour = _getCurrentHourSlot(now);

    if (currentDayAbbr == null || currentHour == null) return null;

    try {
      return schedule.firstWhere(
        (entry) => entry.isAtDayAndHour(currentDayAbbr, currentHour),
      );
    } catch (e) {
      return null;
    }
  }

  /// Get grouped schedule by day for display
  Map<String, List<ProfessorScheduleEntry>> getScheduleByDay() {
    final Map<String, List<ProfessorScheduleEntry>> grouped = {};

    for (final entry in schedule) {
      for (final day in entry.dayAbbreviations) {
        grouped.putIfAbsent(day, () => []);
        grouped[day]!.add(entry);
      }
    }

    // Sort entries within each day by hour
    for (final day in grouped.keys) {
      grouped[day]!.sort((a, b) {
        final aMinHour = a.hours.isEmpty ? 0 : a.hours.reduce((a, b) => a < b ? a : b);
        final bMinHour = b.hours.isEmpty ? 0 : b.hours.reduce((a, b) => a < b ? a : b);
        return aMinHour.compareTo(bMinHour);
      });
    }

    return grouped;
  }

  /// Convert weekday (1=Monday) to day abbreviation
  static String? _getDayAbbreviation(int weekday) {
    const dayMap = {
      1: 'M',
      2: 'T',
      3: 'W',
      4: 'Th',
      5: 'F',
      6: 'S',
    };
    return dayMap[weekday];
  }

  /// Get the current hour slot based on time
  static int? _getCurrentHourSlot(DateTime time) {
    final hour = time.hour;
    final minute = time.minute;
    final totalMinutes = hour * 60 + minute;

    // Hour slots:
    // 1: 8:00-8:50
    // 2: 9:00-9:50
    // 3: 10:00-10:50
    // 4: 11:00-11:50
    // 5: 12:00-12:50
    // 6: 13:00-13:50 (1:00 PM)
    // 7: 14:00-14:50 (2:00 PM)
    // 8: 15:00-15:50 (3:00 PM)
    // 9: 16:00-16:50 (4:00 PM)
    // 10: 17:00-17:50 (5:00 PM)
    // 11: 18:00-18:50 (6:00 PM)
    // 12: 19:00-19:50 (7:00 PM)

    if (totalMinutes >= 8 * 60 && totalMinutes < 8 * 60 + 50) return 1;
    if (totalMinutes >= 9 * 60 && totalMinutes < 9 * 60 + 50) return 2;
    if (totalMinutes >= 10 * 60 && totalMinutes < 10 * 60 + 50) return 3;
    if (totalMinutes >= 11 * 60 && totalMinutes < 11 * 60 + 50) return 4;
    if (totalMinutes >= 12 * 60 && totalMinutes < 12 * 60 + 50) return 5;
    if (totalMinutes >= 13 * 60 && totalMinutes < 13 * 60 + 50) return 6;
    if (totalMinutes >= 14 * 60 && totalMinutes < 14 * 60 + 50) return 7;
    if (totalMinutes >= 15 * 60 && totalMinutes < 15 * 60 + 50) return 8;
    if (totalMinutes >= 16 * 60 && totalMinutes < 16 * 60 + 50) return 9;
    if (totalMinutes >= 17 * 60 && totalMinutes < 17 * 60 + 50) return 10;
    if (totalMinutes >= 18 * 60 && totalMinutes < 18 * 60 + 50) return 11;
    if (totalMinutes >= 19 * 60 && totalMinutes < 19 * 60 + 50) return 12;

    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Professor &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Professor(id: $id, name: $name, chamber: $chamber, scheduleCount: ${schedule.length})';
}

class ProfessorService extends ChangeNotifier {
  static final ProfessorService _instance = ProfessorService._internal();
  factory ProfessorService() => _instance;
  ProfessorService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  List<Professor> _professors = [];
  List<Professor> _filteredProfessors = [];
  bool _isLoading = false;
  String? _error;
  String _searchQuery = '';
  ProfessorSortType _sortType = ProfessorSortType.nameAsc;

  List<Professor> get professors => _filteredProfessors;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get searchQuery => _searchQuery;
  ProfessorSortType get sortType => _sortType;

  /// Load all professors from Firestore
  Future<void> loadProfessors({bool forceRefresh = false}) async {
    if (_professors.isNotEmpty && !forceRefresh) {
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final snapshot = await _firestore
          .collection('professors')
          .orderBy('name')
          .get();

      _professors = snapshot.docs
          .map((doc) => Professor.fromJson(doc.data()))
          .toList();

      _applyFilters();
      
      if (kDebugMode) {
        print('ProfessorService: Loaded ${_professors.length} professors');
      }
    } catch (e) {
      _error = 'Failed to load professors: ${e.toString()}';
      if (kDebugMode) {
        print('ProfessorService error: $_error');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Search professors by name or chamber
  void searchProfessors(String query) {
    _searchQuery = query;
    _applyFilters();
    notifyListeners();
  }

  /// Clear search and show all professors
  void clearSearch() {
    _searchQuery = '';
    _applyFilters();
    notifyListeners();
  }

  /// Set sort type
  void setSortType(ProfessorSortType sortType) {
    _sortType = sortType;
    _applyFilters();
    notifyListeners();
  }

  /// Apply current search filters and sorting
  void _applyFilters() {
    if (_searchQuery.isEmpty) {
      _filteredProfessors = List.from(_professors);
    } else {
      final query = _searchQuery.toLowerCase();
      _filteredProfessors = _professors.where((professor) {
        final nameMatch = professor.name.toLowerCase().contains(query);
        final chamberMatch = professor.chamber.toLowerCase().contains(query);
        return nameMatch || chamberMatch;
      }).toList();
    }
    
    // Apply sorting
    _filteredProfessors.sort((a, b) {
      switch (_sortType) {
        case ProfessorSortType.nameAsc:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case ProfessorSortType.nameDesc:
          return b.name.toLowerCase().compareTo(a.name.toLowerCase());
        case ProfessorSortType.chamberAsc:
          return a.chamber.toLowerCase().compareTo(b.chamber.toLowerCase());
        case ProfessorSortType.chamberDesc:
          return b.chamber.toLowerCase().compareTo(a.chamber.toLowerCase());
      }
    });
  }

  /// Get professor by ID
  Professor? getProfessorById(String id) {
    try {
      return _professors.firstWhere((prof) => prof.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Get professors by chamber (exact match)
  List<Professor> getProfessorsByChamber(String chamber) {
    return _professors
        .where((prof) => prof.chamber.toLowerCase() == chamber.toLowerCase())
        .toList();
  }

  /// Get professors by name (partial match)
  List<Professor> getProfessorsByName(String name) {
    final query = name.toLowerCase();
    return _professors
        .where((prof) => prof.name.toLowerCase().contains(query))
        .toList();
  }

  /// Get all unique chambers
  List<String> getAllChambers() {
    final chambers = _professors
        .map((prof) => prof.chamber)
        .where((chamber) => chamber != 'Unavailable')
        .toSet()
        .toList();
    
    chambers.sort();
    return chambers;
  }

  /// Get statistics about the professor data
  Map<String, dynamic> getStatistics() {
    final availableChambers = _professors
        .where((prof) => prof.chamber != 'Unavailable')
        .length;
    
    final unavailableChambers = _professors
        .where((prof) => prof.chamber == 'Unavailable')
        .length;

    // Group by building (first letter of chamber)
    final buildingGroups = <String, int>{};
    for (final prof in _professors) {
      if (prof.chamber != 'Unavailable') {
        final building = prof.chamber.isNotEmpty ? prof.chamber[0].toUpperCase() : 'Unknown';
        buildingGroups[building] = (buildingGroups[building] ?? 0) + 1;
      }
    }

    return {
      'total': _professors.length,
      'availableChambers': availableChambers,
      'unavailableChambers': unavailableChambers,
      'buildingGroups': buildingGroups,
    };
  }

  /// Refresh professor data
  Future<void> refresh() async {
    await loadProfessors(forceRefresh: true);
  }
}