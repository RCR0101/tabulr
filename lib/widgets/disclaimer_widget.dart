import 'package:flutter/material.dart';
import '../services/responsive_service.dart';
import '../services/user_settings_service.dart';
import '../services/announcement_service.dart';

enum DisclaimerType {
  general,
  guestMode,
}

class DisclaimerWidget extends StatelessWidget {
  final DisclaimerType type;
  final String? customText;
  final EdgeInsetsGeometry? padding;
  final bool showIcon;
  final IconData? icon;

  const DisclaimerWidget({
    super.key,
    this.type = DisclaimerType.general,
    this.customText,
    this.padding,
    this.showIcon = true,
    this.icon,
  });

  String get _disclaimerText {
    if (customText != null) return customText!;
    
    switch (type) {
      case DisclaimerType.general:
        return 'Disclaimer: This software may make mistakes or suggest classes you might not be eligible for. Please double-check all course selections with your academic advisor.';
      case DisclaimerType.guestMode:
        return 'Note: Guest mode data will be cleared when you close the app';
    }
  }

  IconData get _disclaimerIcon {
    if (icon != null) return icon!;
    
    switch (type) {
      case DisclaimerType.general:
        return Icons.info_outline;
      case DisclaimerType.guestMode:
        return Icons.warning_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectivePadding = padding ?? _getDefaultPadding(context);
    
    return Container(
      padding: effectivePadding,
      decoration: _getDecoration(context),
      child: Row(
        children: [
          if (showIcon) ...[
            Icon(
              _disclaimerIcon,
              size: _getIconSize(context),
              color: _getIconColor(context),
            ),
            SizedBox(width: _getIconSpacing(context)),
          ],
          Expanded(
            child: Text(
              _disclaimerText,
              style: _getTextStyle(context),
            ),
          ),
        ],
      ),
    );
  }

  EdgeInsetsGeometry _getDefaultPadding(BuildContext context) {
    switch (type) {
      case DisclaimerType.general:
        return ResponsiveService.getAdaptivePadding(
          context,
          const EdgeInsets.all(12),
        );
      case DisclaimerType.guestMode:
        return EdgeInsets.zero;
    }
  }

  BoxDecoration? _getDecoration(BuildContext context) {
    switch (type) {
      case DisclaimerType.general:
        return BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
        );
      case DisclaimerType.guestMode:
        return null;
    }
  }

  double _getIconSize(BuildContext context) {
    switch (type) {
      case DisclaimerType.general:
        return ResponsiveService.getValue(
          context,
          mobile: 14.0,
          tablet: 16.0,
          desktop: 16.0,
        );
      case DisclaimerType.guestMode:
        return 16;
    }
  }

  double _getIconSpacing(BuildContext context) {
    switch (type) {
      case DisclaimerType.general:
        return ResponsiveService.getValue(
          context,
          mobile: 6.0,
          tablet: 8.0,
          desktop: 8.0,
        );
      case DisclaimerType.guestMode:
        return 8;
    }
  }

  Color _getIconColor(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7);
  }

  TextStyle _getTextStyle(BuildContext context) {
    switch (type) {
      case DisclaimerType.general:
        return Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
          fontSize: ResponsiveService.isMobile(context) ? 9 : 11,
        ) ?? const TextStyle();
      case DisclaimerType.guestMode:
        return Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ) ?? const TextStyle();
    }
  }
}

/// A specialized widget for bottom navigation bar disclaimers with action buttons
class BottomDisclaimerWidget extends StatefulWidget {
  final String? customText;

  const BottomDisclaimerWidget({
    super.key,
    this.customText,
  });

  @override
  State<BottomDisclaimerWidget> createState() => _BottomDisclaimerWidgetState();
}

class _BottomDisclaimerWidgetState extends State<BottomDisclaimerWidget> {
  bool _isTemporarilyHidden = false;
  final UserSettingsService _userSettingsService = UserSettingsService();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _userSettingsService,
      builder: (context, child) {
        // Don't show if user has permanently disabled it
        if (_userSettingsService.dontShowBottomDisclaimer) {
          return const SizedBox.shrink();
        }

        // Don't show if temporarily hidden this session
        if (_isTemporarilyHidden) {
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
              top: BorderSide(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
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
                  widget.customText ?? 'Disclaimer: This software may make mistakes or suggest classes you might not be eligible for. Please double-check all course selections with your academic advisor.',
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
                    ResponsiveService.getValue(context, mobile: 40.0, tablet: 50.0, desktop: 50.0),
                    ResponsiveService.getValue(context, mobile: 28.0, tablet: 32.0, desktop: 32.0),
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
                  await _userSettingsService.updateDontShowBottomDisclaimer(true);
                },
                style: TextButton.styleFrom(
                  minimumSize: Size(
                    ResponsiveService.getValue(context, mobile: 80.0, tablet: 100.0, desktop: 100.0),
                    ResponsiveService.getValue(context, mobile: 28.0, tablet: 32.0, desktop: 32.0),
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

/// A specialized widget for guest mode disclaimers
class GuestModeDisclaimerWidget extends StatelessWidget {
  final String? customText;
  final TextAlign textAlign;

  const GuestModeDisclaimerWidget({
    super.key,
    this.customText,
    this.textAlign = TextAlign.center,
  });

  @override
  Widget build(BuildContext context) {
    return DisclaimerWidget(
      type: DisclaimerType.guestMode,
      customText: customText,
      showIcon: false,
      padding: EdgeInsets.zero,
    );
  }
}

/// A specialized widget for top announcements from Firebase
class TopAnnouncementWidget extends StatefulWidget {
  const TopAnnouncementWidget({super.key});

  @override
  State<TopAnnouncementWidget> createState() => _TopAnnouncementWidgetState();
}

class _TopAnnouncementWidgetState extends State<TopAnnouncementWidget> {
  bool _isTemporarilyHidden = false;
  final UserSettingsService _userSettingsService = UserSettingsService();
  final AnnouncementService _announcementService = AnnouncementService();

  @override
  void initState() {
    super.initState();
    // Fetch announcement when widget is created
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
                    ResponsiveService.getValue(context, mobile: 40.0, tablet: 50.0, desktop: 50.0),
                    ResponsiveService.getValue(context, mobile: 28.0, tablet: 32.0, desktop: 32.0),
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
                    ResponsiveService.getValue(context, mobile: 28.0, tablet: 32.0, desktop: 32.0),
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