import 'dart:typed_data';
import '../services/ui/secure_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/web_utils.dart' as web_utils;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart' deferred as arch;
import '../services/data/acad_drives_service.dart';
import '../services/data/user_settings_service.dart';
import '../services/core/timetable_service.dart';
import '../services/ui/responsive_service.dart';
import '../services/ui/toast_service.dart';
import '../services/data/auth_service.dart';
import '../constants/app_constants.dart';
import '../utils/design_constants.dart';
import '../widgets/common/shimmer_loading.dart';
import '../widgets/command_palette.dart';
import '../widgets/app_destinations.dart';
import '../services/ui/tutorial_service.dart';
import '../widgets/common/app_dialog.dart';
import '../widgets/common/app_tappable.dart';
import '../widgets/common/app_button.dart';
import '../services/data/courses_master_service.dart';
import '../utils/page_info_helper.dart';
import '../widgets/acad_drives/acad_drives_layout.dart';

enum CourseSortOption { nameAsc, nameDesc, fileCountAsc, fileCountDesc }

enum FileSortOption { nameAsc, nameDesc, dateAsc, dateDesc, sizeAsc, sizeDesc }

int _naturalSort(String a, String b) {
  final regex = RegExp(r'(\d+|\D+)');
  final aParts =
      regex.allMatches(a.toLowerCase()).map((m) => m.group(0)!).toList();
  final bParts =
      regex.allMatches(b.toLowerCase()).map((m) => m.group(0)!).toList();

  final minLength =
      aParts.length < bParts.length ? aParts.length : bParts.length;

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
  bool _showingBookmarks = false;
  Map<String, dynamic> _selectedDriveLinks = {};
  List<Map<String, dynamic>> _courses = [];
  List<Map<String, dynamic>> _courseFiles = [];
  List<Map<String, dynamic>> _bookmarkedFiles = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreCourses = true;
  bool _isLoadingFiles = false;
  DocumentSnapshot? _lastCourseDoc;
  DocumentSnapshot? _lastFileDoc;
  bool _hasMoreFiles = false;
  int _fileRequestId = 0;
  int _totalCourseCount = 0;

  bool _isSubmitting = false;
  String _searchQuery = '';
  CourseSortOption _courseSortOption = CourseSortOption.fileCountDesc;
  FileSortOption _fileSortOption = FileSortOption.nameAsc;
  static const _coursePageSize = AppLimits.acadDriveCoursePageSize;
  static const _filePageSize = AppLimits.acadDriveFilePageSize;

  final ScrollController _coursesScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final AcadDrivesService _drivesService = AcadDrivesService();
  Set<String> _enrolledCourseCodes = {};
  List<Map<String, dynamic>> _enrolledCourseEntries = [];
  bool _starredExpanded = true;
  bool _yourCoursesExpanded = true;

  // Submit form controllers
  final TextEditingController _driveLinkController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contributorController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _coursesScrollController.addListener(_onCoursesScroll);
    _loadEnrolledCourses();
    _loadCourses().then((_) {
      if (mounted) {
        TutorialService().autoStart(
          context,
          DrawerScreen.acadDrives,
          isMounted: () => mounted,
        );
      }
    });
    CommandPaletteActions.register(
      DrawerScreen.acadDrives,
      () => [
        CommandPaletteEntry(
          label: 'Submit Drive Link',
          subtitle: 'Submit a new academic resource link',
          icon: Icons.add_link,
          category: CommandCategory.context,
          onSelect: _showSubmitDialog,
        ),
        if (_selectedCourse != null)
          CommandPaletteEntry(
            label: 'Back to Courses',
            subtitle: 'Return to course list',
            icon: Icons.arrow_back,
            category: CommandCategory.context,
            onSelect: _goBackToCourses,
          ),
      ],
    );
  }

  @override
  void dispose() {
    CommandPaletteActions.unregister(DrawerScreen.acadDrives);
    _coursesScrollController.dispose();
    _searchController.dispose();
    _driveLinkController.dispose();
    _titleController.dispose();
    _contributorController.dispose();
    super.dispose();
  }

  Future<void> _loadEnrolledCourses() async {
    try {
      final timetables = await TimetableService().getAllTimetables();
      final codes = <String>{};
      for (final tt in timetables) {
        for (final sel in tt.selectedSections) {
          codes.add(sel.courseCode.trim());
        }
      }
      if (codes.isEmpty) return;

      final docs = await _drivesService.fetchCoursesByCodes(codes);
      final master = CoursesMasterService();
      final entries =
          docs.map((doc) {
            final data = doc.data();
            final code = data['code'] ?? doc.id;
            final title = master.getTitle(code);
            return {
              'code': code,
              'name': title != code ? title : '',
              'fileCount': data['fileCount'] ?? 0,
              'driveCount': data['driveCount'] ?? 0,
            };
          }).toList();

      final normalizedCodes = codes.map((c) => c.toUpperCase()).toSet();
      if (mounted) {
        setState(() {
          _enrolledCourseCodes = normalizedCodes;
          _enrolledCourseEntries = entries;
        });
      }
    } catch (e) {
      SecureLogger.warning(
        'ACAD_DRIVES',
        'Failed to load enrolled course codes',
        {'error': e.toString()},
      );
    }
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
      _totalCourseCount = await _drivesService.getCourseCount();

      final query = _buildCourseQuery();
      final snapshot = await _drivesService.fetchCourses(
        query,
        limit: _coursePageSize,
      );

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
      final query = _buildCourseQuery();
      final snapshot = await _drivesService.fetchCourses(
        query,
        limit: _coursePageSize,
        startAfter: _lastCourseDoc!,
      );

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
    switch (_courseSortOption) {
      case CourseSortOption.nameAsc:
        return _drivesService.buildCourseQuery('code');
      case CourseSortOption.nameDesc:
        return _drivesService.buildCourseQuery('code', descending: true);
      case CourseSortOption.fileCountAsc:
        return _drivesService.buildCourseQuery('fileCount');
      case CourseSortOption.fileCountDesc:
        return _drivesService.buildCourseQuery('fileCount', descending: true);
    }
  }

  List<Map<String, dynamic>> _parseCourses(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final master = CoursesMasterService();
    return docs.map((doc) {
      final data = doc.data();
      final code = data['code'] ?? doc.id;
      final title = master.getTitle(code);
      return {
        'code': code,
        'name': title != code ? title : '',
        'fileCount': data['fileCount'] ?? 0,
        'driveCount': data['driveCount'] ?? 0,
        'driveLinks': data['driveLinks'] as Map<String, dynamic>? ?? {},
      };
    }).toList();
  }

  List<Map<String, dynamic>> _parseCourseMaps(
    List<Map<String, dynamic>> rawMaps,
  ) {
    final master = CoursesMasterService();
    return rawMaps.map((data) {
      final code = data['code'] ?? data['_docId'] ?? '';
      final title = master.getTitle(code);
      final driveLinks = data['driveLinks'];
      return {
        'code': code,
        'name': title != code ? title : '',
        'fileCount': data['fileCount'] ?? 0,
        'driveCount': data['driveCount'] ?? 0,
        'driveLinks':
            driveLinks is Map<String, dynamic>
                ? driveLinks
                : (driveLinks is Map
                    ? Map<String, dynamic>.from(driveLinks)
                    : <String, dynamic>{}),
      };
    }).toList();
  }

  Future<void> _loadAllCoursesForSearch() async {
    setState(() => _isLoading = true);
    try {
      final data = await _drivesService.fetchAllCoursesData();
      setState(() {
        _courses = _parseCourseMaps(data);
        _hasMoreCourses = false;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ToastService.showError('Failed to load courses: $e');
    }
  }

  bool _isLoadingMoreFiles = false;

  Future<void> _loadCourseFiles(String courseCode) async {
    final requestId = ++_fileRequestId;
    final courseEntry = _courses.firstWhere(
      (c) => c['code'] == courseCode,
      orElse: () => <String, dynamic>{},
    );
    setState(() {
      _isLoadingFiles = true;
      _isLoadingMoreFiles = false;
      _selectedCourse = courseCode;
      _selectedDriveLinks =
          (courseEntry['driveLinks'] as Map<String, dynamic>?) ?? {};
      _courseFiles = [];
      _lastFileDoc = null;
      _hasMoreFiles = false;
    });

    try {
      final snapshot = await _drivesService.fetchCourseFiles(
        courseCode,
        limit: _filePageSize,
      );
      if (!mounted ||
          requestId != _fileRequestId ||
          _selectedCourse != courseCode) {
        return;
      }

      final files =
          snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      setState(() {
        _courseFiles = files;
        _lastFileDoc = snapshot.docs.isEmpty ? null : snapshot.docs.last;
        _hasMoreFiles =
            snapshot.docs.length == _filePageSize &&
            files.length < AppLimits.acadDriveFileMaxSize;
        _isLoadingFiles = false;
      });
    } catch (e) {
      if (!mounted || requestId != _fileRequestId) return;
      setState(() {
        _courseFiles = [];
        _isLoadingFiles = false;
      });
      ToastService.showError('Failed to load course files: $e');
    }
  }

  Future<void> _loadMoreFiles() async {
    final courseCode = _selectedCourse;
    final cursor = _lastFileDoc;
    if (courseCode == null ||
        cursor == null ||
        _isLoadingMoreFiles ||
        !_hasMoreFiles) {
      return;
    }

    final requestId = _fileRequestId;
    final remaining = AppLimits.acadDriveFileMaxSize - _courseFiles.length;
    if (remaining <= 0) {
      setState(() => _hasMoreFiles = false);
      return;
    }
    final limit = remaining < _filePageSize ? remaining : _filePageSize;
    setState(() => _isLoadingMoreFiles = true);

    try {
      final snapshot = await _drivesService.fetchCourseFiles(
        courseCode,
        limit: limit,
        startAfter: cursor,
      );
      if (!mounted ||
          requestId != _fileRequestId ||
          _selectedCourse != courseCode) {
        return;
      }

      final moreFiles =
          snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      setState(() {
        _courseFiles.addAll(moreFiles);
        _lastFileDoc = snapshot.docs.isEmpty ? cursor : snapshot.docs.last;
        _hasMoreFiles =
            snapshot.docs.length == limit &&
            _courseFiles.length < AppLimits.acadDriveFileMaxSize;
        _isLoadingMoreFiles = false;
      });
    } catch (_) {
      if (mounted && requestId == _fileRequestId) {
        setState(() => _isLoadingMoreFiles = false);
      }
    }
  }

  void _goBackToCourses() {
    _fileRequestId++;
    setState(() {
      _selectedCourse = null;
      _showingBookmarks = false;
      _selectedDriveLinks = {};
      _courseFiles = [];
      _bookmarkedFiles = [];
      _lastFileDoc = null;
      _hasMoreFiles = false;
      _isLoadingMoreFiles = false;
      _searchController.clear();
      _searchQuery = '';
    });
  }

  void _toggleBookmark(String fileId) {
    UserSettingsService().toggleAcadDriveBookmark(fileId);
    setState(() {});
  }

  Future<void> _loadBookmarks() async {
    setState(() {
      _isLoadingFiles = true;
      _showingBookmarks = true;
      _selectedCourse = null;
    });

    try {
      final bookmarkIds = UserSettingsService().acadDriveBookmarks;
      if (bookmarkIds.isEmpty) {
        setState(() {
          _bookmarkedFiles = [];
          _isLoadingFiles = false;
        });
        return;
      }
      final files = await _drivesService.fetchFilesByIds(bookmarkIds);
      setState(() {
        _bookmarkedFiles = files;
        _isLoadingFiles = false;
      });
    } catch (e) {
      setState(() {
        _bookmarkedFiles = [];
        _isLoadingFiles = false;
      });
      ToastService.showError('Failed to load bookmarks: $e');
    }
  }

  bool _isEnrolledCourse(Map<String, dynamic> course) {
    final code = (course['code'] ?? '').toString().trim().toUpperCase();
    return _enrolledCourseCodes.contains(code);
  }

  List<Map<String, dynamic>> get _filteredCourses {
    List<Map<String, dynamic>> result;

    if (_searchQuery.isEmpty) {
      result = List.of(_courses);
    } else {
      final query = _searchQuery.toLowerCase();
      result =
          _courses.where((course) {
            final code = (course['code'] ?? '').toString().toLowerCase();
            final name = (course['name'] ?? '').toString().toLowerCase();
            return code.contains(query) || name.contains(query);
          }).toList();

      switch (_courseSortOption) {
        case CourseSortOption.nameAsc:
          result.sort(
            (a, b) => (a['code'] ?? '').toString().toLowerCase().compareTo(
              (b['code'] ?? '').toString().toLowerCase(),
            ),
          );
        case CourseSortOption.nameDesc:
          result.sort(
            (a, b) => (b['code'] ?? '').toString().toLowerCase().compareTo(
              (a['code'] ?? '').toString().toLowerCase(),
            ),
          );
        case CourseSortOption.fileCountAsc:
          result.sort(
            (a, b) => (a['fileCount'] as int).compareTo(b['fileCount'] as int),
          );
        case CourseSortOption.fileCountDesc:
          result.sort(
            (a, b) => (b['fileCount'] as int).compareTo(a['fileCount'] as int),
          );
      }
    }

    // Put enrolled courses first (only when not searching)
    if (_searchQuery.isEmpty && _enrolledCourseEntries.isNotEmpty) {
      final rest = result.where((c) => !_isEnrolledCourse(c)).toList();
      return [..._enrolledCourseEntries, ...rest];
    }

    return result;
  }

  int get _enrolledCourseCount {
    if (_searchQuery.isNotEmpty || _enrolledCourseEntries.isEmpty) return 0;
    return _enrolledCourseEntries.length;
  }

  List<Map<String, dynamic>> get _filteredFiles {
    List<Map<String, dynamic>> filtered;

    if (_searchQuery.isEmpty) {
      filtered = List.from(_courseFiles);
    } else {
      filtered =
          _courseFiles.where((file) {
            final name = (file['name'] ?? '').toString().toLowerCase();
            final path = (file['path'] ?? '').toString().toLowerCase();
            final tags =
                (file['tags'] as List<dynamic>? ?? []).join(' ').toLowerCase();
            final query = _searchQuery.toLowerCase();
            return name.contains(query) ||
                path.contains(query) ||
                tags.contains(query);
          }).toList();
    }

    // Apply sorting
    switch (_fileSortOption) {
      case FileSortOption.nameAsc:
        filtered.sort(
          (a, b) => (a['name'] ?? '').toString().toLowerCase().compareTo(
            (b['name'] ?? '').toString().toLowerCase(),
          ),
        );
        break;
      case FileSortOption.nameDesc:
        filtered.sort(
          (a, b) => (b['name'] ?? '').toString().toLowerCase().compareTo(
            (a['name'] ?? '').toString().toLowerCase(),
          ),
        );
        break;
      case FileSortOption.dateAsc:
        filtered.sort((a, b) {
          final aDate = a['uploadedAt'];
          final bDate = b['uploadedAt'];
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return -1;
          if (bDate == null) return 1;
          final aDateTime =
              aDate is Timestamp
                  ? aDate.toDate()
                  : DateTime.tryParse(aDate.toString()) ?? DateTime(1970);
          final bDateTime =
              bDate is Timestamp
                  ? bDate.toDate()
                  : DateTime.tryParse(bDate.toString()) ?? DateTime(1970);
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
          final aDateTime =
              aDate is Timestamp
                  ? aDate.toDate()
                  : DateTime.tryParse(aDate.toString()) ?? DateTime(1970);
          final bDateTime =
              bDate is Timestamp
                  ? bDate.toDate()
                  : DateTime.tryParse(bDate.toString()) ?? DateTime(1970);
          return bDateTime.compareTo(aDateTime);
        });
        break;
      case FileSortOption.sizeAsc:
        filtered.sort(
          (a, b) => (a['size'] as int? ?? 0).compareTo(b['size'] as int? ?? 0),
        );
        break;
      case FileSortOption.sizeDesc:
        filtered.sort(
          (a, b) => (b['size'] as int? ?? 0).compareTo(a['size'] as int? ?? 0),
        );
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
        web_utils.openUrl(url);
      } else {
        ToastService.showError('File URL not available');
      }
    }
  }

  bool _isDownloading = false;
  bool _downloadCancelled = false;

  Future<void> _downloadAsZip(String zipName, _FolderTree folderTree) async {
    if (!kIsWeb) {
      ToastService.showError('Mass download is only available on web');
      return;
    }
    if (_isDownloading) return;

    final allFiles = folderTree.collectAllFiles();
    final downloadable =
        allFiles.where((f) {
          final url = f.file['url'];
          if (url == null || url == 'NA' || url.toString().trim().isEmpty) {
            return false;
          }
          final uri = Uri.tryParse(url.toString());
          return uri != null && uri.scheme == 'https';
        }).toList();

    if (downloadable.isEmpty) {
      ToastService.showError('No downloadable files found');
      return;
    }

    _isDownloading = true;
    _downloadCancelled = false;
    final total = downloadable.length;
    final progressNotifier = ValueNotifier<String>('Preparing $total files...');
    final progressValue = ValueNotifier<double>(0);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => PopScope(
            canPop: false,
            child: AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  ValueListenableBuilder<double>(
                    valueListenable: progressValue,
                    builder:
                        (_, value, __) => LinearProgressIndicator(
                          value: value > 0 ? value : null,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(3),
                        ),
                  ),
                  const SizedBox(height: 16),
                  ValueListenableBuilder<String>(
                    valueListenable: progressNotifier,
                    builder:
                        (_, text, __) => Text(
                          text,
                          textAlign: TextAlign.center,
                          style: Theme.of(ctx).textTheme.bodyMedium,
                        ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _downloadCancelled = true;
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
    );

    try {
      await arch.loadLibrary();
      final archive = arch.Archive();
      int fetched = 0;
      int failed = 0;

      for (final entry in downloadable) {
        if (_downloadCancelled) break;
        try {
          final uri = Uri.parse(entry.file['url']);
          if (uri.scheme != 'https') {
            failed++;
            continue;
          }
          final response = await http.get(uri);
          if (_downloadCancelled) break;
          if (response.statusCode == 200) {
            archive.addFile(
              arch.ArchiveFile(
                entry.path,
                response.bodyBytes.length,
                response.bodyBytes,
              ),
            );
            fetched++;
          } else {
            failed++;
          }
        } catch (_) {
          failed++;
        }
        progressValue.value = (fetched + failed) / total;
        progressNotifier.value =
            'Downloading ${fetched + failed}/$total files...';
      }

      if (_downloadCancelled) {
        _isDownloading = false;
        _downloadCancelled = false;
        ToastService.showInfo('Download cancelled');
        return;
      }

      if (fetched == 0) {
        if (mounted) Navigator.of(context).pop();
        ToastService.showError('Failed to download any files');
        return;
      }

      progressNotifier.value = 'Creating zip...';
      progressValue.value = 0;

      await Future.delayed(const Duration(milliseconds: 50));

      final zipBytes = arch.ZipEncoder().encode(archive);
      if (mounted) Navigator.of(context).pop();

      if (zipBytes == null) {
        ToastService.showError('Failed to create zip file');
        return;
      }

      final sanitized = zipName.replaceAll(RegExp(r'[^\w\s\-.]'), '_');
      web_utils.downloadBlob(Uint8List.fromList(zipBytes), '$sanitized.zip');

      ToastService.showSuccess(
        failed > 0
            ? 'Downloaded $fetched files ($failed failed)'
            : 'Downloaded $fetched files',
      );
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      ToastService.showError('Download failed: $e');
    } finally {
      _isDownloading = false;
      progressNotifier.dispose();
      progressValue.dispose();
    }
  }

  Future<void> _showFileInfo(Map<String, dynamic> file) async {
    return AppDialog.adaptive(
      context: context,
      title: file['name'] ?? 'Unknown File',
      icon: Icons.info_outline,
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _InfoRow('Size', _formatFileSize(file['size'] ?? 0)),
            _InfoRow('Uploaded', _formatDate(file['uploadedAt'])),

            const SizedBox(height: 16),
            Text(
              'Metadata',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            if (file['contributor'] != null)
              _InfoRow('Contributor', file['contributor']),

            if (file['driveName'] != null) _InfoRow('Drive', file['driveName']),

            if (file['course_codes'] != null &&
                (file['course_codes'] as List).isNotEmpty)
              _InfoRow(
                'Course',
                (file['course_codes'] as List).first.toString(),
              ),

            if (file['tags'] != null && (file['tags'] as List).isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Tags',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    (file['tags'] as List<dynamic>)
                        .map(
                          (tag) => Chip(
                            label: Text(
                              tag.toString(),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            backgroundColor:
                                Theme.of(
                                  context,
                                ).colorScheme.secondaryContainer,
                          ),
                        )
                        .toList(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        AppButton(
          label: 'Close',
          variant: AppButtonVariant.ghost,
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Future<void> _showSubmitDialog() async {
    return AppDialog.adaptive(
      context: context,
      title: 'Submit Academic Resource',
      icon: Icons.cloud_upload,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Share your notes, papers, or other academic materials with the community',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
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
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onTap: () => Navigator.of(context).pop(),
        ),
        AppButton(label: 'Submit', onTap: _isSubmitting ? null : _submitLink),
      ],
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

      await _drivesService.submitDriveLink(submissionData);

      ToastService.showSuccess(
        '✅ Thank you! Your submission has been received and is pending approval.',
      );

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

  static IconData _getFileIconData(String mimeType) {
    final mt = mimeType.toLowerCase();
    if (mt.contains('pdf')) return Icons.picture_as_pdf_rounded;
    if (mt.contains('image')) return Icons.image_rounded;
    if (mt.contains('video')) return Icons.videocam_rounded;
    if (mt.contains('audio')) return Icons.audiotrack_rounded;
    if (mt.contains('spreadsheet') ||
        mt.contains('excel') ||
        mt.contains('csv')) {
      return Icons.table_chart_rounded;
    }
    if (mt.contains('presentation') || mt.contains('powerpoint')) {
      return Icons.slideshow_rounded;
    }
    if (mt.contains('document') ||
        mt.contains('word') ||
        mt.contains('msword')) {
      return Icons.article_rounded;
    }
    if (mt.contains('zip') || mt.contains('rar') || mt.contains('compressed')) {
      return Icons.folder_zip_rounded;
    }
    if (mt.contains('text')) return Icons.description_rounded;
    return Icons.insert_drive_file_rounded;
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _showCourseSortDialog() {
    AppDialog.adaptive(
      context: context,
      title: 'Sort Courses',
      icon: Icons.sort,
      content: RadioGroup<CourseSortOption>(
        groupValue: _courseSortOption,
        onChanged: (value) {
          if (value == null) return;
          setState(() => _courseSortOption = value);
          Navigator.pop(context);
          if (_searchQuery.isEmpty) _loadCourses();
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children:
              CourseSortOption.values.map((option) {
                final (title, subtitle, icon) = switch (option) {
                  CourseSortOption.nameAsc => (
                    'Name A-Z',
                    'Sort by course name ascending',
                    Icons.sort_by_alpha,
                  ),
                  CourseSortOption.nameDesc => (
                    'Name Z-A',
                    'Sort by course name descending',
                    Icons.sort_by_alpha,
                  ),
                  CourseSortOption.fileCountAsc => (
                    'Files Count ↑',
                    'Sort by file count ascending',
                    Icons.trending_up,
                  ),
                  CourseSortOption.fileCountDesc => (
                    'Files Count ↓',
                    'Sort by file count descending',
                    Icons.trending_down,
                  ),
                };
                return RadioListTile<CourseSortOption>(
                  value: option,
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
    AppDialog.adaptive(
      context: context,
      title: 'Sort Files',
      icon: Icons.sort,
      content: RadioGroup<FileSortOption>(
        groupValue: _fileSortOption,
        onChanged: (value) {
          if (value == null) return;
          setState(() => _fileSortOption = value);
          Navigator.pop(context);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children:
              FileSortOption.values.map((option) {
                final (title, subtitle, icon) = switch (option) {
                  FileSortOption.nameAsc => (
                    'Name A-Z',
                    'Sort by filename ascending',
                    Icons.sort_by_alpha,
                  ),
                  FileSortOption.nameDesc => (
                    'Name Z-A',
                    'Sort by filename descending',
                    Icons.sort_by_alpha,
                  ),
                  FileSortOption.dateAsc => (
                    'Date Oldest',
                    'Sort by upload date ascending',
                    Icons.schedule,
                  ),
                  FileSortOption.dateDesc => (
                    'Date Newest',
                    'Sort by upload date descending',
                    Icons.schedule,
                  ),
                  FileSortOption.sizeAsc => (
                    'Size Smallest',
                    'Sort by file size ascending',
                    Icons.storage,
                  ),
                  FileSortOption.sizeDesc => (
                    'Size Largest',
                    'Sort by file size descending',
                    Icons.storage,
                  ),
                };
                return RadioListTile<FileSortOption>(
                  value: option,
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

  Map<String, dynamic>? _courseEntryFor(String? code) {
    if (code == null) return null;
    for (final course in [..._enrolledCourseEntries, ..._courses]) {
      if (course['code'] == code) return course;
    }
    return null;
  }

  Widget _buildDrivesHero() {
    final scheme = Theme.of(context).colorScheme;
    final selectedEntry = _courseEntryFor(_selectedCourse);
    final selectedTitle = (selectedEntry?['name'] ?? '').toString();
    final bookmarks = UserSettingsService().acadDriveBookmarks.length;
    final starred = UserSettingsService().starredCourses.length;

    final title =
        _showingBookmarks
            ? 'Your saved resource shelf'
            : _selectedCourse != null
            ? _selectedCourse!
            : 'Find the material behind every course';
    final description =
        _showingBookmarks
            ? 'Everything you bookmarked, collected in one focused view.'
            : _selectedCourse != null
            ? (selectedTitle.isEmpty
                ? 'Browse folders, preview file details, or open the source drive.'
                : '$selectedTitle · Browse folders, files, and source drives.')
            : 'Past papers, slides, notes, and student-contributed drives in one searchable library.';

    return AcadDrivesHeader(
      icon:
          _showingBookmarks
              ? Icons.bookmarks_rounded
              : _selectedCourse != null
              ? Icons.folder_open_rounded
              : Icons.local_library_rounded,
      eyebrow:
          _showingBookmarks
              ? 'Saved resources'
              : _selectedCourse != null
              ? 'Course library'
              : 'Academic drives',
      title: title,
      description: description,
      accent: scheme.tertiary,
      metrics:
          _selectedCourse != null && !_showingBookmarks
              ? [
                AcadDrivesMetric(
                  value: '${_courseFiles.length}',
                  label: 'files loaded',
                  icon: Icons.description_outlined,
                ),
                AcadDrivesMetric(
                  value: '${_selectedDriveLinks.length}',
                  label: 'source drives',
                  icon: Icons.cloud_outlined,
                ),
                AcadDrivesMetric(
                  value: '$bookmarks',
                  label: 'bookmarked',
                  icon: Icons.bookmark_outline_rounded,
                ),
              ]
              : [
                AcadDrivesMetric(
                  value:
                      '${_totalCourseCount > 0 ? _totalCourseCount : _courses.length}',
                  label: 'courses',
                  icon: Icons.menu_book_rounded,
                ),
                AcadDrivesMetric(
                  value: '$starred',
                  label: 'starred',
                  icon: Icons.star_outline_rounded,
                ),
                AcadDrivesMetric(
                  value: '$bookmarks',
                  label: 'bookmarked',
                  icon: Icons.bookmark_outline_rounded,
                ),
              ],
      actions: [
        OutlinedButton.icon(
          onPressed: _showingBookmarks ? _goBackToCourses : _loadBookmarks,
          icon: Badge(
            isLabelVisible: !_showingBookmarks && bookmarks > 0,
            label: Text('$bookmarks'),
            child: Icon(
              _showingBookmarks
                  ? Icons.arrow_back_rounded
                  : Icons.bookmarks_outlined,
              size: 18,
            ),
          ),
          label: Text(_showingBookmarks ? 'All courses' : 'Bookmarks'),
        ),
        FilledButton.icon(
          key: TutorialKeys.acadDrivesSubmit,
          onPressed: _showSubmitDialog,
          icon: const Icon(Icons.add_link_rounded, size: 18),
          label: const Text('Submit resource'),
        ),
      ],
    );
  }

  void _onResourceSearchChanged(String value) {
    final wasEmpty = _searchQuery.isEmpty;
    final isNowEmpty = value.isEmpty;
    setState(() => _searchQuery = value);
    if (_selectedCourse == null && !_showingBookmarks) {
      if (wasEmpty && !isNowEmpty) {
        _loadAllCoursesForSearch();
      } else if (!wasEmpty && isNowEmpty) {
        _loadCourses();
      }
    }
  }

  void _clearResourceSearch() {
    _searchController.clear();
    final wasSearching = _searchQuery.isNotEmpty;
    setState(() => _searchQuery = '');
    if (_selectedCourse == null && !_showingBookmarks && wasSearching) {
      _loadCourses();
    }
  }

  Widget _buildResourceToolbar() {
    final scheme = Theme.of(context).colorScheme;
    return AcadDrivesToolbar(
      key: TutorialKeys.acadDrivesSearch,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final search = Semantics(
            label: 'Search Acad Drives',
            textField: true,
            child: TextField(
              controller: _searchController,
              onChanged: _onResourceSearchChanged,
              decoration: AppDesign.inputDecoration(
                context,
                dense: true,
                hint:
                    _showingBookmarks
                        ? 'Search bookmarked files'
                        : _selectedCourse != null
                        ? 'Search files in $_selectedCourse'
                        : 'Search course code or title',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon:
                    _searchController.text.isNotEmpty
                        ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: _clearResourceSearch,
                          tooltip: 'Clear search',
                        )
                        : null,
              ),
            ),
          );
          final showSort =
              _selectedCourse != null || _showingBookmarks
                  ? _showFileSortDialog
                  : _showCourseSortDialog;
          final sort = OutlinedButton.icon(
            onPressed: showSort,
            icon: const Icon(Icons.swap_vert_rounded, size: 18),
            label: const Text('Sort'),
          );
          if (constraints.maxWidth < 560) {
            return Row(
              children: [
                Expanded(child: search),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: showSort,
                  icon: const Icon(Icons.swap_vert_rounded, size: 20),
                  tooltip: 'Sort resources',
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 10),
              Text(
                _selectedCourse != null || _showingBookmarks
                    ? '${_filteredFiles.length} resources'
                    : '${_filteredCourses.length} courses',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 10),
              sort,
            ],
          );
        },
      ),
    );
  }

  Widget _buildDesktopCourseNavigator() {
    final scheme = Theme.of(context).colorScheme;
    final starredCodes = UserSettingsService().starredCourses;
    final courses = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final course in [..._enrolledCourseEntries, ..._courses]) {
      final code = (course['code'] ?? '').toString();
      if (code.isNotEmpty && seen.add(code)) courses.add(course);
    }

    return Container(
      width: 350,
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: .9),
        borderRadius: AppDesign.borderRadiusXl,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .75)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 17, 12, 10),
            child: AcadDrivesSectionTitle(
              title: 'Courses',
              caption: '${courses.length} currently loaded',
              trailing: IconButton(
                onPressed: _goBackToCourses,
                icon: const Icon(Icons.grid_view_rounded, size: 20),
                tooltip: 'Open full course library',
              ),
            ),
          ),
          Divider(
            height: 1,
            color: scheme.outlineVariant.withValues(alpha: .6),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: courses.length,
              itemBuilder: (context, index) {
                final course = courses[index];
                final code = (course['code'] ?? '').toString();
                return _CourseCard(
                  course: course,
                  compact: true,
                  selected: code == _selectedCourse,
                  enrolled: _enrolledCourseCodes.contains(code),
                  starred: starredCodes.contains(code),
                  onTap: () => _loadCourseFiles(code),
                  onToggleStar: () {
                    UserSettingsService().toggleStarredCourse(code);
                    setState(() {});
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResourcePane() {
    final scheme = Theme.of(context).colorScheme;
    final selectedEntry = _courseEntryFor(_selectedCourse);
    final title = (selectedEntry?['name'] ?? '').toString();
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: .9),
        borderRadius: AppDesign.borderRadiusXl,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .75)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 17, 12, 12),
            child: AcadDrivesSectionTitle(
              title: _selectedCourse ?? 'Resources',
              caption: title.isEmpty ? 'Folders and files' : title,
              trailing: IconButton(
                onPressed: () => _loadCourseFiles(_selectedCourse!),
                icon: const Icon(Icons.refresh_rounded, size: 20),
                tooltip: 'Refresh resources',
              ),
            ),
          ),
          Divider(
            height: 1,
            color: scheme.outlineVariant.withValues(alpha: .6),
          ),
          Expanded(child: _buildFilesView()),
        ],
      ),
    );
  }

  Widget _buildResponsiveContent(bool wide) {
    if (_showingBookmarks) return _buildBookmarksView();
    if (_selectedCourse == null) return _buildCoursesView();
    if (!wide) return _buildFilesView();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDesktopCourseNavigator(),
          const SizedBox(width: 16),
          Expanded(child: _buildResourcePane()),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = ResponsiveService.isMobile(context);
    return Scaffold(
      appBar: AppDesign.appBar(
        context,
        title: 'Academic Drives',
        leading:
            mobile && (_selectedCourse != null || _showingBookmarks)
                ? IconButton(
                  onPressed: _goBackToCourses,
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: 'Back to courses',
                )
                : null,
        actions: [
          PageInfoHelper.infoButton(
            context,
            PageInfoHelper.acadDrives,
            key: TutorialKeys.infoAcadDrives,
          ),
          const SizedBox(width: AppDesign.spacingSm),
        ],
      ),
      body: AcadDrivesPageBackground(
        accent: Theme.of(context).colorScheme.tertiary,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1050;
            return Column(
              children: [
                if (!mobile)
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1320),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildDrivesHero().motionEntry(),
                            const SizedBox(height: 14),
                            _buildResourceToolbar(),
                            const SizedBox(height: 10),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1320),
                      child: AnimatedSwitcher(
                        duration: AppDesign.motionStandard,
                        switchInCurve: AppDesign.curveStandard,
                        switchOutCurve: AppDesign.curveStandard,
                        child: KeyedSubtree(
                          key: ValueKey(
                            _showingBookmarks
                                ? '_bookmarks'
                                : (_selectedCourse ?? '_courses'),
                          ),
                          child: _buildResponsiveContent(wide),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMobileResourceToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: _buildResourceToolbar(),
    );
  }

  Widget _buildMobileResourceState(
    Widget child, {
    required Future<void> Function() onRefresh,
  }) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildMobileResourceToolbar()),
          SliverFillRemaining(hasScrollBody: false, child: child),
        ],
      ),
    );
  }

  Widget _buildCoursesView() {
    final isMobile = ResponsiveService.isMobile(context);
    if (_isLoading) {
      final skeleton = AcadDrivesSkeleton(grid: !isMobile);
      return isMobile
          ? _buildMobileResourceState(skeleton, onRefresh: _loadCourses)
          : skeleton;
    }

    final courses = _filteredCourses;

    if (courses.isEmpty) {
      final empty = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.school_outlined,
              size: 64,
              color: AppDesign.muted(context),
            ),
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
      return isMobile
          ? _buildMobileResourceState(empty, onRefresh: _loadCourses)
          : empty;
    }

    final enrolledCount = _enrolledCourseCount;
    final hasEnrolledSection = enrolledCount > 0;

    // Split courses into enrolled and rest
    final enrolledCourses =
        hasEnrolledSection
            ? courses.sublist(0, enrolledCount)
            : <Map<String, dynamic>>[];
    final restCourses =
        hasEnrolledSection ? courses.sublist(enrolledCount) : courses;

    Widget sectionHeader(
      String text,
      IconData icon, {
      Key? key,
      int? count,
      bool? expanded,
      VoidCallback? onToggle,
    }) {
      final scheme = Theme.of(context).colorScheme;
      return AppTappable(
        key: key,
        onTap: onToggle,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            children: [
              Icon(icon, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                text,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text(
                  '($count)',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
              const Spacer(),
              if (expanded != null)
                AnimatedRotation(
                  turns: expanded ? 0.0 : -0.25,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  child: Icon(
                    Icons.expand_more,
                    size: 18,
                    color: scheme.primary.withValues(alpha: 0.7),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    final starredCodes = UserSettingsService().starredCourses;
    final starredCourseEntries =
        _searchQuery.isEmpty
            ? courses.where((c) => starredCodes.contains(c['code'])).toList()
            : <Map<String, dynamic>>[];
    final hasStarred = starredCourseEntries.isNotEmpty;

    Widget courseCardWithStar(
      Map<String, dynamic> course, {
      bool compact = false,
      bool enrolled = false,
    }) {
      final code = course['code'] ?? '';
      return _CourseCard(
        course: course,
        onTap: () => _loadCourseFiles(code),
        compact: compact,
        enrolled: enrolled,
        starred: starredCodes.contains(code),
        onToggleStar: () {
          UserSettingsService().toggleStarredCourse(code);
          setState(() {});
        },
      );
    }

    Widget collapsibleSection(
      List<Map<String, dynamic>> items, {
      required bool expanded,
      bool enrolled = false,
      bool useGrid = false,
    }) {
      return SliverToBoxAdapter(
        child: AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          clipBehavior: Clip.hardEdge,
          child:
              !expanded
                  ? const SizedBox(width: double.infinity)
                  : useGrid
                  ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children:
                          items
                              .map(
                                (course) => SizedBox(
                                  width: 360,
                                  height: 116,
                                  child: courseCardWithStar(
                                    course,
                                    compact: true,
                                    enrolled: enrolled,
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                  )
                  : Column(
                    children:
                        items
                            .map(
                              (course) => courseCardWithStar(
                                course,
                                enrolled: enrolled,
                              ),
                            )
                            .toList(),
                  ),
        ),
      );
    }

    if (isMobile) {
      return RefreshIndicator(
        onRefresh: _loadCourses,
        child: CustomScrollView(
          controller: _coursesScrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(),
          scrollCacheExtent: ScrollCacheExtent.pixels(800),
          slivers: [
            SliverToBoxAdapter(child: _buildMobileResourceToolbar()),
            SliverToBoxAdapter(child: _buildCourseCountBar(courses.length)),
            if (hasStarred) ...[
              SliverToBoxAdapter(
                child: sectionHeader(
                  'Starred',
                  Icons.star_rounded,
                  count: starredCourseEntries.length,
                  expanded: _starredExpanded,
                  onToggle:
                      () =>
                          setState(() => _starredExpanded = !_starredExpanded),
                ),
              ),
              collapsibleSection(
                starredCourseEntries,
                expanded: _starredExpanded,
              ),
            ],
            if (hasEnrolledSection) ...[
              SliverToBoxAdapter(
                child: sectionHeader(
                  'Your Courses',
                  Icons.school,
                  key: TutorialKeys.acadDrivesYourCourses,
                  count: enrolledCount,
                  expanded: _yourCoursesExpanded,
                  onToggle:
                      () => setState(
                        () => _yourCoursesExpanded = !_yourCoursesExpanded,
                      ),
                ),
              ),
              collapsibleSection(
                enrolledCourses,
                expanded: _yourCoursesExpanded,
                enrolled: true,
              ),
            ],
            if (hasEnrolledSection || hasStarred)
              SliverToBoxAdapter(
                child: sectionHeader('All Courses', Icons.library_books),
              ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index >= restCourses.length) {
                    return _buildLoadingFooter();
                  }
                  // No per-item entrance animation: this list is lazy and
                  // paginated, so animating on build re-fades cards every
                  // time they scroll back into view.
                  return courseCardWithStar(restCourses[index]);
                },
                childCount:
                    restCourses.length +
                    (_hasMoreCourses && _searchQuery.isEmpty ? 1 : 0),
              ),
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
          ],
        ),
      );
    }

    // Desktop: grid layout
    return Column(
      children: [
        _buildCourseCountBar(courses.length),
        Expanded(
          child: CustomScrollView(
            controller: _coursesScrollController,
            slivers: [
              if (hasStarred) ...[
                SliverToBoxAdapter(
                  child: sectionHeader(
                    'Starred',
                    Icons.star_rounded,
                    count: starredCourseEntries.length,
                    expanded: _starredExpanded,
                    onToggle:
                        () => setState(
                          () => _starredExpanded = !_starredExpanded,
                        ),
                  ),
                ),
                collapsibleSection(
                  starredCourseEntries,
                  expanded: _starredExpanded,
                  useGrid: true,
                ),
              ],
              if (hasEnrolledSection) ...[
                SliverToBoxAdapter(
                  child: sectionHeader(
                    'Your Courses',
                    Icons.school,
                    key: TutorialKeys.acadDrivesYourCourses,
                    count: enrolledCount,
                    expanded: _yourCoursesExpanded,
                    onToggle:
                        () => setState(
                          () => _yourCoursesExpanded = !_yourCoursesExpanded,
                        ),
                  ),
                ),
                collapsibleSection(
                  enrolledCourses,
                  expanded: _yourCoursesExpanded,
                  enrolled: true,
                  useGrid: true,
                ),
              ],
              if (hasEnrolledSection || hasStarred)
                SliverToBoxAdapter(
                  child: sectionHeader('All Courses', Icons.library_books),
                ),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index >= restCourses.length) {
                        return _buildLoadingFooter();
                      }
                      return courseCardWithStar(
                        restCourses[index],
                        compact: true,
                      );
                    },
                    childCount:
                        restCourses.length +
                        (_hasMoreCourses && _searchQuery.isEmpty ? 1 : 0),
                  ),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 360,
                    mainAxisExtent: 124,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCourseCountBar(int shown) {
    final total = _searchQuery.isNotEmpty ? shown : _totalCourseCount;
    final label =
        _searchQuery.isNotEmpty
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
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
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

  Widget _buildBookmarksView() {
    final mobile = ResponsiveService.isMobile(context);
    if (_isLoadingFiles) {
      const skeleton = GenericListSkeleton(count: 8, itemHeight: 56);
      return mobile
          ? _buildMobileResourceState(skeleton, onRefresh: _loadBookmarks)
          : skeleton;
    }

    if (_bookmarkedFiles.isEmpty) {
      final empty = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bookmark_border_rounded,
              size: 64,
              color: AppDesign.muted(context),
            ),
            const SizedBox(height: 16),
            Text(
              'No bookmarks yet',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppDesign.muted(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Bookmark files from any course for quick access',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppDesign.muted(context)),
            ),
          ],
        ),
      );
      return mobile
          ? _buildMobileResourceState(empty, onRefresh: _loadBookmarks)
          : empty;
    }

    final filtered =
        _searchQuery.isEmpty
            ? _bookmarkedFiles
            : _bookmarkedFiles.where((file) {
              final name = (file['name'] ?? '').toString().toLowerCase();
              final course =
                  (file['courseName'] ?? '').toString().toLowerCase();
              final code =
                  ((file['course_codes'] as List?)?.firstOrNull ?? '')
                      .toString()
                      .toLowerCase();
              final q = _searchQuery.toLowerCase();
              return name.contains(q) || course.contains(q) || code.contains(q);
            }).toList();

    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: filtered.length + (mobile ? 1 : 0),
      itemBuilder: (context, index) {
        if (mobile && index == 0) return _buildMobileResourceToolbar();
        final fileIndex = index - (mobile ? 1 : 0);
        final file = filtered[fileIndex];
        final fileId = file['id'] as String? ?? '';
        final codes = (file['course_codes'] as List?)?.join(', ') ?? '';
        return Column(
          children: [
            if (codes.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(left: 16, top: fileIndex == 0 ? 8 : 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    codes,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            _FileCard(
              file: file,
              onOpen: (type) => _openFile(file, type),
              onInfo: () => _showFileInfo(file),
              formatFileSize: _formatFileSize,
              formatDate: _formatDate,
              isBookmarked: true,
              onToggleBookmark: () {
                _toggleBookmark(fileId);
                setState(() {
                  _bookmarkedFiles.removeWhere((f) => f['id'] == fileId);
                });
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilesView() {
    final mobile = ResponsiveService.isMobile(context);
    Future<void> refresh() => _loadCourseFiles(_selectedCourse!);
    if (_isLoadingFiles) {
      const skeleton = GenericListSkeleton(count: 8, itemHeight: 56);
      return mobile
          ? _buildMobileResourceState(skeleton, onRefresh: refresh)
          : skeleton;
    }

    final files = _filteredFiles;

    if (files.isEmpty) {
      final empty = Center(
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
      return mobile
          ? _buildMobileResourceState(empty, onRefresh: refresh)
          : empty;
    }

    // Group files by driveName and then create hierarchical folder structure
    final Map<String, _FolderTree> driveTrees = {};
    final Map<String, String> driveContributors = {};
    for (final file in files) {
      final driveName = file['driveName'] as String? ?? 'Unknown Drive';
      final path = file['path'] as String? ?? '';
      final contributor = file['contributor'] as String?;

      // Track contributor per drive (use the first one found)
      if (contributor != null &&
          contributor.isNotEmpty &&
          !driveContributors.containsKey(driveName)) {
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
      onRefresh: refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.extentAfter < 320 &&
              _hasMoreFiles &&
              !_isLoadingMoreFiles) {
            _loadMoreFiles();
          }
          return false;
        },
        child: ListView.builder(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemCount:
              driveNames.length +
              (mobile ? 1 : 0) +
              ((_hasMoreFiles || _isLoadingMoreFiles) ? 1 : 0),
          itemBuilder: (context, index) {
            if (mobile && index == 0) return _buildMobileResourceToolbar();
            final contentIndex = index - (mobile ? 1 : 0);
            if (contentIndex >= driveNames.length) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child:
                      _isLoadingMoreFiles
                          ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : OutlinedButton.icon(
                            onPressed: _loadMoreFiles,
                            icon: const Icon(
                              Icons.expand_more_rounded,
                              size: 18,
                            ),
                            label: Text('Load $_filePageSize more files'),
                          ),
                ),
              );
            }
            final driveName = driveNames[contentIndex];
            final folderTree = driveTrees[driveName]!;
            final contributor = driveContributors[driveName];

            return _DriveHierarchySection(
              driveName: driveName,
              contributor: contributor,
              driveLink: _selectedDriveLinks[driveName] as String?,
              folderTree: folderTree,
              onOpenFile: (file, type) => _openFile(file, type),
              onShowFileInfo: (file) => _showFileInfo(file),
              formatFileSize: _formatFileSize,
              formatDate: _formatDate,
              onDownloadZip: _downloadAsZip,
              isBookmarked:
                  (fileId) =>
                      UserSettingsService().isAcadDriveBookmarked(fileId),
              onToggleBookmark: (fileId) => _toggleBookmark(fileId),
            );
          },
        ),
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({
    required this.course,
    required this.onTap,
    this.compact = false,
    this.enrolled = false,
    this.starred = false,
    this.selected = false,
    this.onToggleStar,
  });

  final Map<String, dynamic> course;
  final VoidCallback onTap;
  final bool compact;
  final bool enrolled;
  final bool starred;
  final bool selected;
  final VoidCallback? onToggleStar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final code = (course['code'] ?? 'Unknown Course').toString();
    final title = (course['name'] ?? '').toString();
    final fileCount = course['fileCount'] ?? 0;
    final driveCount = course['driveCount'] ?? 0;
    final accent = selected ? scheme.tertiary : scheme.primary;

    return Padding(
      padding:
          compact
              ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
              : const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppDesign.borderRadiusLg,
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.fromLTRB(13, 12, 9, 12),
            decoration: BoxDecoration(
              color:
                  selected
                      ? scheme.tertiaryContainer.withValues(alpha: .35)
                      : enrolled
                      ? scheme.primaryContainer.withValues(alpha: .2)
                      : scheme.surface.withValues(alpha: .92),
              borderRadius: AppDesign.borderRadiusLg,
              border: Border.all(
                color:
                    selected
                        ? scheme.tertiary.withValues(alpha: .46)
                        : enrolled
                        ? scheme.primary.withValues(alpha: .28)
                        : scheme.outlineVariant.withValues(alpha: .7),
              ),
              boxShadow:
                  selected
                      ? [
                        BoxShadow(
                          color: scheme.tertiary.withValues(alpha: .1),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ]
                      : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        accent.withValues(alpha: .19),
                        accent.withValues(alpha: .07),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.menu_book_rounded, size: 21, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        code,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (title.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          title,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: [
                          _ResourceCount(
                            icon: Icons.description_outlined,
                            label: '$fileCount',
                          ),
                          _ResourceCount(
                            icon: Icons.cloud_outlined,
                            label: '$driveCount',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (onToggleStar != null)
                  IconButton(
                    onPressed: onToggleStar,
                    icon: Icon(
                      starred ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 21,
                    ),
                    color:
                        starred
                            ? scheme.tertiary
                            : scheme.onSurfaceVariant.withValues(alpha: .5),
                    tooltip: starred ? 'Remove star' : 'Star course',
                  ),
                Icon(
                  selected
                      ? Icons.arrow_forward_rounded
                      : Icons.chevron_right_rounded,
                  size: 19,
                  color: accent.withValues(alpha: .8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResourceCount extends StatelessWidget {
  const _ResourceCount({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tint = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: tint.withValues(alpha: .78)),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: tint),
        ),
      ],
    );
  }
}

class _FileCard extends StatelessWidget {
  const _FileCard({
    required this.file,
    required this.onOpen,
    required this.onInfo,
    required this.formatFileSize,
    required this.formatDate,
    this.isBookmarked = false,
    this.onToggleBookmark,
  });

  final Map<String, dynamic> file;
  final Function(String) onOpen;
  final VoidCallback onInfo;
  final String Function(int) formatFileSize;
  final String Function(dynamic) formatDate;
  final bool isBookmarked;
  final VoidCallback? onToggleBookmark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasDriveLink =
        file['folderMetadata']?['drive_link'] != null &&
        file['folderMetadata']?['drive_link'] != 'NA';
    final hasDownloadUrl =
        file['url'] != null &&
        file['url'] != 'NA' &&
        file['url'].toString().trim().isNotEmpty;
    final mimeType = (file['mimeType'] ?? '').toString();
    final icon = _AcadDrivesScreenState._getFileIconData(mimeType);
    final primaryAction =
        hasDownloadUrl
            ? 'download'
            : hasDriveLink
            ? 'drive'
            : null;

    void handleMenu(String value) {
      switch (value) {
        case 'bookmark':
          onToggleBookmark?.call();
        case 'info':
          onInfo();
        case 'drive':
          onOpen('drive');
        case 'download':
          onOpen('download');
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: primaryAction == null ? onInfo : () => onOpen(primaryAction),
          borderRadius: AppDesign.borderRadiusMd,
          child: Ink(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: .94),
              borderRadius: AppDesign.borderRadiusMd,
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: .65),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 520;
                final details = Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (file['name'] ?? 'Unknown File').toString(),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${formatFileSize(file['size'] ?? 0)}  ·  '
                        '${formatDate(file['uploadedAt'])}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );

                return Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer.withValues(alpha: .55),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        icon,
                        size: 19,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(width: 11),
                    details,
                    if (compact) ...[
                      if (isBookmarked)
                        Icon(
                          Icons.bookmark_rounded,
                          size: 18,
                          color: scheme.primary,
                        ),
                      PopupMenuButton<String>(
                        tooltip: 'File actions',
                        onSelected: handleMenu,
                        itemBuilder:
                            (context) => [
                              if (onToggleBookmark != null)
                                PopupMenuItem(
                                  value: 'bookmark',
                                  child: ListTile(
                                    leading: Icon(
                                      isBookmarked
                                          ? Icons.bookmark_remove_outlined
                                          : Icons.bookmark_add_outlined,
                                    ),
                                    title: Text(
                                      isBookmarked
                                          ? 'Remove bookmark'
                                          : 'Bookmark',
                                    ),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              const PopupMenuItem(
                                value: 'info',
                                child: ListTile(
                                  leading: Icon(Icons.info_outline_rounded),
                                  title: Text('File details'),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              if (hasDriveLink)
                                const PopupMenuItem(
                                  value: 'drive',
                                  child: ListTile(
                                    leading: Icon(Icons.open_in_new_rounded),
                                    title: Text('Open in Drive'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              if (hasDownloadUrl)
                                const PopupMenuItem(
                                  value: 'download',
                                  child: ListTile(
                                    leading: Icon(Icons.download_rounded),
                                    title: Text('Download'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                            ],
                      ),
                    ] else ...[
                      if (onToggleBookmark != null)
                        IconButton(
                          onPressed: onToggleBookmark,
                          icon: Icon(
                            isBookmarked
                                ? Icons.bookmark_rounded
                                : Icons.bookmark_border_rounded,
                            size: 20,
                          ),
                          tooltip:
                              isBookmarked ? 'Remove bookmark' : 'Bookmark',
                          color: isBookmarked ? scheme.primary : null,
                        ),
                      IconButton(
                        onPressed: onInfo,
                        icon: const Icon(Icons.info_outline_rounded, size: 20),
                        tooltip: 'File details',
                      ),
                      if (hasDriveLink)
                        IconButton(
                          onPressed: () => onOpen('drive'),
                          icon: const Icon(Icons.open_in_new_rounded, size: 20),
                          tooltip: 'Open in Drive',
                        ),
                      if (hasDownloadUrl)
                        IconButton(
                          onPressed: () => onOpen('download'),
                          icon: const Icon(Icons.download_rounded, size: 20),
                          tooltip: 'Download',
                        ),
                    ],
                  ],
                );
              },
            ),
          ),
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

  List<({String path, Map<String, dynamic> file})> collectAllFiles([
    String prefix = '',
  ]) {
    final result = <({String path, Map<String, dynamic> file})>[];
    for (final file in files) {
      final name = file['name'] ?? 'unknown';
      result.add((path: prefix.isEmpty ? name : '$prefix/$name', file: file));
    }
    for (final entry in subfolders.entries) {
      final subPrefix = prefix.isEmpty ? entry.key : '$prefix/${entry.key}';
      result.addAll(entry.value.collectAllFiles(subPrefix));
    }
    return result;
  }
}

// Hierarchical Drive Section Widget
class _DriveHierarchySection extends StatefulWidget {
  final String driveName;
  final String? contributor;
  final String? driveLink;
  final _FolderTree folderTree;
  final Function(Map<String, dynamic>, String) onOpenFile;
  final Function(Map<String, dynamic>) onShowFileInfo;
  final String Function(int) formatFileSize;
  final String Function(dynamic) formatDate;
  final Future<void> Function(String zipName, _FolderTree folderTree)
  onDownloadZip;
  final bool Function(String)? isBookmarked;
  final Function(String)? onToggleBookmark;

  const _DriveHierarchySection({
    required this.driveName,
    this.contributor,
    this.driveLink,
    required this.folderTree,
    required this.onOpenFile,
    required this.onShowFileInfo,
    required this.formatFileSize,
    required this.formatDate,
    required this.onDownloadZip,
    this.isBookmarked,
    this.onToggleBookmark,
  });

  @override
  State<_DriveHierarchySection> createState() => _DriveHierarchySectionState();
}

class _DriveHierarchySectionState extends State<_DriveHierarchySection> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(10),
              bottom: _isExpanded ? Radius.zero : const Radius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    _isExpanded
                        ? Icons.folder_open_rounded
                        : Icons.folder_rounded,
                    color: scheme.onSurface.withValues(alpha: 0.5),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.driveName,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text:
                                    '${widget.folderTree.totalFileCount} file${widget.folderTree.totalFileCount == 1 ? '' : 's'}',
                              ),
                              TextSpan(
                                text:
                                    ' · ${widget.folderTree.subfolders.length} folder${widget.folderTree.subfolders.length == 1 ? '' : 's'}',
                              ),
                              if (widget.contributor != null &&
                                  widget.contributor!.isNotEmpty)
                                TextSpan(
                                  text: ' · ${widget.contributor}',
                                  style: TextStyle(fontStyle: FontStyle.italic),
                                ),
                            ],
                          ),
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.45),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.driveLink != null)
                    IconButton(
                      onPressed: () => launchUrl(Uri.parse(widget.driveLink!)),
                      icon: Icon(Icons.open_in_new_rounded, size: 18),
                      tooltip: 'Open in Google Drive',
                      visualDensity: VisualDensity.compact,
                      color: scheme.onSurface.withValues(alpha: 0.5),
                    ),
                  if (kIsWeb)
                    IconButton(
                      onPressed:
                          () => widget.onDownloadZip(
                            widget.driveName,
                            widget.folderTree,
                          ),
                      icon: Icon(Icons.download_rounded, size: 18),
                      tooltip: 'Download all files as zip',
                      visualDensity: VisualDensity.compact,
                      color: scheme.onSurface.withValues(alpha: 0.5),
                    ),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: scheme.onSurface.withValues(alpha: 0.4),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          AnimatedCrossFade(
            duration: AppDesign.animDurationNormal,
            sizeCurve: AppDesign.animCurve,
            crossFadeState:
                _isExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: [
                Divider(
                  height: 1,
                  color: scheme.outlineVariant.withValues(alpha: 0.3),
                ),
                _FolderNode(
                  folderTree: widget.folderTree,
                  level: 0,
                  onOpenFile: widget.onOpenFile,
                  onShowFileInfo: widget.onShowFileInfo,
                  formatFileSize: widget.formatFileSize,
                  formatDate: widget.formatDate,
                  onDownloadZip: widget.onDownloadZip,
                  isBookmarked: widget.isBookmarked,
                  onToggleBookmark: widget.onToggleBookmark,
                ),
              ],
            ),
          ),
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
  final Future<void> Function(String zipName, _FolderTree folderTree)
  onDownloadZip;
  final bool Function(String)? isBookmarked;
  final Function(String)? onToggleBookmark;

  const _FolderNode({
    required this.folderTree,
    required this.level,
    this.folderName,
    required this.onOpenFile,
    required this.onShowFileInfo,
    required this.formatFileSize,
    required this.formatDate,
    required this.onDownloadZip,
    this.isBookmarked,
    this.onToggleBookmark,
  });

  @override
  State<_FolderNode> createState() => _FolderNodeState();
}

class _FolderNodeState extends State<_FolderNode> {
  final Map<String, bool> _folderExpanded = {};

  @override
  Widget build(BuildContext context) {
    final subfolderNames =
        widget.folderTree.subfolders.keys.toList()..sort(_naturalSort);

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
                onTap:
                    () => setState(
                      () => _folderExpanded[folderName] = !isExpanded,
                    ),
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
                          style: Theme.of(
                            context,
                          ).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: _getFolderTextColor(context, widget.level),
                          ),
                        ),
                      ),
                      Text(
                        '${subfolder.totalFileCount}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      if (kIsWeb)
                        IconButton(
                          onPressed:
                              () => widget.onDownloadZip(folderName, subfolder),
                          icon: Icon(Icons.download_rounded, size: 16),
                          tooltip: 'Download folder as zip',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          padding: EdgeInsets.zero,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.45),
                        ),
                      const SizedBox(width: 4),
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
              AnimatedCrossFade(
                duration: AppDesign.animDurationNormal,
                sizeCurve: AppDesign.animCurve,
                crossFadeState:
                    isExpanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                firstChild: const SizedBox.shrink(),
                secondChild: _FolderNode(
                  folderTree: subfolder,
                  level: widget.level + 1,
                  folderName: folderName,
                  onOpenFile: widget.onOpenFile,
                  onShowFileInfo: widget.onShowFileInfo,
                  formatFileSize: widget.formatFileSize,
                  formatDate: widget.formatDate,
                  onDownloadZip: widget.onDownloadZip,
                  isBookmarked: widget.isBookmarked,
                  onToggleBookmark: widget.onToggleBookmark,
                ),
              ),
            ],
          );
        }),

        // Render files at this level
        ...widget.folderTree.files.map((file) {
          final fileId = file['id'] as String? ?? '';
          return Container(
            margin: EdgeInsets.only(left: 16.0 + (widget.level * 20.0)),
            child: _FileCard(
              file: file,
              onOpen: (type) => widget.onOpenFile(file, type),
              onInfo: () => widget.onShowFileInfo(file),
              formatFileSize: widget.formatFileSize,
              formatDate: widget.formatDate,
              isBookmarked: widget.isBookmarked?.call(fileId) ?? false,
              onToggleBookmark:
                  widget.onToggleBookmark != null && fileId.isNotEmpty
                      ? () => widget.onToggleBookmark!(fileId)
                      : null,
            ),
          );
        }),
      ],
    );
  }

  Color _getFolderBackgroundColor(BuildContext context, int level) {
    final scheme = Theme.of(context).colorScheme;
    final alpha = (0.04 + level * 0.02).clamp(0.0, 0.1);
    return scheme.onSurface.withValues(alpha: alpha);
  }

  Color _getFolderIconColor(BuildContext context, int level) {
    return Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45);
  }

  Color _getFolderTextColor(BuildContext context, int level) {
    return Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75);
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
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
