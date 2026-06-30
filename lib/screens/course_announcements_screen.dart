import 'dart:async';
import '../utils/web_utils.dart' as web_utils;
import 'package:flutter/material.dart';
import '../models/announcement_flag.dart';
import '../models/announcement_source.dart';
import '../models/announcement_user_state.dart';
import '../models/announcement_verification.dart';
import '../models/course_announcement.dart';
import '../models/timetable.dart';
import '../models/user_reputation.dart';
import '../services/data/auth_service.dart';
import '../services/data/course_announcement_service.dart';
import '../services/data/reputation_service.dart';
import '../services/ui/responsive_service.dart';
import '../services/core/timetable_service.dart';
import '../services/ui/toast_service.dart';
import '../utils/design_constants.dart';
import '../widgets/common/shimmer_loading.dart';
import '../widgets/common/app_dialog.dart';
import '../utils/page_info_helper.dart';
import '../services/ui/tutorial_service.dart';


class CourseAnnouncementsScreen extends StatefulWidget {
  const CourseAnnouncementsScreen({super.key});

  @override
  State<CourseAnnouncementsScreen> createState() =>
      _CourseAnnouncementsScreenState();
}

class _CourseAnnouncementsScreenState extends State<CourseAnnouncementsScreen> {
  final CourseAnnouncementService _announcementService =
      CourseAnnouncementService();
  final TimetableService _timetableService = TimetableService();
  final AuthService _authService = AuthService();
  final ReputationService _reputationService = ReputationService();

  List<Timetable> _timetables = [];
  Timetable? _selectedTimetable;
  List<CourseAnnouncement> _allAnnouncements = [];
  List<CourseAnnouncement> _announcements = [];
  bool _isLoading = true;
  bool _showExpired = false;
  StreamSubscription? _announcementsSub;
  StreamSubscription? _repSub;
  UserReputation? _currentUserRep;
  final Map<String, TrustTier> _authorTiers = {};
  final Map<String, AnnouncementUserState> _userStates = {};

  @override
  void initState() {
    super.initState();
    _loadTimetables();
    _subscribeToReputation();
  }

  @override
  void dispose() {
    _announcementsSub?.cancel();
    _repSub?.cancel();
    super.dispose();
  }

  void _subscribeToReputation() {
    _repSub = _reputationService.watchCurrentUserReputation().listen((rep) {
      if (mounted) setState(() => _currentUserRep = rep);
    });
  }

  Future<void> _loadTimetables() async {
    setState(() => _isLoading = true);
    final timetables = await _timetableService.getAllTimetables();
    setState(() {
      _timetables = timetables;
      if (timetables.isNotEmpty) {
        _selectedTimetable = timetables.first;
        _subscribeToAnnouncements();
      } else {
        _isLoading = false;
      }
    });
  }

  void _subscribeToAnnouncements() {
    _announcementsSub?.cancel();
    final timetable = _selectedTimetable;
    if (timetable == null) {
      setState(() {
        _announcements = [];
        _isLoading = false;
      });
      return;
    }

    final courseCodes = timetable.selectedSections
        .map((s) => s.courseCode)
        .toSet()
        .toList();

    if (courseCodes.isEmpty) {
      setState(() {
        _announcements = [];
        _isLoading = false;
      });
      return;
    }

    _announcementsSub =
        _announcementService.watchAnnouncements(courseCodes).listen(
      (announcements) {
        setState(() {
          _allAnnouncements = announcements;
          _applyFilter();
          _isLoading = false;
        });
        _loadAuthorTiers();
        _loadUserStates(announcements);
      },
      onError: (e) {
        setState(() => _isLoading = false);
        ToastService.showError('Failed to load announcements');
      },
    );
  }

  void _loadUserStates(List<CourseAnnouncement> announcements) {
    final newIds =
        announcements.map((a) => a.id).where((id) => !_userStates.containsKey(id)).toList();
    if (newIds.isEmpty) return;
    _announcementService.fetchUserStates(newIds).then((states) {
      if (mounted) setState(() => _userStates.addAll(states));
    });
  }

  void _loadAuthorTiers() {
    final uids = _announcements.map((a) => a.authorUid).toSet();
    for (final uid in uids) {
      if (_authorTiers.containsKey(uid)) continue;
      _reputationService.getReputation(uid).then((rep) {
        if (mounted) setState(() => _authorTiers[uid] = rep.tier);
      });
    }
  }

  void _applyFilter() {
    if (_showExpired) {
      _announcements = List.of(_allAnnouncements);
    } else {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      _announcements = _allAnnouncements
          .where((a) => !a.eventDate.isBefore(today))
          .toList();
    }
  }

  void _onTimetableChanged(Timetable? timetable) {
    setState(() {
      _selectedTimetable = timetable;
      _isLoading = true;
    });
    _subscribeToAnnouncements();
  }

  List<String> _getCourseCodes() {
    return _selectedTimetable?.selectedSections
            .map((s) => s.courseCode)
            .toSet()
            .toList() ??
        [];
  }

  Map<String, List<String>> _getCoursesSectionsMap() {
    final map = <String, List<String>>{};
    for (final s
        in _selectedTimetable?.selectedSections ?? <SelectedSection>[]) {
      map.putIfAbsent(s.courseCode, () => []);
      if (!map[s.courseCode]!.contains(s.sectionId)) {
        map[s.courseCode]!.add(s.sectionId);
      }
    }
    return map;
  }

  // ── Dialog launchers ──────────────────────────────────────────────────

  void _showPostDialog() {
    final courseSections = _getCoursesSectionsMap();
    if (courseSections.isEmpty) {
      ToastService.showError('No courses in selected timetable');
      return;
    }
    if (_currentUserRep?.isSuspended == true) {
      ToastService.showError('You are temporarily suspended from posting');
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => _PostAnnouncementDialog(
        courseSections: courseSections,
        onPost: (title, description, courseCode, sectionId, eventDate,
            startTime, endTime, source, confidence) async {
          Navigator.pop(ctx);
          try {
            await _announcementService.postAnnouncement(
              title: title,
              description: description,
              courseCode: courseCode,
              sectionId: sectionId,
              eventDate: eventDate,
              startTime: startTime,
              endTime: endTime,
              source: source,
              confidence: confidence,
            );
            ToastService.showSuccess('Announcement posted');
          } catch (e) {
            ToastService.showError('Failed to post announcement');
          }
        },
      ),
    );
  }

  void _showFlagDialog(CourseAnnouncement announcement) {
    if (_currentUserRep?.isSuspended == true) {
      ToastService.showError('You are temporarily suspended');
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => _FlagDialog(
        onSubmit: (reason, counterSourceUrl, confidence) async {
          Navigator.pop(ctx);
          final prev = _userStates[announcement.id] ?? const AnnouncementUserState();
          setState(() {
            _userStates[announcement.id] = prev.copyWith(
              flag: () => AnnouncementFlag(
                uid: '',
                reason: reason,
                counterSourceUrl: counterSourceUrl,
                confidence: confidence,
                weight: 1,
                timestamp: DateTime.now(),
              ),
            );
          });
          try {
            await _announcementService.submitFlag(
              announcementId: announcement.id,
              reason: reason,
              counterSourceUrl: counterSourceUrl,
              confidence: confidence,
            );
            ToastService.showSuccess('Flag submitted');
          } catch (e) {
            setState(() => _userStates[announcement.id] = prev);
            ToastService.showError('Failed to submit flag');
          }
        },
      ),
    );
  }

  void _showAcceptCorrectionDialog(CourseAnnouncement announcement) {
    showDialog(
      context: context,
      builder: (ctx) => _AcceptCorrectionDialog(
        onSubmit: (correctionText, correctionSource) async {
          Navigator.pop(ctx);
          try {
            await _announcementService.acceptCorrection(
              announcementId: announcement.id,
              correctionText: correctionText,
              correctionSource: correctionSource,
            );
            ToastService.showSuccess('Correction accepted');
          } catch (e) {
            ToastService.showError('Failed to accept correction');
          }
        },
      ),
    );
  }

  Future<void> _confirmDelete(CourseAnnouncement announcement) async {
    String warning = 'Are you sure you want to delete this announcement?';
    if (announcement.isDisputed || announcement.isCorrectionAccepted) {
      warning += '\n\nThis post is ${announcement.disputeState.replaceAll('_', ' ')}. '
          'Deleting it will incur a reputation penalty.';
    }
    final confirmed = await AppDialog.confirm(
      context: context,
      title: 'Delete Announcement',
      message: warning,
      confirmLabel: 'Delete',
      isDangerous: true,
    );
    if (confirmed) {
      try {
        await _announcementService.deleteAnnouncement(announcement.id);
        ToastService.showSuccess('Announcement deleted');
      } catch (e) {
        ToastService.showError('Failed to delete announcement');
      }
    }
  }

  void _openGoogleCalendar(CourseAnnouncement announcement) {
    web_utils.openUrl(announcement.googleCalendarUrl);
  }

  // ── Formatting helpers ────────────────────────────────────────────────

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _formatEventDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _formatTimeRange(TimeOfDay start, TimeOfDay? end) {
    final s = _formatTime(start);
    if (end == null) return s;
    return '$s – ${_formatTime(end)}';
  }

  String _formatTime(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final min = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$min $period';
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppDesign.appBar(
        context,
        title: 'Announcements',
        actions: [
          PageInfoHelper.infoButton(context, PageInfoHelper.announcements, key: TutorialKeys.infoAnnouncements),
          if (_currentUserRep != null) _buildRepChip(theme),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: _selectedTimetable != null
          ? FloatingActionButton(
              onPressed: _showPostDialog,
              heroTag: 'announcements_post',
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          if (_currentUserRep?.isSuspended == true)
            _buildSuspensionBanner(theme),
          _buildTimetablePicker(theme),
          Expanded(child: _buildBody(theme)),
        ],
      ),
    );
  }

  Widget _buildRepChip(ThemeData theme) {
    final rep = _currentUserRep!;
    final tier = rep.tier;
    final color = UserReputation.tierColor(tier);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_rounded, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              '${rep.decayedScore} · ${UserReputation.tierName(tier)}',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuspensionBanner(ThemeData theme) {
    final until = _currentUserRep!.suspendedUntil;
    final daysLeft =
        until != null ? until.difference(DateTime.now()).inDays + 1 : 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: theme.colorScheme.error.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(Icons.block, size: 16, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'You are suspended from posting for $daysLeft more day${daysLeft == 1 ? '' : 's'}.',
              style: TextStyle(fontSize: 13, color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimetablePicker(ThemeData theme) {
    return Container(
      padding: ResponsiveService.getAdaptivePadding(
        context,
        const EdgeInsets.all(16),
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonFormField<String>(
        initialValue: _selectedTimetable?.id,
        decoration: InputDecoration(
          labelText: 'Select Timetable',
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        items: _timetables
            .map((t) => DropdownMenuItem(
                  value: t.id,
                  child: Text(
                    t.name.isNotEmpty ? t.name : 'Timetable ${t.id}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ))
            .toList(),
        onChanged: (id) {
          final timetable = _timetables.firstWhere((t) => t.id == id);
          _onTimetableChanged(timetable);
        },
      ),
    );
  }

  Widget _buildShowOlderToggle(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          FilterChip(
            label: const Text('Show past events'),
            selected: _showExpired,
            showCheckmark: false,
            onSelected: (value) {
              setState(() {
                _showExpired = value;
                _applyFilter();
              });
            },
            avatar: Icon(
              _showExpired ? Icons.history : Icons.history_outlined,
              size: 18,
            ),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const AnnouncementsSkeleton();
    }
    if (_timetables.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule,
                size: 64,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('Create a timetable first to see announcements',
                style: theme.textTheme.bodyLarge?.copyWith(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.6))),
          ],
        ),
      );
    }
    if (_getCourseCodes().isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.class_outlined,
                size: 64,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('Add courses to your timetable to see announcements',
                style: theme.textTheme.bodyLarge?.copyWith(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.6))),
          ],
        ),
      );
    }
    if (_announcements.isEmpty && !_showExpired) {
      return Column(
        children: [
          _buildShowOlderToggle(theme),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.campaign_outlined,
                      size: 64,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  Text('No upcoming announcements for your courses',
                      style: theme.textTheme.bodyLarge?.copyWith(
                          color:
                              theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                  const SizedBox(height: 8),
                  Text('Tap + to post one, or toggle "Show past" above',
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color:
                              theme.colorScheme.onSurface.withValues(alpha: 0.4))),
                ],
              ),
            ),
          ),
        ],
      );
    }
    if (_announcements.isEmpty && _showExpired) {
      return Column(
        children: [
          _buildShowOlderToggle(theme),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.campaign_outlined,
                      size: 64,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  Text('No announcements for your courses yet',
                      style: theme.textTheme.bodyLarge?.copyWith(
                          color:
                              theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        _buildShowOlderToggle(theme),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadTimetables,
            child: ListView.builder(
              padding: ResponsiveService.getAdaptivePadding(
                context,
                const EdgeInsets.all(16),
              ),
              itemCount: _announcements.length,
              itemBuilder: (context, index) =>
                  _buildAnnouncementCard(_announcements[index], theme),
            ),
          ),
        ),
      ],
    );
  }

  // ── Announcement card ─────────────────────────────────────────────────

  Widget _buildAnnouncementCard(
      CourseAnnouncement announcement, ThemeData theme) {
    final isAuthor =
        announcement.authorUid == _authService.userDocId;
    final authorTier = _authorTiers[announcement.authorUid];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCardHeader(announcement, theme, isAuthor),
            const SizedBox(height: 10),
            Text(
              announcement.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                decoration: announcement.isCorrectionAccepted
                    ? TextDecoration.lineThrough
                    : null,
                color: announcement.isCorrectionAccepted
                    ? theme.colorScheme.onSurface.withValues(alpha: 0.5)
                    : null,
              ),
            ),
            if (announcement.isCorrectionAccepted &&
                announcement.correctionText != null) ...[
              const SizedBox(height: 8),
              _buildCorrectionBanner(announcement, theme),
            ],
            if (announcement.isDisputed) ...[
              const SizedBox(height: 8),
              _buildDisputeBanner(announcement, theme, isAuthor),
            ],
            if (announcement.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                announcement.description,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.7)),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.event,
                    size: 15,
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.5)),
                const SizedBox(width: 4),
                Text(
                  _formatEventDate(announcement.eventDate),
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (announcement.hasTime) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.access_time,
                      size: 14,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.5)),
                  const SizedBox(width: 3),
                  Text(
                    _formatTimeRange(
                        announcement.startTime!, announcement.endTime),
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.6),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.person_outline,
                    size: 14,
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.4)),
                const SizedBox(width: 4),
                Text(
                  announcement.authorName,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.5),
                  ),
                ),
                if (authorTier != null) ...[
                  const SizedBox(width: 6),
                  _buildTierBadge(authorTier),
                ],
                const SizedBox(width: 8),
                Text(
                  _relativeTime(announcement.createdAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _buildVerificationRow(announcement, theme),
            const SizedBox(height: 10),
            _buildActionRow(announcement, theme, isAuthor),
          ],
        ),
      ),
    );
  }

  Widget _buildCardHeader(
      CourseAnnouncement announcement, ThemeData theme, bool isAuthor) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            announcement.courseCode,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        if (announcement.isSectionSpecific) ...[
          const SizedBox(width: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              announcement.sectionId,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
        if (announcement.source.isSourced) ...[
          const SizedBox(width: 6),
          _buildSourceBadge(announcement.source),
        ],
        const Spacer(),
        if (isAuthor)
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => _confirmDelete(announcement),
            visualDensity: VisualDensity.compact,
            color: theme.colorScheme.error,
            tooltip: 'Delete',
          ),
      ],
    );
  }

  Widget _buildSourceBadge(AnnouncementSource source) {
    Color color;
    switch (source.trustLevel) {
      case 'high':
        color = AppDesign.success(context);
        break;
      case 'medium':
        color = AppDesign.warning(context);
        break;
      case 'low':
        color = AppDesign.warning(context);
        break;
      default:
        color = AppDesign.muted(context);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.link, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            source.label,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildTierBadge(TrustTier tier) {
    final color = UserReputation.tierColor(tier);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        UserReputation.tierName(tier),
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  Widget _buildCorrectionBanner(
      CourseAnnouncement announcement, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppDesign.success(context).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppDesign.success(context).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, size: 16, color: AppDesign.success(context)),
              const SizedBox(width: 6),
              Text(
                'Correction',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppDesign.success(context)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            announcement.correctionText!,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
          if (announcement.correctionSource != null) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: () => web_utils.openUrl(announcement.correctionSource!),
              child: Text(
                'Source: ${announcement.correctionSource}',
                style: TextStyle(
                  fontSize: 11,
                  color: AppDesign.info(context),
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDisputeBanner(
      CourseAnnouncement announcement, ThemeData theme, bool isAuthor) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: theme.colorScheme.error.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 16, color: theme.colorScheme.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Flagged as potentially incorrect',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
          if (announcement.topFlagReason != null) ...[
            const SizedBox(height: 4),
            Text(
              'Reason: ${announcement.topFlagReason}',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.error.withValues(alpha: 0.8),
              ),
            ),
          ],
          if (isAuthor) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 30,
              child: TextButton.icon(
                onPressed: () =>
                    _showAcceptCorrectionDialog(announcement),
                icon: const Icon(Icons.edit, size: 14),
                label: const Text('Accept & Correct',
                    style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVerificationRow(
      CourseAnnouncement announcement, ThemeData theme) {
    final state = announcement.verificationState;
    final cc = announcement.confirmCount;
    final dc = announcement.denyCount;

    Color badgeColor;
    IconData badgeIcon;
    String badgeText;

    switch (state) {
      case 'community_verified':
        badgeColor = AppDesign.success(context);
        badgeIcon = Icons.verified;
        badgeText = 'Community Verified';
        break;
      case 'partially_verified':
        badgeColor = AppDesign.info(context);
        badgeIcon = Icons.check_circle_outline;
        badgeText = 'Partially Verified';
        break;
      case 'contested':
        badgeColor = AppDesign.warning(context);
        badgeIcon = Icons.warning_amber_rounded;
        badgeText = 'Contested';
        break;
      case 'likely_incorrect':
        badgeColor = AppDesign.danger(context);
        badgeIcon = Icons.error_outline;
        badgeText = 'Likely Incorrect';
        break;
      default:
        badgeColor = AppDesign.muted(context);
        badgeIcon = Icons.help_outline;
        badgeText = 'Unverified';
    }

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border:
                Border.all(color: badgeColor.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(badgeIcon, size: 13, color: badgeColor),
              const SizedBox(width: 4),
              Text(badgeText,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: badgeColor)),
              if (cc > 0 || dc > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '($cc✓ $dc✗)',
                  style: TextStyle(
                      fontSize: 10,
                      color: badgeColor.withValues(alpha: 0.7)),
                ),
              ],
            ],
          ),
        ),
        if (announcement.isStale)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: AppDesign.warning(context).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule,
                    size: 12, color: AppDesign.warning(context)),
                const SizedBox(width: 3),
                Text('Needs verification',
                    style: TextStyle(
                        fontSize: 10, color: AppDesign.warning(context))),
              ],
            ),
          ),
      ],
    );
  }

  // ── Action row ────────────────────────────────────────────────────────

  Widget _buildActionRow(
      CourseAnnouncement announcement, ThemeData theme, bool isAuthor) {
    final showModActions =
        !isAuthor && !announcement.isCorrectionAccepted;

    final userState = _userStates[announcement.id] ?? const AnnouncementUserState();
    final userVote = userState.vote;
    final hasFlag = userState.flag != null;
    final userVerif = userState.verification;
    final isConfirmed = userVerif?.type == VerificationType.confirm;
    final isDenied = userVerif?.type == VerificationType.deny;

    return Row(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _VoteButton(
              icon: Icons.arrow_upward_rounded,
              count: announcement.upvotes,
              isActive: userVote == 1,
              activeColor: AppDesign.success(context),
              onTap: () async {
                final prev = userState;
                setState(() {
                  _userStates[announcement.id] = userState.copyWith(
                    vote: () => userVote == 1 ? null : 1,
                  );
                });
                try {
                  await _announcementService.toggleVote(announcement.id, 1);
                } catch (_) {
                  if (mounted) setState(() => _userStates[announcement.id] = prev);
                }
              },
            ),
            const SizedBox(width: 4),
            _VoteButton(
              icon: Icons.arrow_downward_rounded,
              count: announcement.downvotes,
              isActive: userVote == -1,
              activeColor: AppDesign.danger(context),
              onTap: () async {
                final prev = userState;
                setState(() {
                  _userStates[announcement.id] = userState.copyWith(
                    vote: () => userVote == -1 ? null : -1,
                  );
                });
                try {
                  await _announcementService.toggleVote(announcement.id, -1);
                } catch (_) {
                  if (mounted) setState(() => _userStates[announcement.id] = prev);
                }
              },
            ),
          ],
        ),
        if (showModActions) ...[
          const SizedBox(width: 8),
          _ActionIconButton(
            icon: Icons.flag_outlined,
            activeIcon: Icons.flag,
            isActive: hasFlag,
            activeColor: AppDesign.warning(context),
            tooltip: hasFlag ? 'Already flagged' : 'Flag as incorrect',
            onTap: hasFlag ? null : () => _showFlagDialog(announcement),
          ),
          const SizedBox(width: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ActionIconButton(
                icon: Icons.check_circle_outline,
                activeIcon: Icons.check_circle,
                isActive: isConfirmed,
                activeColor: AppDesign.success(context),
                tooltip: isConfirmed ? 'Confirmed' : 'Confirm this',
                onTap: isConfirmed
                    ? null
                    : () async {
                        final prev = userState;
                        setState(() {
                          _userStates[announcement.id] = userState.copyWith(
                            verification: () => AnnouncementVerification(
                              uid: '',
                              type: VerificationType.confirm,
                              weight: 1,
                              timestamp: DateTime.now(),
                            ),
                          );
                        });
                        try {
                          await _announcementService.submitVerification(
                            announcementId: announcement.id,
                            type: VerificationType.confirm,
                          );
                        } catch (_) {
                          if (mounted) setState(() => _userStates[announcement.id] = prev);
                        }
                      },
              ),
              const SizedBox(width: 2),
              _ActionIconButton(
                icon: Icons.cancel_outlined,
                activeIcon: Icons.cancel,
                isActive: isDenied,
                activeColor: AppDesign.danger(context),
                tooltip: isDenied ? 'Denied' : 'Deny this',
                onTap: isDenied
                    ? null
                    : () async {
                        final prev = userState;
                        setState(() {
                          _userStates[announcement.id] = userState.copyWith(
                            verification: () => AnnouncementVerification(
                              uid: '',
                              type: VerificationType.deny,
                              weight: 1,
                              timestamp: DateTime.now(),
                            ),
                          );
                        });
                        try {
                          await _announcementService.submitVerification(
                            announcementId: announcement.id,
                            type: VerificationType.deny,
                          );
                        } catch (_) {
                          if (mounted) setState(() => _userStates[announcement.id] = prev);
                        }
                      },
              ),
            ],
          ),
        ],
        const Spacer(),
        TextButton.icon(
          onPressed: () => _openGoogleCalendar(announcement),
          icon: const Icon(Icons.calendar_month, size: 16),
          label: const Text('Add to Calendar'),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            textStyle: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Private widgets
// ══════════════════════════════════════════════════════════════════════════

class _VoteButton extends StatelessWidget {
  final IconData icon;
  final int count;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onTap;

  const _VoteButton({
    required this.icon,
    required this.count,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? activeColor.withValues(alpha: 0.12)
              : theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: isActive
                    ? activeColor
                    : theme.colorScheme.onSurface.withValues(alpha: 0.5)),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isActive
                    ? activeColor
                    : theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final bool isActive;
  final Color activeColor;
  final String tooltip;
  final VoidCallback? onTap;

  const _ActionIconButton({
    required this.icon,
    required this.activeIcon,
    required this.isActive,
    required this.activeColor,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            isActive ? activeIcon : icon,
            size: 18,
            color: isActive
                ? activeColor
                : onTap != null
                    ? theme.colorScheme.onSurface.withValues(alpha: 0.5)
                    : theme.colorScheme.onSurface.withValues(alpha: 0.25),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Post announcement dialog
// ══════════════════════════════════════════════════════════════════════════

class _PostAnnouncementDialog extends StatefulWidget {
  final Map<String, List<String>> courseSections;
  final Future<void> Function(
      String title,
      String description,
      String courseCode,
      String sectionId,
      DateTime eventDate,
      TimeOfDay? startTime,
      TimeOfDay? endTime,
      AnnouncementSource source,
      String confidence) onPost;

  const _PostAnnouncementDialog({
    required this.courseSections,
    required this.onPost,
  });

  @override
  State<_PostAnnouncementDialog> createState() =>
      _PostAnnouncementDialogState();
}

class _PostAnnouncementDialogState extends State<_PostAnnouncementDialog> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _sourceUrlController = TextEditingController();
  String? _selectedCourse;
  String _selectedSection = '';
  DateTime? _selectedDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  SourceType _selectedSourceType = SourceType.none;
  String _confidence = 'fairly_sure';
  bool _isPosting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _sourceUrlController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 7)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) {
      setState(() {
        _startTime = picked;
        if (_endTime != null && _toMinutes(_endTime!) <= _toMinutes(picked)) {
          _endTime = null;
        }
      });
    }
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime ??
          TimeOfDay(
            hour: (_startTime?.hour ?? 9) + 1,
            minute: _startTime?.minute ?? 0,
          ),
    );
    if (picked != null) setState(() => _endTime = picked);
  }

  int _toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  String _fmtTime(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final min = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$min $period';
  }

  bool get _canPost =>
      _titleController.text.trim().isNotEmpty &&
      _selectedCourse != null &&
      _selectedDate != null &&
      !_isPosting;

  Future<void> _post() async {
    if (!_canPost) return;
    setState(() => _isPosting = true);
    final url = _sourceUrlController.text.trim();
    final source = AnnouncementSource(
      type: _selectedSourceType,
      url: url.isNotEmpty ? url : null,
    );
    await widget.onPost(
      _titleController.text.trim(),
      _descriptionController.text.trim(),
      _selectedCourse!,
      _selectedSection,
      _selectedDate!,
      _startTime,
      _endTime,
      source,
      _confidence,
    );
  }

  static String _sourceTypeLabel(SourceType t) {
    switch (t) {
      case SourceType.none:
        return 'No source';
      case SourceType.officialLink:
        return 'Official link (website, notice)';
      case SourceType.emailScreenshot:
        return 'Email / notice screenshot';
      case SourceType.lmsLink:
        return 'LMS link';
      case SourceType.photo:
        return 'Photo evidence';
      case SourceType.crossReference:
        return 'Cross-referenced';
      case SourceType.secondhand:
        return 'Secondhand (heard from someone)';
    }
  }

  static bool _needsUrl(SourceType t) {
    return t != SourceType.none && t != SourceType.secondhand;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final courses = widget.courseSections.keys.toList()..sort();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: EdgeInsets.symmetric(
        horizontal: ResponsiveService.isMobile(context) ? 16 : (MediaQuery.of(context).size.width - 480) / 2,
        vertical: 24,
      ),
      child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Post Announcement',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: _selectedCourse,
                decoration: InputDecoration(
                  labelText: 'Course *',
                ),
                items: courses
                    .map(
                        (c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() {
                  _selectedCourse = v;
                  _selectedSection = '';
                }),
              ),
              if (_selectedCourse != null &&
                  widget.courseSections[_selectedCourse]!.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedSection.isEmpty
                      ? null
                      : _selectedSection,
                  decoration: const InputDecoration(
                    labelText: 'Section (optional)',
                  ),
                  items: [
                    const DropdownMenuItem(
                        value: '', child: Text('All sections')),
                    ...widget.courseSections[_selectedCourse]!.map(
                        (s) =>
                            DropdownMenuItem(value: s, child: Text(s))),
                  ],
                  onChanged: (v) =>
                      setState(() => _selectedSection = v ?? ''),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Title *',
                  hintText: 'e.g. Quiz postponed to next week',
                ),
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: 'Description (optional)',
                ),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(
                  _selectedDate != null
                      ? '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}'
                      : 'Pick event date *',
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickStartTime,
                      icon: const Icon(Icons.access_time, size: 18),
                      label: Text(
                        _startTime != null
                            ? _fmtTime(_startTime!)
                            : 'Start time',
                      ),
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          _startTime != null ? _pickEndTime : null,
                      icon: const Icon(Icons.access_time, size: 18),
                      label: Text(
                        _endTime != null
                            ? _fmtTime(_endTime!)
                            : 'End time',
                      ),
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  if (_startTime != null)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(() {
                        _startTime = null;
                        _endTime = null;
                      }),
                      tooltip: 'Clear times',
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(
                  color: theme.colorScheme.outlineVariant
                      .withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text('Source & Confidence',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              DropdownButtonFormField<SourceType>(
                initialValue: _selectedSourceType,
                decoration: InputDecoration(
                  labelText: 'Source (optional)',
                ),
                items: SourceType.values
                    .map((t) => DropdownMenuItem(
                        value: t, child: Text(_sourceTypeLabel(t))))
                    .toList(),
                onChanged: (v) => setState(() {
                  _selectedSourceType = v ?? SourceType.none;
                  if (!_needsUrl(_selectedSourceType)) {
                    _sourceUrlController.clear();
                  }
                }),
              ),
              if (_needsUrl(_selectedSourceType)) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _sourceUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Source URL',
                    hintText: 'https://...',
                  ),
                  keyboardType: TextInputType.url,
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _confidence,
                decoration: InputDecoration(
                  labelText: 'How sure are you?',
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'certain', child: Text('Certain')),
                  DropdownMenuItem(
                      value: 'fairly_sure',
                      child: Text('Fairly sure')),
                  DropdownMenuItem(
                      value: 'speculative',
                      child: Text('Speculative')),
                ],
                onChanged: (v) =>
                    setState(() => _confidence = v ?? 'fairly_sure'),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _canPost ? _post : null,
                    child: _isPosting
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary),
                          )
                        : const Text('Post'),
                  ),
                ],
              ),
            ],
          ),
        ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Flag dialog
// ══════════════════════════════════════════════════════════════════════════

class _FlagDialog extends StatefulWidget {
  final Future<void> Function(
      String reason, String? counterSourceUrl, String confidence) onSubmit;

  const _FlagDialog({required this.onSubmit});

  @override
  State<_FlagDialog> createState() => _FlagDialogState();
}

class _FlagDialogState extends State<_FlagDialog> {
  final _reasonController = TextEditingController();
  final _counterSourceController = TextEditingController();
  String _confidence = 'fairly_sure';
  bool _isSubmitting = false;

  @override
  void dispose() {
    _reasonController.dispose();
    _counterSourceController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _reasonController.text.trim().length >= 20 && !_isSubmitting;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _isSubmitting = true);
    final counterSource = _counterSourceController.text.trim();
    await widget.onSubmit(
      _reasonController.text.trim(),
      counterSource.isNotEmpty ? counterSource : null,
      _confidence,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final charCount = _reasonController.text.trim().length;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: EdgeInsets.symmetric(
        horizontal: ResponsiveService.isMobile(context) ? 16 : (MediaQuery.of(context).size.width - 480) / 2,
        vertical: 24,
      ),
      child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Flag as Incorrect',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                'Explain why this announcement is incorrect. Be specific.',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _reasonController,
                decoration: InputDecoration(
                  labelText: 'Reason *',
                  hintText: 'Describe what is incorrect and why...',
                  helperText: charCount < 20
                      ? '${20 - charCount} more characters needed'
                      : null,
                ),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _counterSourceController,
                decoration: InputDecoration(
                  labelText: 'Counter-source URL (optional)',
                  hintText: 'Link to correct information...',
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _confidence,
                decoration: InputDecoration(
                  labelText: 'How sure are you?',
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'certain', child: Text('Certain')),
                  DropdownMenuItem(
                      value: 'fairly_sure',
                      child: Text('Fairly sure')),
                ],
                onChanged: (v) =>
                    setState(() => _confidence = v ?? 'fairly_sure'),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _canSubmit ? _submit : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                    ),
                    child: _isSubmitting
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary),
                          )
                        : const Text('Submit Flag'),
                  ),
                ],
              ),
            ],
          ),
        ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Accept correction dialog
// ══════════════════════════════════════════════════════════════════════════

class _AcceptCorrectionDialog extends StatefulWidget {
  final Future<void> Function(String correctionText, String? correctionSource)
      onSubmit;

  const _AcceptCorrectionDialog({required this.onSubmit});

  @override
  State<_AcceptCorrectionDialog> createState() =>
      _AcceptCorrectionDialogState();
}

class _AcceptCorrectionDialogState extends State<_AcceptCorrectionDialog> {
  final _correctionController = TextEditingController();
  final _sourceController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _correctionController.dispose();
    _sourceController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _correctionController.text.trim().isNotEmpty && !_isSubmitting;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _isSubmitting = true);
    final source = _sourceController.text.trim();
    await widget.onSubmit(
      _correctionController.text.trim(),
      source.isNotEmpty ? source : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: EdgeInsets.symmetric(
        horizontal: ResponsiveService.isMobile(context) ? 16 : (MediaQuery.of(context).size.width - 480) / 2,
        vertical: 24,
      ),
      child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Accept & Correct',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                'Provide the correct information. This will be displayed alongside the original post.',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Accepting a correction applies a reputation penalty.',
                  style: TextStyle(
                      fontSize: 12, color: theme.colorScheme.error),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _correctionController,
                decoration: InputDecoration(
                  labelText: 'Correct information *',
                  hintText: 'What is the correct information?',
                ),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sourceController,
                decoration: InputDecoration(
                  labelText: 'Source URL (optional)',
                  hintText: 'Link to correct source...',
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _canSubmit ? _submit : null,
                    child: _isSubmitting
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary),
                          )
                        : const Text('Accept Correction'),
                  ),
                ],
              ),
            ],
          ),
        ),
    );
  }
}
