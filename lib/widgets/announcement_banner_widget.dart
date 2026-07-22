import 'package:flutter/material.dart';
import '../services/ui/responsive_service.dart';
import '../services/data/user_settings_service.dart';
import '../services/data/app_announcement_service.dart';

class TopAnnouncementWidget extends StatefulWidget {
  const TopAnnouncementWidget({super.key});

  @override
  State<TopAnnouncementWidget> createState() => _TopAnnouncementWidgetState();
}

class _TopAnnouncementWidgetState extends State<TopAnnouncementWidget> {
  bool _isTemporarilyHidden = false;
  final UserSettingsService _userSettingsService = UserSettingsService();
  final AppAnnouncementService _announcementService = AppAnnouncementService();

  @override
  void initState() {
    super.initState();
    _announcementService.fetchAnnouncement();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_userSettingsService, _announcementService]),
      builder: (context, child) {
        // Don't show if temporarily hidden this session
        if (_isTemporarilyHidden) {
          return const SizedBox.shrink();
        }

        // Don't show until user settings have loaded
        if (_userSettingsService.userSettings == null) {
          return const SizedBox.shrink();
        }

        // Check if we should show the announcement
        final announcementText = _announcementService.getAnnouncementText(
          _userSettingsService.dontShowTopUpdated,
        );

        if (announcementText == null || announcementText.trim().isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: ResponsiveService.getAdaptivePadding(
            context,
            const EdgeInsets.all(16),
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.campaign_outlined,
                size: ResponsiveService.getValue(
                  context,
                  mobile: 14.0,
                  tablet: 16.0,
                  desktop: 16.0,
                ),
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              SizedBox(
                width: ResponsiveService.getValue(
                  context,
                  mobile: 6.0,
                  tablet: 8.0,
                  desktop: 8.0,
                ),
              ),
              Expanded(
                child: Text(
                  announcementText,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    fontSize: ResponsiveService.isMobile(context) ? 9 : 11,
                  ),
                ),
              ),
              SizedBox(
                width: ResponsiveService.getValue(
                  context,
                  mobile: 8.0,
                  tablet: 12.0,
                  desktop: 12.0,
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isTemporarilyHidden = true;
                  });
                },
                style: TextButton.styleFrom(
                  minimumSize: Size(
                    48.0,
                    48.0, // ≥48px tap target (a11y)
                  ),
                  padding: ResponsiveService.getAdaptivePadding(
                    context,
                    EdgeInsets.symmetric(
                      horizontal: ResponsiveService.getValue(context, mobile: 8.0, tablet: 12.0, desktop: 12.0),
                      vertical: ResponsiveService.getValue(context, mobile: 4.0, tablet: 6.0, desktop: 6.0),
                    ),
                  ),
                ),
                child: Text(
                  'OK',
                  style: TextStyle(
                    fontSize: ResponsiveService.getValue(context, mobile: 10.0, tablet: 12.0, desktop: 12.0),
                  ),
                ),
              ),
              SizedBox(
                width: ResponsiveService.getValue(
                  context,
                  mobile: 4.0,
                  tablet: 6.0,
                  desktop: 6.0,
                ),
              ),
              TextButton(
                onPressed: () async {
                  setState(() {
                    _isTemporarilyHidden = true;
                  });
                  await _userSettingsService.updateDontShowTopUpdated();
                },
                style: TextButton.styleFrom(
                  minimumSize: Size(
                    ResponsiveService.getValue(context, mobile: 80.0, tablet: 100.0, desktop: 100.0),
                    48.0, // ≥48px tap target (a11y)
                  ),
                  padding: ResponsiveService.getAdaptivePadding(
                    context,
                    EdgeInsets.symmetric(
                      horizontal: ResponsiveService.getValue(context, mobile: 8.0, tablet: 12.0, desktop: 12.0),
                      vertical: ResponsiveService.getValue(context, mobile: 4.0, tablet: 6.0, desktop: 6.0),
                    ),
                  ),
                ),
                child: Text(
                  'Don\'t show again',
                  style: TextStyle(
                    fontSize: ResponsiveService.getValue(context, mobile: 10.0, tablet: 12.0, desktop: 12.0),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
