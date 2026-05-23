import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/responsive_service.dart';
import '../services/toast_service.dart';
import '../services/auth_service.dart';
import '../utils/design_constants.dart';
import '../widgets/common/loading_state.dart';
import '../widgets/common/shimmer_loading.dart';


enum CourseSortOption {
  nameAsc,
  nameDesc,
  fileCountAsc,
  fileCountDesc,
}

enum FileSortOption {
  nameAsc,
  nameDesc,
  dateAsc,
  dateDesc,
  sizeAsc,
  sizeDesc,
}

int _naturalSort(String a, String b) {
  final regex = RegExp(r'(\d+|\D+)');
  final aParts = regex.allMatches(a.toLowerCase()).map((m) => m.group(0)!).toList();
  final bParts = regex.allMatches(b.toLowerCase()).map((m) => m.group(0)!).toList();
  
  final minLength = aParts.length < bParts.length ? aParts.length : bParts.length;
  
  for (int i = 0; i < minLength; i++) {
    final aPart = aParts[i];
    final bPart = bParts[i];
    
    final aNum = int.tryParse(aPart);
    final bNum = int.tryParse(bPart);
    
    if (aNum != null && bNum != null) {
      final comparison = aNum.compareTo(bNum);
      if (comparison != 0) return comparison;
    } else {
      final comparison = aPart.compareTo(bPart);
      if (comparison != 0) return comparison;
    }
  }
  
  return aParts.length.compareTo(bParts.length);
}

class AcadDrivesScreen extends StatefulWidget {
  const AcadDrivesScreen({super.key});

  @override
  State<AcadDrivesScreen> createState() => _AcadDrivesScreenState();
}

class _AcadDrivesScreenState extends State<AcadDrivesScreen> {
  String? _selectedCourse;
  List<Map<String, dynamic>> _courses = [];
  List<Map<String, dynamic>> _courseFiles = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreCourses = true;
  bool _isLoadingFiles = false;
  DocumentSnapshot? _lastCourseDoc;
  int _totalCourseCount = 0;

  bool _isSubmitting = false;
  String _searchQuery = '';
  CourseSortOption _courseSortOption = CourseSortOption.fileCountDesc;
  FileSortOption _fileSortOption = FileSortOption.nameAsc;
  static const _coursePageSize = 40;
  static const _filePageSize = 500;

  final ScrollController _coursesScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Submit form controllers
  final TextEditingController _driveLinkController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contributorController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _coursesScrollController.addListener(_onCoursesScroll);
    _loadCourses();
  }

  @override
  void dispose() {
    _coursesScrollController.dispose();
    _searchController.dispose();
    _driveLinkController.dispose();
    _titleController.dispose();
    _contributorController.dispose();
    super.dispose();
  }

  void _onCoursesScroll() {
    if (_searchQuery.isNotEmpty) return;
    if (!_hasMoreCourses || _isLoadingMore) return;
    final pos = _coursesScrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _loadMoreCourses();
    }
  }

  Future<void> _loadCourses() async {
    setState(() {
      _isLoading = true;
      _courses = [];
      _lastCourseDoc = null;
      _hasMoreCourses = true;
    });

    try {
      final countSnapshot = await _firestore
          .collection('acad_drives_index')
          .count()
          .get();
      _totalCourseCount = countSnapshot.count ?? 0;

      final query = _buildCourseQuery();
      final snapshot = await query.limit(_coursePageSize).get();

      setState(() {
        _courses = _parseCourses(snapshot.docs);
        _lastCourseDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
        _hasMoreCourses = snapshot.docs.length == _coursePageSize;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _courses = [];
        _isLoading = false;
      });
      ToastService.showError('Failed to load courses: $e');
    }
  }

  Future<void> _loadMoreCourses() async {
    if (_lastCourseDoc == null || _isLoadingMore || !_hasMoreCourses) return;

    setState(() => _isLoadingMore = true);

    try {
      final query = _buildCourseQuery()
          .startAfterDocument(_lastCourseDoc!)
          .limit(_coursePageSize);
      final snapshot = await query.get();

      setState(() {
        _courses.addAll(_parseCourses(snapshot.docs));
        _lastCourseDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
        _hasMoreCourses = snapshot.docs.length == _coursePageSize;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() => _isLoadingMore = false);
      ToastService.showError('Failed to load more courses: $e');
    }
  }

  Query<Map<String, dynamic>> _buildCourseQuery() {
    final collection = _firestore.collection('acad_drives_index');
    switch (_courseSortOption) {
      case CourseSortOption.nameAsc:
        return collection.orderBy('code');
      case CourseSortOption.nameDesc:
        return collection.orderBy('code', descending: true);
      case CourseSortOption.fileCountAsc:
        return collection.orderBy('fileCount').orderBy('code');
      case CourseSortOption.fileCountDesc:
        return collection.orderBy('fileCount', descending: true).orderBy('code', descending: true);
    }
  }

  List<Map<String, dynamic>> _parseCourses(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return docs.map((doc) {
      final data = doc.data();
      return {
        'code': data['code'] ?? doc.id,
        'name': data['code'] ?? doc.id,
        'fileCount': data['fileCount'] ?? 0,
        'driveCount': data['driveCount'] ?? 0,
      };
    }).toList();
  }

  Future<void> _loadAllCoursesForSearch() async {
    setState(() => _isLoading = true);
    try {
      final snapshot = await _firestore.collection('acad_drives_index').get();
      setState(() {
        _courses = _parseCourses(snapshot.docs);
        _hasMoreCourses = false;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ToastService.showError('Failed to load courses: $e');
    }
  }

  Future<void> _loadCourseFiles(String courseCode) async {
    setState(() {
      _isLoadingFiles = true;
      _selectedCourse = courseCode;
      _courseFiles = [];
    });

    try {
      final filesSnapshot = await _firestore
          .collection('acad_drives_files')
          .where('course_codes', arrayContains: courseCode)
          .orderBy('uploadedAt', descending: true)
          .limit(_filePageSize)
          .get();

      final files = filesSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          ...data,
        };
      }).toList();

      setState(() {
        _courseFiles = files;
        _isLoadingFiles = false;
      });
    } catch (e) {
      setState(() {
        _courseFiles = [];
        _isLoadingFiles = false;
      });
      ToastService.showError('Failed to load course files: $e');
    }
  }

  void _goBackToCourses() {
    setState(() {
      _selectedCourse = null;
      _courseFiles = [];
      _searchController.clear();
      _searchQuery = '';
    });
  }

  List<Map<String, dynamic>> get _filteredCourses {
    if (_searchQuery.isEmpty) {
      return _courses;
    }

    final query = _searchQuery.toLowerCase();
    final filtered = _courses.where((course) {
      final code = (course['code'] ?? '').toString().toLowerCase();
      final name = (course['name'] ?? '').toString().toLowerCase();
      return code.contains(query) || name.contains(query);
    }).toList();

    switch (_courseSortOption) {
      case CourseSortOption.nameAsc:
        filtered.sort((a, b) => (a['code'] ?? '').toString().toLowerCase().compareTo((b['code'] ?? '').toString().toLowerCase()));
      case CourseSortOption.nameDesc:
        filtered.sort((a, b) => (b['code'] ?? '').toString().toLowerCase().compareTo((a['code'] ?? '').toString().toLowerCase()));
      case CourseSortOption.fileCountAsc:
        filtered.sort((a, b) => (a['fileCount'] as int).compareTo(b['fileCount'] as int));
      case CourseSortOption.fileCountDesc:
        filtered.sort((a, b) => (b['fileCount'] as int).compareTo(a['fileCount'] as int));
    }

    return filtered;
  }

  List<Map<String, dynamic>> get _filteredFiles {
    List<Map<String, dynamic>> filtered;
    
    if (_searchQuery.isEmpty) {
      filtered = List.from(_courseFiles);
    } else {
      filtered = _courseFiles.where((file) {
        final name = (file['name'] ?? '').toString().toLowerCase();
        final path = (file['path'] ?? '').toString().toLowerCase();
        final tags = (file['tags'] as List<dynamic>? ?? []).join(' ').toLowerCase();
        final query = _searchQuery.toLowerCase();
        return name.contains(query) || path.contains(query) || tags.contains(query);
      }).toList();
    }
    
    // Apply sorting
    switch (_fileSortOption) {
      case FileSortOption.nameAsc:
        filtered.sort((a, b) => (a['name'] ?? '').toString().toLowerCase().compareTo((b['name'] ?? '').toString().toLowerCase()));
        break;
      case FileSortOption.nameDesc:
        filtered.sort((a, b) => (b['name'] ?? '').toString().toLowerCase().compareTo((a['name'] ?? '').toString().toLowerCase()));
        break;
      case FileSortOption.dateAsc:
        filtered.sort((a, b) {
          final aDate = a['uploadedAt'];
          final bDate = b['uploadedAt'];
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return -1;
          if (bDate == null) return 1;
          final aDateTime = aDate is Timestamp ? aDate.toDate() : DateTime.tryParse(aDate.toString()) ?? DateTime(1970);
          final bDateTime = bDate is Timestamp ? bDate.toDate() : DateTime.tryParse(bDate.toString()) ?? DateTime(1970);
          return aDateTime.compareTo(bDateTime);
        });
        break;
      case FileSortOption.dateDesc:
        filtered.sort((a, b) {
          final aDate = a['uploadedAt'];
          final bDate = b['uploadedAt'];
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          final aDateTime = aDate is Timestamp ? aDate.toDate() : DateTime.tryParse(aDate.toString()) ?? DateTime(1970);
          final bDateTime = bDate is Timestamp ? bDate.toDate() : DateTime.tryParse(bDate.toString()) ?? DateTime(1970);
          return bDateTime.compareTo(aDateTime);
        });
        break;
      case FileSortOption.sizeAsc:
        filtered.sort((a, b) => (a['size'] as int? ?? 0).compareTo(b['size'] as int? ?? 0));
        break;
      case FileSortOption.sizeDesc:
        filtered.sort((a, b) => (b['size'] as int? ?? 0).compareTo(a['size'] as int? ?? 0));
        break;
    }
    
    return filtered;
  }

  void _openFile(Map<String, dynamic> file, String type) async {
    if (kIsWeb) {
      String? url;
      if (type == 'drive') {
        url = file['folderMetadata']?['drive_link'];
      } else if (type == 'download') {
        url = file['url'];
      }
      
      if (url != null) {
              html.window.open(url, '_blank');
            } else {
        ToastService.showError('File URL not available');
      }
    }
    }

  Future<void> _showFileInfo(Map<String, dynamic> file) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          file['name'] ?? 'Unknown File',
          style: Theme.of(context).textTheme.titleMedium,
          overflow: TextOverflow.ellipsis,
        ),
        content: SizedBox(
          width: ResponsiveService.getValue(
            context,
            mobile: double.maxFinite,
            tablet: 400,
            desktop: 500,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _InfoRow('Size', _formatFileSize(file['size'] ?? 0)),
                _InfoRow('Uploaded', _formatDate(file['uploadedAt'])),
                
                const SizedBox(height: 16),
                Text(
                  'Metadata',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                if (file['contributor'] != null)
                  _InfoRow('Contributor', file['contributor']),

                if (file['driveName'] != null)
                  _InfoRow('Drive', file['driveName']),

                if (file['course_codes'] != null && (file['course_codes'] as List).isNotEmpty)
                  _InfoRow('Course', (file['course_codes'] as List).first.toString()),
                
                if (file['tags'] != null && (file['tags'] as List).isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Tags',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: (file['tags'] as List<dynamic>)
                        .map((tag) => Chip(
                              label: Text(
                                tag.toString(),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showSubmitDialog() async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cloud_upload),
            SizedBox(width: 8),
            Text('Submit Academic Resource'),
          ],
        ),
        content: SizedBox(
          width: ResponsiveService.getValue(
            context,
            mobile: double.maxFinite,
            tablet: 400,
            desktop: 500,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Share your notes, papers, or other academic materials with the community',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _driveLinkController,
                  decoration: const InputDecoration(
                    labelText: 'Google Drive Link *',
                    hintText: 'https://drive.google.com/file/d/...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title *',
                    hintText: 'e.g., Algorithm Analysis Notes',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _contributorController,
                  decoration: const InputDecoration(
                    labelText: 'Contributor Name *',
                    hintText: 'Your name as it should appear',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _isSubmitting ? null : _submitLink,
            child: _isSubmitting 
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitLink() async {
    if (_driveLinkController.text.isEmpty || 
        _titleController.text.isEmpty || 
        _contributorController.text.isEmpty) {
      ToastService.showError('Please fill in all required fields');
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      // Get user email from auth service
      final authService = AuthService();
      final userEmail = authService.userEmail;
      
      final submissionData = {
        'driveLink': _driveLinkController.text.trim(),
        'title': _titleController.text.trim(),
        'contributorName': _contributorController.text.trim(),
        'submittedBy': userEmail ?? 'anonymous',
        'status': 'pending',
        'submittedAt': FieldValue.serverTimestamp(),
      };

      await _firestore.collection('acad_drives_submissions').add(submissionData);

      ToastService.showSuccess('✅ Thank you! Your submission has been received and is pending approval.');
      
      if (mounted) {
        Navigator.of(context).pop();
      }
      
      // Clear form
      _driveLinkController.clear();
      _titleController.clear();
      _contributorController.clear();
    } catch (e) {
      ToastService.showError('Failed to submit: $e');
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  String _getFileIcon(String mimeType) {
    // Return empty string to remove emojis for files
    return '';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _showCourseSortDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.sort),
            SizedBox(width: 8),
            Text('Sort Courses'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: CourseSortOption.values.map((option) {
            String title;
            String subtitle;
            IconData icon;
            
            switch (option) {
              case CourseSortOption.nameAsc:
                title = 'Name A-Z';
                subtitle = 'Sort by course name ascending';
                icon = Icons.sort_by_alpha;
                break;
              case CourseSortOption.nameDesc:
                title = 'Name Z-A';
                subtitle = 'Sort by course name descending';
                icon = Icons.sort_by_alpha;
                break;
              case CourseSortOption.fileCountAsc:
                title = 'Files Count ↑';
                subtitle = 'Sort by file count ascending';
                icon = Icons.trending_up;
                break;
              case CourseSortOption.fileCountDesc:
                title = 'Files Count ↓';
                subtitle = 'Sort by file count descending';
                icon = Icons.trending_down;
                break;
            }
            
            return RadioListTile<CourseSortOption>(
              value: option,
              groupValue: _courseSortOption,
              onChanged: (value) {
                setState(() {
                  _courseSortOption = value!;
                });
                Navigator.pop(context);
                if (_searchQuery.isEmpty) {
                  _loadCourses();
                }
              },
              title: Text(title),
              subtitle: Text(subtitle),
              secondary: Icon(icon),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showFileSortDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.sort),
            SizedBox(width: 8),
            Text('Sort Files'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: FileSortOption.values.map((option) {
            String title;
            String subtitle;
            IconData icon;
            
            switch (option) {
              case FileSortOption.nameAsc:
                title = 'Name A-Z';
                subtitle = 'Sort by filename ascending';
                icon = Icons.sort_by_alpha;
                break;
              case FileSortOption.nameDesc:
                title = 'Name Z-A';
                subtitle = 'Sort by filename descending';
                icon = Icons.sort_by_alpha;
                break;
              case FileSortOption.dateAsc:
                title = 'Date Oldest';
                subtitle = 'Sort by upload date ascending';
                icon = Icons.schedule;
                break;
              case FileSortOption.dateDesc:
                title = 'Date Newest';
                subtitle = 'Sort by upload date descending';
                icon = Icons.schedule;
                break;
              case FileSortOption.sizeAsc:
                title = 'Size Smallest';
                subtitle = 'Sort by file size ascending';
                icon = Icons.storage;
                break;
              case FileSortOption.sizeDesc:
                title = 'Size Largest';
                subtitle = 'Sort by file size descending';
                icon = Icons.storage;
                break;
            }
            
            return RadioListTile<FileSortOption>(
              value: option,
              groupValue: _fileSortOption,
              onChanged: (value) {
                setState(() {
                  _fileSortOption = value!;
                });
                Navigator.pop(context);
              },
              title: Text(title),
              subtitle: Text(subtitle),
              secondary: Icon(icon),
            );
          }).toList(),
        ),
      ),
    );
  }

  String _formatDate(dynamic dateValue) {
    DateTime date;
    
    if (dateValue is Timestamp) {
      date = dateValue.toDate();
    } else if (dateValue is String) {
      date = DateTime.parse(dateValue);
    } else if (dateValue == null) {
      return 'Unknown';
    } else {
      return 'Unknown';
    }
    
    final now = DateTime.now();
    final difference = now.difference(date).inDays;
    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    if (difference < 7) return '$difference days ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedCourse ?? 'Academic Drives'),
        leading: _selectedCourse != null
            ? IconButton(
                onPressed: _goBackToCourses,
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to Courses',
              )
            : null, // This will show the hamburger menu for main screen
        actions: [
          IconButton(
            onPressed: _showSubmitDialog,
            icon: const Icon(Icons.cloud_upload_outlined),
            tooltip: 'Submit Resource',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Section
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                // Search Field
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      final wasEmpty = _searchQuery.isEmpty;
                      final isNowEmpty = value.isEmpty;
                      setState(() => _searchQuery = value);
                      if (_selectedCourse == null) {
                        if (wasEmpty && !isNowEmpty) {
                          _loadAllCoursesForSearch();
                        } else if (!wasEmpty && isNowEmpty) {
                          _loadCourses();
                        }
                      }
                    },
                    decoration: InputDecoration(
                      hintText: _selectedCourse != null
                        ? 'Search files in $_selectedCourse...'
                        : 'Search courses...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                final wasSearching = _searchQuery.isNotEmpty;
                                setState(() => _searchQuery = '');
                                if (_selectedCourse == null && wasSearching) {
                                  _loadCourses();
                                }
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(width: 12),
                
                // Sort Button
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    onPressed: _selectedCourse != null 
                        ? _showFileSortDialog
                        : _showCourseSortDialog,
                    icon: const Icon(Icons.sort),
                    tooltip: _selectedCourse != null ? 'Sort files' : 'Sort courses',
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: _selectedCourse == null
                ? _buildCoursesView()
                : _buildFilesView(),
          ),
        ],
      ),
    );
  }

  Widget _buildCoursesView() {
    if (_isLoading) {
      return AcadDrivesSkeleton(grid: !ResponsiveService.isMobile(context));
    }

    final courses = _filteredCourses;

    if (courses.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.school_outlined, size: 64, color: AppDesign.muted(context)),
            const SizedBox(height: 16),
            Text(
              'No courses found',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppDesign.muted(context),
              ),
            ),
          ],
        ),
      );
    }

    final itemCount = courses.length + (_hasMoreCourses && _searchQuery.isEmpty ? 1 : 0);

    final isMobile = ResponsiveService.isMobile(context);
    if (isMobile) {
      return Column(
        children: [
          _buildCourseCountBar(courses.length),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadCourses,
              child: ListView.builder(
                controller: _coursesScrollController,
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: itemCount,
                itemBuilder: (context, index) {
                  if (index >= courses.length) {
                    return _buildLoadingFooter();
                  }
                  final course = courses[index];
                  return _CourseCard(
                    course: course,
                    onTap: () => _loadCourseFiles(course['code']),
                  );
                },
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        _buildCourseCountBar(courses.length),
        Expanded(
          child: GridView.builder(
            controller: _coursesScrollController,
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 360,
              mainAxisExtent: 80,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: itemCount,
            itemBuilder: (context, index) {
              if (index >= courses.length) {
                return _buildLoadingFooter();
              }
              final course = courses[index];
              return _CourseCard(
                course: course,
                onTap: () => _loadCourseFiles(course['code']),
                compact: true,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCourseCountBar(int shown) {
    final total = _searchQuery.isNotEmpty ? shown : _totalCourseCount;
    final label = _searchQuery.isNotEmpty
        ? '$shown result${shown == 1 ? '' : 's'}'
        : _hasMoreCourses
            ? 'Showing $shown of $total courses'
            : '$total courses';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingFooter() {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }

  Widget _buildFilesView() {
    if (_isLoadingFiles) {
      return const GenericListSkeleton(count: 8, itemHeight: 56);
    }

    final files = _filteredFiles;
    
    if (files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64, color: AppDesign.muted(context)),
            const SizedBox(height: 16),
            Text(
              'No files found',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppDesign.muted(context),
              ),
            ),
          ],
        ),
      );
    }

    // Group files by driveName and then create hierarchical folder structure
    final Map<String, _FolderTree> driveTrees = {};
    final Map<String, String> driveContributors = {};
    for (final file in files) {
      final driveName = file['driveName'] as String? ?? 'Unknown Drive';
      final path = file['path'] as String? ?? '';
      final contributor = file['contributor'] as String?;

      // Track contributor per drive (use the first one found)
      if (contributor != null && contributor.isNotEmpty && !driveContributors.containsKey(driveName)) {
        driveContributors[driveName] = contributor;
      }

      // Extract folder path from the path field
      final pathParts = path.split('/');
      List<String> folderPath = [];
      if (pathParts.length > 1) {
        // Get folder structure, exclude filename
        folderPath = pathParts.sublist(0, pathParts.length - 1);
      }

      // If no folder structure, put in root
      if (folderPath.isEmpty) {
        folderPath = ['General'];
      }

      driveTrees.putIfAbsent(driveName, () => _FolderTree());
      driveTrees[driveName]!.addFile(folderPath, file);
    }

    final driveNames = driveTrees.keys.toList()..sort(_naturalSort);

    return RefreshIndicator(
      onRefresh: () => _loadCourseFiles(_selectedCourse!),
      child: ListView.builder(
        itemCount: driveNames.length,
        itemBuilder: (context, index) {
          final driveName = driveNames[index];
          final folderTree = driveTrees[driveName]!;
          final contributor = driveContributors[driveName];

          return _DriveHierarchySection(
            driveName: driveName,
            contributor: contributor,
            folderTree: folderTree,
            onOpenFile: (file, type) => _openFile(file, type),
            onShowFileInfo: (file) => _showFileInfo(file),
            formatFileSize: _formatFileSize,
            formatDate: _formatDate,
            getFileIcon: _getFileIcon,
          );
        },
      ),
    );
  }
}

// Course Card Widget
class _CourseCard extends StatelessWidget {
  final Map<String, dynamic> course;
  final VoidCallback onTap;
  final bool compact;

  const _CourseCard({
    required this.course,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: compact ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: compact ? 1 : 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 16),
          child: Row(
            children: [
              Icon(
                Icons.folder_rounded,
                size: compact ? 28 : 32,
                color: AppDesign.warning(context),
              ),
              SizedBox(width: compact ? 12 : 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      course['code'] ?? 'Unknown Course',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${course['fileCount']} file${course['fileCount'] == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
            ],
          ),
        ),
      ),
    );
  }
}

// File Card Widget
class _FileCard extends StatelessWidget {
  final Map<String, dynamic> file;
  final Function(String) onOpen;
  final VoidCallback onInfo;
  final String Function(int) formatFileSize;
  final String Function(dynamic) formatDate;
  final String Function(String) getFileIcon;

  const _FileCard({
    required this.file,
    required this.onOpen,
    required this.onInfo,
    required this.formatFileSize,
    required this.formatDate,
    required this.getFileIcon,
  });

  @override
  Widget build(BuildContext context) {
    final hasDriveLink = file['folderMetadata']?['drive_link'] != null && file['folderMetadata']?['drive_link'] != 'NA';
    final hasDownloadUrl = file['url'] != null && file['url'] != 'NA' && file['url'].toString().trim().isNotEmpty;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [

            // File Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file['name'] ?? 'Unknown File',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        formatFileSize(file['size'] ?? 0),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '•',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatDate(file['uploadedAt']),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Action Buttons
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Info Button
                IconButton(
                  onPressed: onInfo,
                  icon: const Icon(Icons.info_outline, size: 20),
                  tooltip: 'File Info',
                ),
                
                // Drive Button (conditional)
                if (hasDriveLink)
                  IconButton(
                    onPressed: () => onOpen('drive'),
                    icon: const Icon(Icons.open_in_new, size: 20),
                    tooltip: 'Open in Drive',
                  ),
                
                // Download Button (conditional)
                if (hasDownloadUrl)
                  IconButton(
                    onPressed: () => onOpen('download'),
                    icon: const Icon(Icons.download, size: 20),
                    tooltip: 'Download',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Folder Tree Data Structure
class _FolderTree {
  final Map<String, _FolderTree> subfolders = {};
  final List<Map<String, dynamic>> files = [];
  
  void addFile(List<String> folderPath, Map<String, dynamic> file) {
    if (folderPath.isEmpty) {
      files.add(file);
    } else {
      final folderName = folderPath.first;
      subfolders.putIfAbsent(folderName, () => _FolderTree());
      subfolders[folderName]!.addFile(folderPath.sublist(1), file);
    }
  }
  
  int get totalFileCount {
    int count = files.length;
    for (final subfolder in subfolders.values) {
      count += subfolder.totalFileCount;
    }
    return count;
  }
}

// Hierarchical Drive Section Widget
class _DriveHierarchySection extends StatefulWidget {
  final String driveName;
  final String? contributor;
  final _FolderTree folderTree;
  final Function(Map<String, dynamic>, String) onOpenFile;
  final Function(Map<String, dynamic>) onShowFileInfo;
  final String Function(int) formatFileSize;
  final String Function(dynamic) formatDate;
  final String Function(String) getFileIcon;

  const _DriveHierarchySection({
    required this.driveName,
    this.contributor,
    required this.folderTree,
    required this.onOpenFile,
    required this.onShowFileInfo,
    required this.formatFileSize,
    required this.formatDate,
    required this.getFileIcon,
  });

  @override
  State<_DriveHierarchySection> createState() => _DriveHierarchySectionState();
}

class _DriveHierarchySectionState extends State<_DriveHierarchySection> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          // Drive Header
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_shared,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.driveName,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        Text(
                          '${widget.folderTree.totalFileCount} file${widget.folderTree.totalFileCount == 1 ? '' : 's'} • ${widget.folderTree.subfolders.length} folder${widget.folderTree.subfolders.length == 1 ? '' : 's'}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                        if (widget.contributor != null && widget.contributor!.isNotEmpty)
                          Text(
                            'Credits: ${widget.contributor}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.secondary,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),

          // Folder Hierarchy
          if (_isExpanded) ...[
            const Divider(height: 1),
            _FolderNode(
              folderTree: widget.folderTree,
              level: 0,
              onOpenFile: widget.onOpenFile,
              onShowFileInfo: widget.onShowFileInfo,
              formatFileSize: widget.formatFileSize,
              formatDate: widget.formatDate,
              getFileIcon: widget.getFileIcon,
            ),
          ],
        ],
      ),
    );
  }
}

// Recursive Folder Node Widget
class _FolderNode extends StatefulWidget {
  final _FolderTree folderTree;
  final int level;
  final String? folderName;
  final Function(Map<String, dynamic>, String) onOpenFile;
  final Function(Map<String, dynamic>) onShowFileInfo;
  final String Function(int) formatFileSize;
  final String Function(dynamic) formatDate;
  final String Function(String) getFileIcon;

  const _FolderNode({
    required this.folderTree,
    required this.level,
    this.folderName,
    required this.onOpenFile,
    required this.onShowFileInfo,
    required this.formatFileSize,
    required this.formatDate,
    required this.getFileIcon,
  });

  @override
  State<_FolderNode> createState() => _FolderNodeState();
}

class _FolderNodeState extends State<_FolderNode> {
  final Map<String, bool> _folderExpanded = {};

  @override
  Widget build(BuildContext context) {
    final subfolderNames = widget.folderTree.subfolders.keys.toList()..sort(_naturalSort);
    
    return Column(
      children: [
        // Render subfolders
        ...subfolderNames.map((folderName) {
          final subfolder = widget.folderTree.subfolders[folderName]!;
          final isExpanded = _folderExpanded[folderName] ?? false;
          final hasSubfolders = subfolder.subfolders.isNotEmpty;
          
          return Column(
            children: [
              // Folder Header
              InkWell(
                onTap: () => setState(() => _folderExpanded[folderName] = !isExpanded),
                child: Container(
                  padding: EdgeInsets.only(
                    left: 16.0 + (widget.level * 20.0),
                    right: 16,
                    top: 12,
                    bottom: 12,
                  ),
                  decoration: BoxDecoration(
                    color: _getFolderBackgroundColor(context, widget.level),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        hasSubfolders || subfolder.files.isNotEmpty 
                            ? (isExpanded ? Icons.folder_open : Icons.folder)
                            : Icons.folder_outlined,
                        color: _getFolderIconColor(context, widget.level),
                        size: 18,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          folderName,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: _getFolderTextColor(context, widget.level),
                          ),
                        ),
                      ),
                      Text(
                        '${subfolder.totalFileCount}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: _getFolderIconColor(context, widget.level),
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
              
              // Folder Contents (Recursive)
              if (isExpanded) ...[
                _FolderNode(
                  folderTree: subfolder,
                  level: widget.level + 1,
                  folderName: folderName,
                  onOpenFile: widget.onOpenFile,
                  onShowFileInfo: widget.onShowFileInfo,
                  formatFileSize: widget.formatFileSize,
                  formatDate: widget.formatDate,
                  getFileIcon: widget.getFileIcon,
                ),
              ],
            ],
          );
        }),
        
        // Render files at this level
        ...widget.folderTree.files.map((file) => Container(
          margin: EdgeInsets.only(left: 16.0 + (widget.level * 20.0)),
          child: _FileCard(
            file: file,
            onOpen: (type) => widget.onOpenFile(file, type),
            onInfo: () => widget.onShowFileInfo(file),
            formatFileSize: widget.formatFileSize,
            formatDate: widget.formatDate,
            getFileIcon: widget.getFileIcon,
          ),
        )),
      ],
    );
  }
  
  Color _getFolderBackgroundColor(BuildContext context, int level) {
    switch (level % 3) {
      case 0:
        return Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.3);
      case 1:
        return Theme.of(context).colorScheme.tertiaryContainer.withValues(alpha: 0.3);
      default:
        return Theme.of(context).colorScheme.surfaceContainer.withValues(alpha: 0.5);
    }
  }
  
  Color _getFolderIconColor(BuildContext context, int level) {
    switch (level % 3) {
      case 0:
        return Theme.of(context).colorScheme.secondary;
      case 1:
        return Theme.of(context).colorScheme.tertiary;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }
  
  Color _getFolderTextColor(BuildContext context, int level) {
    switch (level % 3) {
      case 0:
        return Theme.of(context).colorScheme.secondary;
      case 1:
        return Theme.of(context).colorScheme.tertiary;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }
}

// Info Row Widget
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}