import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../constants/app_constants.dart';
import '../ui/secure_logger.dart';
import 'campus_service.dart';
import 'local_cache_service.dart';

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

  /// Reads both spellings, because the two sources genuinely disagree.
  ///
  /// rebuildProfessorSchedules (functions/admin.js) writes `course_code` and
  /// `section_id`; [toJson] — which backs the local cache — writes `courseCode`
  /// and `sectionId`. Reading only the camelCase names left both fields empty
  /// for everything loaded from Firestore, which blanked the chip labels in a
  /// professor's schedule dialog and made `addable` permanently false, so the
  /// tap-to-add-this-section chips did nothing.
  factory ProfessorScheduleEntry.fromJson(Map<String, dynamic> json) {
    return ProfessorScheduleEntry(
      courseCode: json['course_code'] ?? json['courseCode'] ?? '',
      courseTitle: json['course_title'] ?? json['courseTitle'] ?? '',
      sectionId: json['section_id'] ?? json['sectionId'] ?? '',
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

    if (hours.length == 1) {
      return ScheduleConstants.hourSlotNames[hours.first] ?? '';
    }

    final sortedHours = List<int>.from(hours)..sort();
    final startHour = sortedHours.first;
    final endHour = sortedHours.last;
    final startTime = ScheduleConstants.hourSlotNames[startHour]?.split('-')[0] ?? '';
    final endTime = ScheduleConstants.hourSlotNames[endHour]?.split('-')[1] ?? '';
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
  final String? email;
  final String? contact;
  final List<ProfessorScheduleEntry> schedule;
  final DateTime createdAt;
  final DateTime updatedAt;

  Professor({
    required this.id,
    required this.name,
    required this.chamber,
    this.email,
    this.contact,
    required this.schedule,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Professor.fromJson(Map<String, dynamic> json) {
    return Professor(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      chamber: json['chamber'] ?? 'Unavailable',
      email: json['email'] as String?,
      contact: json['contact'] as String?,
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
      if (email != null) 'email': email,
      if (contact != null) 'contact': contact,
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
    if (weekday < 1 || weekday > DayConstants.singleChar.length) return null;
    return DayConstants.singleChar[weekday - 1];
  }

  /// Get the current hour slot based on time
  static int? _getCurrentHourSlot(DateTime time) {
    final totalMinutes = time.hour * 60 + time.minute;

    // Maps a wall-clock time to a BITS hour slot (1 = 8:00, … 12 = 19:00).
    // Slot boundaries are the single source of truth in
    // ScheduleConstants.hourSlotNames.
    for (final entry in ScheduleConstants.hourToTime.entries) {
      final start = entry.value[0] * 60 + entry.value[1];
      if (totalMinutes >= start && totalMinutes < start + 50) return entry.key;
    }

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
  final LocalCacheService _localCache = LocalCacheService();

  List<Professor> _professors = [];
  List<Professor> _filteredProfessors = [];
  bool _isLoading = false;
  String? _error;
  String _searchQuery = '';
  ProfessorSortType _sortType = ProfessorSortType.nameAsc;

  String? _loadedCampusId;

  List<Professor> get professors => _filteredProfessors;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get searchQuery => _searchQuery;
  ProfessorSortType get sortType => _sortType;

  String get _cacheKey => 'professors_${CampusService.campusId}';

  DocumentReference<Map<String, dynamic>> get _metadataRef =>
      _firestore.doc('admin_metadata/professors_${CampusService.campusId}');

  Future<void> loadProfessors({bool forceRefresh = false}) async {
    final campusId = CampusService.campusId;
    if (_professors.isNotEmpty && !forceRefresh && _loadedCampusId == campusId) {
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (!forceRefresh) {
        final cached = await _localCache.readIfFresh(
          _cacheKey,
          metadataRef: _metadataRef,
        );
        if (cached != null) {
          _professors = cached.map((m) => Professor.fromJson(m)).toList();
          _loadedCampusId = campusId;
          _applyFilters();
          SecureLogger.info('ProfessorService', 'Loaded ${_professors.length} professors from cache');
          _isLoading = false;
          notifyListeners();
          return;
        }
      }

      final snapshot = await _firestore
          .collection(FirestoreCollections.reference).doc(FirestoreCollections.professors).collection('$campusId-entries')
          .orderBy('name')
          .get();

      final rawDocs = snapshot.docs.map((doc) => doc.data()).toList();
      _professors = rawDocs.map((m) => Professor.fromJson(m)).toList();
      _loadedCampusId = campusId;

      await _localCache.write(_cacheKey, rawDocs);
      _applyFilters();

      SecureLogger.info('ProfessorService', 'Loaded ${_professors.length} professors');
    } catch (e) {
      _error = 'Failed to load professors: ${e.toString()}';
      SecureLogger.error('ProfessorService', _error!);
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