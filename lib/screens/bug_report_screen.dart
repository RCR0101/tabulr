import 'package:flutter/material.dart';
import '../models/bug_report.dart';
import '../services/data/auth_service.dart';
import '../services/data/bug_report_service.dart';
import '../services/ui/toast_service.dart';
import '../utils/design_constants.dart';
import '../widgets/bug_status_chip.dart';
import '../widgets/bug_thread.dart';
import '../widgets/common/app_button.dart';
import '../widgets/common/empty_state_widget.dart';

class BugReportScreen extends StatefulWidget {
  const BugReportScreen({super.key});

  @override
  State<BugReportScreen> createState() => _BugReportScreenState();
}

class _BugReportScreenState extends State<BugReportScreen> {
  final BugReportService _service = BugReportService();
  final AuthService _auth = AuthService();
  final TextEditingController _descController = TextEditingController();

  String? _category;
  String? _subCategory;
  bool _submitting = false;

  // Client-side pagination over the user's (capped) report stream.
  static const int _pageSize = 5;
  int _page = 0;

  /// Reports whose conversation is expanded. Threads are mounted only while
  /// open so the screen doesn't hold a listener per row.
  final Set<String> _openThreads = {};

  // Cache the stream once so form rebuilds (typing, picking a category) don't
  // re-subscribe and flash the loading/empty state. The live Firestore stream
  // still updates on its own once a new report is submitted.
  Stream<List<BugReport>>? _reportsStream;

  @override
  void initState() {
    super.initState();
    if (_auth.isAuthenticated) {
      _reportsStream = _service.myReports();
    }
  }

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  List<String> get _subOptions =>
      _category == null ? const [] : (bugReportTaxonomy[_category] ?? const []);

  Future<void> _submit() async {
    final desc = _descController.text.trim();
    if (_category == null || _subCategory == null) {
      ToastService.showError('Please pick a category and sub-category');
      return;
    }
    if (desc.isEmpty) {
      ToastService.showError('Please describe the issue');
      return;
    }

    setState(() => _submitting = true);
    final ok = await _service.submitReport(
      category: _category!,
      subCategory: _subCategory!,
      description: desc,
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (ok) {
      setState(() {
        _category = null;
        _subCategory = null;
        _descController.clear();
        _page = 0;
      });
      ToastService.showSuccess('Report submitted — thank you!');
    } else {
      ToastService.showError('Could not submit. Are you signed in?');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppDesign.appBar(
        context,
        titleWidget: AppDesign.iconTitle(
          context,
          icon: Icons.bug_report_outlined,
          title: 'Report a Bug',
          subtitle: 'Help us make Tabulr better',
        ),
        centerTitle: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(AppDesign.spacingMd),
            children: [
              _buildForm(context),
              const SizedBox(height: AppDesign.spacingLg),
              _buildPastReports(context),
              const SizedBox(height: AppDesign.spacingXl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!_auth.isAuthenticated) {
      return Container(
        padding: const EdgeInsets.all(AppDesign.spacingLg),
        decoration: AppDesign.cardDecoration(context),
        child: Row(
          children: [
            Icon(Icons.lock_outline, color: AppDesign.muted(context)),
            const SizedBox(width: AppDesign.spacingMd),
            Expanded(
              child: Text(
                'Sign in with your BITS email to file and track bug reports.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppDesign.spacingLg),
      decoration: AppDesign.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('New report',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: AppDesign.spacingLg),
          DropdownButtonFormField<String>(
            initialValue: _category,
            isExpanded: true,
            decoration: AppDesign.inputDecoration(context, label: 'Category'),
            items: bugReportTaxonomy.keys
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() {
              _category = v;
              _subCategory = null; // reset dependent field
            }),
          ),
          const SizedBox(height: AppDesign.spacingMd),
          DropdownButtonFormField<String>(
            initialValue: _subCategory,
            isExpanded: true,
            decoration: AppDesign.inputDecoration(
              context,
              label: 'Sub-category',
              hint: _category == null ? 'Pick a category first' : null,
            ),
            items: _subOptions
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: _category == null
                ? null
                : (v) => setState(() => _subCategory = v),
          ),
          const SizedBox(height: AppDesign.spacingMd),
          TextField(
            controller: _descController,
            maxLines: 5,
            minLines: 3,
            maxLength: 1000,
            textInputAction: TextInputAction.newline,
            decoration: AppDesign.inputDecoration(
              context,
              label: 'Description',
              hint: 'What happened? Steps to reproduce, what you expected…',
            ),
          ),
          const SizedBox(height: AppDesign.spacingSm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  'Reports are visible to you and the Tabulr team only.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      ),
                ),
              ),
              const SizedBox(width: AppDesign.spacingMd),
              AppButton(
                label: 'Submit report',
                icon: Icons.send_rounded,
                isLoading: _submitting,
                onTap: _submitting ? null : _submit,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPastReports(BuildContext context) {
    if (!_auth.isAuthenticated) return const SizedBox.shrink();

    return StreamBuilder<List<BugReport>>(
      stream: _reportsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(AppDesign.spacingXl),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final reports = snapshot.data ?? const <BugReport>[];
        if (reports.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(top: AppDesign.spacingLg),
            child: EmptyStateWidget(
              icon: Icons.inbox_outlined,
              title: 'No reports yet',
              subtitle: 'Your submitted reports will appear here.',
            ),
          );
        }

        final pageCount = (reports.length + _pageSize - 1) ~/ _pageSize;
        final page = _page.clamp(0, pageCount - 1);
        final start = page * _pageSize;
        final pageItems = reports.sublist(
          start,
          (start + _pageSize).clamp(0, reports.length),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                  left: AppDesign.spacingXs, bottom: AppDesign.spacingSm),
              child: Text(
                'Your reports (${reports.length})',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            ...pageItems.map((r) => _reportCard(context, r)),
            if (pageCount > 1)
              _paginationBar(context, page, pageCount),
          ],
        );
      },
    );
  }

  Widget _reportCard(BuildContext context, BugReport r) {
    final scheme = Theme.of(context).colorScheme;
    final open = _openThreads.contains(r.id);
    return Container(
      margin: const EdgeInsets.only(bottom: AppDesign.spacingSm),
      padding: const EdgeInsets.all(AppDesign.spacingMd),
      decoration: AppDesign.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${r.category} · ${r.subCategory}',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: AppDesign.spacingSm),
              BugStatusChip(status: r.status, small: true),
            ],
          ),
          const SizedBox(height: AppDesign.spacingXs),
          Text(
            r.description,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppDesign.spacingSm),
          Row(
            children: [
              Text(
                _formatDate(r.createdAt),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.5),
                    ),
              ),
              const Spacer(),
              if (r.hasUnreadForUser && !open) ...[
                Text(
                  'New reply',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(width: AppDesign.spacingSm),
              ],
              TextButton.icon(
                onPressed: () => setState(() {
                  if (!_openThreads.remove(r.id)) _openThreads.add(r.id);
                }),
                icon: Icon(
                  open ? Icons.expand_less : Icons.forum_outlined,
                  size: 18,
                ),
                label: Text(open ? 'Hide' : 'Conversation'),
              ),
            ],
          ),
          if (open) ...[
            Divider(color: scheme.outline.withValues(alpha: 0.2)),
            const SizedBox(height: AppDesign.spacingSm),
            BugThread(reportId: r.id, asAdmin: false),
          ],
        ],
      ),
    );
  }

  Widget _paginationBar(BuildContext context, int page, int pageCount) {
    return Padding(
      padding: const EdgeInsets.only(top: AppDesign.spacingSm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: page > 0 ? () => setState(() => _page = page - 1) : null,
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous',
          ),
          Text('Page ${page + 1} of $pageCount',
              style: Theme.of(context).textTheme.bodyMedium),
          IconButton(
            onPressed: page < pageCount - 1
                ? () => setState(() => _page = page + 1)
                : null,
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next',
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final now = DateTime.now();
    final diff = now.difference(d);
    String rel;
    if (diff.inMinutes < 1) {
      rel = 'just now';
    } else if (diff.inHours < 1) {
      rel = '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      rel = '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      rel = '${diff.inDays}d ago';
    } else {
      rel = '${d.day} ${months[d.month - 1]} ${d.year}';
    }
    return rel;
  }
}
