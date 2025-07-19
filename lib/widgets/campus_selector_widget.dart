import 'package:flutter/material.dart';
import '../services/campus_service.dart';

class CampusSelectorWidget extends StatefulWidget {
  final Function(Campus)? onCampusChanged;
  
  const CampusSelectorWidget({
    super.key,
    this.onCampusChanged,
  });

  @override
  State<CampusSelectorWidget> createState() => _CampusSelectorWidgetState();
}

class _CampusSelectorWidgetState extends State<CampusSelectorWidget> {
  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Campus>(
      initialValue: CampusService.currentCampus,
      tooltip: 'Select Campus',
      onSelected: (Campus campus) async {
        if (campus != CampusService.currentCampus) {
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
                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
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
            color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
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