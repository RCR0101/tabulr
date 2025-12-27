import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

enum ProfessorSortType {
  nameAsc,
  nameDesc,
  chamberAsc,
  chamberDesc,
}

class Professor {
  final String id;
  final String name;
  final String chamber;
  final DateTime createdAt;
  final DateTime updatedAt;

  Professor({
    required this.id,
    required this.name,
    required this.chamber,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Professor.fromJson(Map<String, dynamic> json) {
    return Professor(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      chamber: json['chamber'] ?? 'Unavailable',
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
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
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
  String toString() => 'Professor(id: $id, name: $name, chamber: $chamber)';
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
      
    } catch (e) {
      _error = 'Failed to load professors: ${e.toString()}';
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