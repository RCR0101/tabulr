import 'package:flutter/material.dart';

import '../models/course.dart';
import '../services/data/user_settings_service.dart';

/// Which basis to count in, asked once per place the choice is made.
///
/// The toggle it points at defaults to credits, so a 2026-batch student who
/// never finds it builds a whole timetable in the wrong currency and only
/// learns at registration. Shown until dismissed; dismissal is keyed by
/// [noticeId] because the choice is made per timetable — and once more in the
/// generator, which builds a timetable before there is one to key on.
class CreditBasisNotice extends StatefulWidget {
  const CreditBasisNotice({
    super.key,
    required this.noticeId,
    required this.courses,
    required this.toggleHint,
    this.margin = const EdgeInsets.fromLTRB(8, 8, 8, 0),
  });

  /// Dismissal key: a timetable id, or a fixed name for a screen.
  final String noticeId;

  /// Hidden where none of these is offered in hours. Every campus publishes
  /// some — Pilani as a second row under a com cod ≥5000, Goa in its own CREDIT
  /// HOUR column, Hyderabad in the separate 2026-27 first-year booklet — so
  /// this is a per-catalogue test, not a per-campus one.
  final List<Course> courses;

  /// Where the reader will find the toggle, in their words.
  final String toggleHint;

  /// Spacing around the card, so it sits right in whichever column hosts it.
  final EdgeInsets margin;

  @override
  State<CreditBasisNotice> createState() => _CreditBasisNoticeState();
}

class _CreditBasisNoticeState extends State<CreditBasisNotice> {
  final _settings = UserSettingsService();

  @override
  Widget build(BuildContext context) {
    // Cheapest and most decisive test first: where nothing is offered in hours
    // there is no choice to explain and no settings to consult.
    if (!widget.courses.any((c) => c.offersBasis(CreditBasis.hours))) {
      return const SizedBox.shrink();
    }
    if (!_settings.showsCreditBasisNotice(widget.noticeId)) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    // Amber rather than the error red the mix warning uses: this is a thing to
    // check, not a thing that is wrong.
    final amber = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFFFCA28)
        : const Color(0xFFB26A00);

    return Container(
      margin: widget.margin,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.12),
        border: Border.all(color: amber.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: amber),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Which one are you counting in?',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface),
                ),
                const SizedBox(height: 3),
                Text(
                  '2026 batch onwards registers in credit hours. 2025 batch and '
                  'earlier registers in credits. ${widget.toggleHint} — a '
                  'timetable counts one way or the other.',
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: scheme.onSurface.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            icon: const Icon(Icons.close, size: 16),
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              await _settings.dismissCreditBasisNotice(widget.noticeId);
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
    );
  }
}
