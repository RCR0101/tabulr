import 'dart:async';
import 'package:flutter/material.dart';
import '../services/data/campus_service.dart';
import '../utils/design_constants.dart';

class CampusSelectorWidget extends StatefulWidget {
  final Function(Campus)? onCampusChanged;
  final Future<bool> Function()? confirmSwitch;

  const CampusSelectorWidget({
    super.key,
    this.onCampusChanged,
    this.confirmSwitch,
  });

  /// The switcher as an entry in an overflow menu, for the phone layouts whose
  /// app bar has no room for it — in portrait it was dropped altogether, which
  /// left no way to change campus at all.
  ///
  /// The entry is disabled so that tapping it selects nothing on the menu that
  /// holds it; the switcher inside stays live and closes that menu itself.
  static PopupMenuItem<T> menuEntry<T>(
    BuildContext context, {
    Future<bool> Function()? confirmSwitch,
    void Function(Campus)? onCampusChanged,
  }) {
    return PopupMenuItem<T>(
      enabled: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppDesign.spacingXs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Campus',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: AppDesign.opacityMedium),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppDesign.spacingXs),
            CampusSelectorWidget(
              confirmSwitch: confirmSwitch,
              onCampusChanged: (campus) {
                Navigator.pop(context);
                onCampusChanged?.call(campus);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  State<CampusSelectorWidget> createState() => _CampusSelectorWidgetState();
}

class _CampusSelectorWidgetState extends State<CampusSelectorWidget> {
  late StreamSubscription<Campus> _campusSubscription;
  
  @override
  void initState() {
    super.initState();
    _campusSubscription = CampusService.campusChangeStream.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _campusSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Campus>(
      initialValue: CampusService.currentCampus,
      tooltip: 'Select Campus',
      onSelected: (Campus campus) async {
        if (campus != CampusService.currentCampus) {
          if (widget.confirmSwitch != null) {
            final confirmed = await widget.confirmSwitch!();
            if (!confirmed) return;
          }
          await CampusService.setCampus(campus);
          setState(() {});
          widget.onCampusChanged?.call(campus);
        }
      },
      itemBuilder: (BuildContext context) {
        return CampusService.allCampuses.map((Campus campus) {
          final isSelected = campus == CampusService.currentCampus;
          return PopupMenuItem<Campus>(
            value: campus,
            child: Row(
              children: [
                Icon(
                  Icons.location_city,
                  size: 20,
                  color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 12),
                Text(
                  CampusService.getCampusDisplayName(campus),
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : null,
                  ),
                ),
                if (isSelected) ...[
                  const Spacer(),
                  Icon(
                    Icons.check,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ],
            ),
          );
        }).toList();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(20),
          color: Theme.of(context).colorScheme.surface,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_city,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              CampusService.currentCampusDisplayName,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}