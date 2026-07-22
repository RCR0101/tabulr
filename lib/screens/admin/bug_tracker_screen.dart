import 'package:flutter/material.dart';
import '../../models/bug_report.dart';
import '../../services/data/bug_report_service.dart';
import '../../services/ui/toast_service.dart';
import '../../utils/design_constants.dart';
import '../../widgets/bug_status_chip.dart';
import '../../widgets/common/empty_state_widget.dart';

class BugTrackerScreen extends StatefulWidget {
  const BugTrackerScreen({super.key});

  @override
  State<BugTrackerScreen> createState() => _BugTrackerScreenState();
}

class _BugTrackerScreenState extends State<BugTrackerScreen> {
  final BugReportService _service = BugReportService();

  BugStatus? _filter; // null = all
  int _page = 0;
  static const int _pageSize = 10;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppDesign.appBar(
        context,
        titleWidget: AppDesign.iconTitle(
          context,
          icon: Icons.bug_report,
          title: 'Bug Tracker',
          subtitle: 'All reports, newest first',
        ),
        centerTitle: false,
      ),
      body: StreamBuilder<List<BugReport>>(
        stream: _service.allReports(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(
              child: EmptyStateWidget(
                icon: Icons.error_outline,
                title: 'Could not load reports',
                subtitle: 'Check your admin access and try again.',
              ),
            );
          }

          final all = snapshot.data ?? const <BugReport>[];
          final filtered = _filter == null
              ? all
              : all.where((r) => r.status == _filter).toList();

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                children: [
                  _buildFilters(context, all),
                  Expanded(child: _buildList(context, filtered)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilters(BuildContext context, List<BugReport> all) {
    int count(BugStatus? s) =>
        s == null ? all.length : all.where((r) => r.status == s).length;

    Widget chip(String label, BugStatus? status) {
      final selected = _filter == status;
      return Padding(
        padding: const EdgeInsets.only(right: AppDesign.spacingSm),
        child: FilterChip(
          label: Text('$label (${count(status)})'),
          selected: selected,
          onSelected: (_) => setState(() {
            _filter = status;
            _page = 0;
          }),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(AppDesign.spacingMd, AppDesign.spacingMd,
          AppDesign.spacingMd, AppDesign.spacingSm),
      child: Row(
        children: [
          chip('All', null),
          for (final s in BugStatus.values) chip(s.label, s),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, List<BugReport> reports) {
    if (reports.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.inbox_outlined,
        title: 'No reports',
        subtitle: 'Nothing matches this filter.',
      );
    }

    final pageCount = (reports.length + _pageSize - 1) ~/ _pageSize;
    final page = _page.clamp(0, pageCount - 1);
    final start = page * _pageSize;
    final pageItems =
        reports.sublist(start, (start + _pageSize).clamp(0, reports.length));

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: AppDesign.spacingMd),
            children: pageItems.map((r) => _reportCard(context, r)).toList(),
          ),
        ),
        if (pageCount > 1) _paginationBar(context, page, pageCount),
      ],
    );
  }

  Widget _reportCard(BuildContext context, BugReport r) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppDesign.spacingSm),
      padding: const EdgeInsets.all(AppDesign.spacingMd),
      decoration: AppDesign.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${r.category} · ${r.subCategory}',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${r.authorEmail}  ·  ${_formatDateTime(r.createdAt)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.55),
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppDesign.spacingSm),
              BugStatusChip(status: r.status, small: true),
            ],
          ),
          const SizedBox(height: AppDesign.spacingSm),
          Text(r.description, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppDesign.spacingMd),
          Row(
            children: [
              Text('Status',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.55),
                      )),
              const SizedBox(width: AppDesign.spacingSm),
              _statusDropdown(context, r),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusDropdown(BuildContext context, BugReport r) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppDesign.spacingSm),
      decoration: BoxDecoration(
        borderRadius: AppDesign.borderRadiusSm,
        border: Border.all(color: scheme.outline.withValues(alpha: 0.3)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<BugStatus>(
          value: r.status,
          isDense: true,
          borderRadius: AppDesign.borderRadiusMd,
          items: BugStatus.values
              .map((s) => DropdownMenuItem(
                    value: s,
                    child: Text(s.label,
                        style: Theme.of(context).textTheme.bodyMedium),
                  ))
              .toList(),
          onChanged: (next) => _changeStatus(r, next),
        ),
      ),
    );
  }

  Future<void> _changeStatus(BugReport r, BugStatus? next) async {
    if (next == null || next == r.status) return;
    final ok = await _service.updateStatus(r.id, next);
    if (!mounted) return;
    if (ok) {
      ToastService.showSuccess('Marked "${next.label}"');
    } else {
      ToastService.showError('Failed to update status');
    }
  }

  Widget _paginationBar(BuildContext context, int page, int pageCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDesign.spacingSm),
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

  static String _formatDateTime(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]} ${d.year}, $hh:$mm';
  }
}
