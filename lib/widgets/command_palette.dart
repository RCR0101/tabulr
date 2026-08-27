import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/data/auth_service.dart';
import '../models/timetable_selection_link.dart';
import '../screens/guide_screen.dart';
import '../services/ui/theme_service.dart';
import '../services/ui/theme_preferences_controller.dart';
import '../models/user_settings.dart' as user_settings;
import '../utils/design_constants.dart';
import '../utils/guide_content.dart';
import '../utils/page_transitions.dart';
import 'app_destinations.dart';
import 'app_tools.dart';
import 'app_workspaces.dart';

class CommandPaletteEntry {
  final String label;
  final String? subtitle;
  final IconData icon;
  final CommandCategory category;
  final VoidCallback onSelect;
  final String? shortcut;

  const CommandPaletteEntry({
    required this.label,
    this.subtitle,
    required this.icon,
    required this.category,
    required this.onSelect,
    this.shortcut,
  });
}

enum CommandCategory {
  recent('Recent', Icons.history),
  context('This Page', Icons.push_pin_outlined),
  navigation('Navigate', Icons.navigation),
  action('Actions', Icons.bolt),
  guide('Guide', Icons.auto_stories_outlined);

  final String label;
  final IconData icon;
  const CommandCategory(this.label, this.icon);
}

/// Screens register their context-specific actions here.
/// Keyed by screen identity so only the active screen's actions show.
class CommandPaletteActions {
  CommandPaletteActions._();

  static final Map<DrawerScreen, List<CommandPaletteEntry> Function()>
  _providers = {};
  static final List<String> _recentLabels = [];
  static const int _maxRecent = 5;

  static void register(
    DrawerScreen screen,
    List<CommandPaletteEntry> Function() provider,
  ) {
    _providers[screen] = provider;
  }

  static void unregister(DrawerScreen screen) {
    _providers.remove(screen);
  }

  static List<CommandPaletteEntry> entriesFor(DrawerScreen screen) {
    return _providers[screen]?.call() ?? [];
  }

  static void recordUsage(String label) {
    _recentLabels.remove(label);
    _recentLabels.insert(0, label);
    if (_recentLabels.length > _maxRecent) {
      _recentLabels.removeLast();
    }
  }

  static List<String> get recentLabels => List.unmodifiable(_recentLabels);
}

class CommandPalette extends StatefulWidget {
  final void Function(DrawerScreen screen) onNavigate;
  final DrawerScreen? currentScreen;
  final List<CommandPaletteEntry> contextEntries;
  final VoidCallback? onToggleTheme;
  final VoidCallback? onSignOut;
  final VoidCallback? onReplayTour;

  /// Passed to the elective browsers so they can add straight to the timetable
  /// being edited. Null everywhere except the editor, where it's read-only.
  final TimetableSelectionLink? selectionLink;

  const CommandPalette({
    super.key,
    required this.onNavigate,
    required this.currentScreen,
    this.contextEntries = const [],
    this.onToggleTheme,
    this.onSignOut,
    this.onReplayTour,
    this.selectionLink,
  });

  static Future<void> show(
    BuildContext context, {
    required void Function(DrawerScreen screen) onNavigate,
    required DrawerScreen? currentScreen,
    List<CommandPaletteEntry> contextEntries = const [],
    VoidCallback? onToggleTheme,
    VoidCallback? onSignOut,
    VoidCallback? onReplayTour,
    TimetableSelectionLink? selectionLink,
  }) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close command palette',
      barrierColor: Colors.black.withValues(alpha: 0.48),
      transitionDuration:
          reduceMotion ? Duration.zero : AppDesign.animDurationNormal,
      pageBuilder:
          (_, __, ___) => RepaintBoundary(
            key: const ValueKey('command-palette-route-boundary'),
            child: CommandPalette(
              onNavigate: onNavigate,
              currentScreen: currentScreen,
              contextEntries: contextEntries,
              onToggleTheme: onToggleTheme,
              onSignOut: onSignOut,
              onReplayTour: onReplayTour,
              selectionLink: selectionLink,
            ),
          ),
      transitionBuilder: (_, animation, __, child) {
        final eased = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: eased,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.975, end: 1).animate(eased),
            alignment: Alignment.topCenter,
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  int _selectedIndex = 0;
  List<CommandPaletteEntry> _filtered = [];
  late List<CommandPaletteEntry> _allEntries;

  @override
  void initState() {
    super.initState();
    _allEntries = _buildEntries();
    _filtered = _allEntries;
    _focusNode.addListener(_onFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  static String _firstSentence(String text) {
    final stop = text.indexOf('. ');
    return stop < 0 ? text : text.substring(0, stop + 1);
  }

  List<CommandPaletteEntry> _buildEntries() {
    final entries = <CommandPaletteEntry>[];
    final auth = widget.onSignOut == null ? null : AuthService();
    final nav = Navigator.of(context);

    // All non-recent entries first (we'll inject recents at the end)
    final nonRecentEntries = <CommandPaletteEntry>[];

    // Context-specific actions for the current screen (shown first)
    if (widget.contextEntries.isNotEmpty) {
      nonRecentEntries.addAll(widget.contextEntries);
    } else if (widget.currentScreen != null) {
      nonRecentEntries.addAll(
        CommandPaletteActions.entriesFor(widget.currentScreen!),
      );
    }

    // Every shell destination, straight from the registry. Hand-listing these
    // is what let Minors and Academic FAQ ship to the sidebar and never appear
    // here; now a new DrawerScreen shows up in both or compiles in neither.
    // A tool that is also a shell destination wins when there's a timetable to
    // add to — pushing it keeps the editor underneath, navigating would not.
    final linkedScreens =
        widget.selectionLink == null
            ? const <DrawerScreen>{}
            : {
              for (final info in AppTools.all)
                if (info.screen != null) info.screen!,
            };

    nonRecentEntries.addAll([
      for (final destination in AppDestinations.visible)
        if (!linkedScreens.contains(destination.screen))
          CommandPaletteEntry(
            label: destination.label,
            subtitle:
                '${AppWorkspaces.contextForScreen(destination.screen)}: ${destination.description}',
            icon: destination.icon,
            category: CommandCategory.navigation,
            onSelect: () => widget.onNavigate(destination.screen),
          ),
    ]);

    nonRecentEntries.addAll([
      for (final info in AppTools.all)
        if ((info.screen == null || widget.selectionLink != null) &&
            info.isReachable)
          CommandPaletteEntry(
            label: info.label,
            subtitle: [
              AppWorkspaces.contextForTool(info.tool),
              info.description,
            ].whereType<String>().join(': '),
            icon: info.icon,
            category: CommandCategory.navigation,
            onSelect: () => info.pushOn(nav, widget.selectionLink),
          ),
    ]);

    // Global actions
    if (widget.onReplayTour != null) {
      nonRecentEntries.add(
        CommandPaletteEntry(
          label: 'Show me around',
          subtitle: 'Replay the guided tour for this page',
          icon: Icons.explore_outlined,
          category: CommandCategory.action,
          onSelect: widget.onReplayTour!,
        ),
      );
    }

    if (widget.onToggleTheme != null) {
      nonRecentEntries.add(
        CommandPaletteEntry(
          label: 'Change Theme',
          subtitle: 'Open the theme picker',
          icon: Icons.brightness_6,
          category: CommandCategory.action,
          onSelect: widget.onToggleTheme!,
        ),
      );
    }

    // Direct theme + mode switches — type "drac", "light", etc. to apply
    // instantly without opening the picker dialog.
    final themeService = ThemeService();
    final themePreferences = ThemePreferencesController();
    for (final theme in AppTheme.values) {
      nonRecentEntries.add(
        CommandPaletteEntry(
          label: 'Theme: ${theme.displayName}',
          subtitle:
              theme == themeService.currentTheme
                  ? 'Current theme'
                  : 'Apply this theme',
          icon: theme.icon,
          category: CommandCategory.action,
          onSelect: () => themePreferences.setTheme(theme),
        ),
      );
    }
    nonRecentEntries.addAll([
      CommandPaletteEntry(
        label: 'Dark Mode',
        subtitle: 'Always use the dark palette',
        icon: Icons.dark_mode,
        category: CommandCategory.action,
        onSelect:
            () =>
                themePreferences.setThemeMode(user_settings.AppThemeMode.dark),
      ),
      CommandPaletteEntry(
        label: 'Light Mode',
        subtitle: 'Always use the light palette',
        icon: Icons.light_mode,
        category: CommandCategory.action,
        onSelect:
            () =>
                themePreferences.setThemeMode(user_settings.AppThemeMode.light),
      ),
      CommandPaletteEntry(
        label: 'System Theme Mode',
        subtitle: 'Match your device setting',
        icon: Icons.brightness_auto,
        category: CommandCategory.action,
        onSelect:
            () => themePreferences.setThemeMode(
              user_settings.AppThemeMode.system,
            ),
      ),
    ]);

    if (widget.onSignOut != null && (auth?.isAuthenticated ?? false)) {
      nonRecentEntries.add(
        CommandPaletteEntry(
          label: 'Sign Out',
          icon: Icons.logout,
          category: CommandCategory.action,
          onSelect: widget.onSignOut!,
        ),
      );
    }

    nonRecentEntries.addAll([
      for (final topic in guideTopics)
        CommandPaletteEntry(
          label: topic.title,
          subtitle: _firstSentence(topic.lead),
          icon: topic.icon,
          category: CommandCategory.guide,
          onSelect:
              () => nav.push(
                FadeSlidePageRoute<void>(
                  page: GuideScreen(initialAnchor: topic.anchor),
                ),
              ),
        ),
    ]);

    // Promote recent commands instead of showing each command twice.
    final promotedLabels = <String>{};
    for (final label in CommandPaletteActions.recentLabels) {
      final match =
          nonRecentEntries.where((entry) => entry.label == label).firstOrNull;
      if (match == null || !promotedLabels.add(match.label)) continue;
      entries.add(
        CommandPaletteEntry(
          label: match.label,
          subtitle: match.subtitle,
          icon: match.icon,
          category: CommandCategory.recent,
          onSelect: match.onSelect,
          shortcut: match.shortcut,
        ),
      );
    }

    entries.addAll(
      nonRecentEntries.where((entry) => !promotedLabels.contains(entry.label)),
    );
    return entries;
  }

  void _filter(String query) {
    if (query.isEmpty) {
      setState(() {
        _filtered = _allEntries;
        _selectedIndex = 0;
      });
      return;
    }

    final q = query.toLowerCase();
    final scored = <(CommandPaletteEntry, double)>[];

    for (final entry in _allEntries) {
      final score = _fuzzyScore(entry, q);
      if (score > 0) scored.add((entry, score));
    }

    scored.sort((a, b) => b.$2.compareTo(a.$2));

    setState(() {
      _filtered = scored.map((e) => e.$1).toList();
      _selectedIndex = 0;
    });
  }

  double _fuzzyScore(CommandPaletteEntry entry, String query) {
    final label = entry.label.toLowerCase();
    final subtitle = (entry.subtitle ?? '').toLowerCase();
    final combined = '$label $subtitle';

    // Exact match
    if (label == query) return 100;

    // Prefix match
    if (label.startsWith(query)) return 90;

    // Word-start match (e.g. "gen" matches "TT Generator")
    final words = label.split(RegExp(r'[\s/]+'));
    if (words.any((w) => w.startsWith(query))) return 80;

    // Acronym match (e.g. "ttg" matches "TT Generator", "fsl" matches "Free Slot Finder")
    if (words.length >= 2) {
      final acronym = words.map((w) => w.isNotEmpty ? w[0] : '').join();
      if (acronym.startsWith(query)) return 75;
    }

    // Contains in label
    if (label.contains(query)) return 65;

    // Multi-word: all query words appear in combined text
    final queryWords = query.split(RegExp(r'\s+'));
    if (queryWords.length > 1 &&
        queryWords.every((qw) => combined.contains(qw))) {
      return 60;
    }

    // Subtitle matches
    if (subtitle.startsWith(query)) return 50;
    if (subtitle.contains(query)) return 40;
    if (queryWords.length > 1 &&
        queryWords.every((qw) => subtitle.contains(qw))) {
      return 35;
    }

    // Subsequence match
    int qi = 0;
    for (int i = 0; i < combined.length && qi < query.length; i++) {
      if (combined[i] == query[qi]) qi++;
    }
    if (qi == query.length) return 20;

    return 0;
  }

  void _selectCurrent() {
    if (_filtered.isEmpty) return;
    final entry = _filtered[_selectedIndex];
    CommandPaletteActions.recordUsage(entry.label);
    Navigator.of(context).pop();
    entry.onSelect();
  }

  void _moveSelection(int delta) {
    if (_filtered.isEmpty) return;
    setState(() {
      _selectedIndex = (_selectedIndex + delta).clamp(0, _filtered.length - 1);
    });
    _ensureVisible();
  }

  void _ensureVisible() {
    if (_scrollController.hasClients) {
      const itemHeight = 64.0;
      final targetOffset = _selectedIndex * itemHeight;
      final viewportHeight = _scrollController.position.viewportDimension;
      final currentScroll = _scrollController.offset;

      if (targetOffset < currentScroll) {
        _scrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      } else if (targetOffset + itemHeight > currentScroll + viewportHeight) {
        _scrollController.animateTo(
          targetOffset + itemHeight - viewportHeight,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final screenSize = media.size;
    final compact = screenSize.width < 600;
    final maxHeight = math.min(
      screenSize.height * (compact ? 0.86 : 0.74),
      compact ? 720.0 : 620.0,
    );
    final radius = BorderRadius.circular(compact ? 20 : 26);

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _moveSelection(1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _moveSelection(-1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter) {
          _selectCurrent();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedPadding(
        duration:
            media.disableAnimations
                ? Duration.zero
                : AppDesign.animDurationNormal,
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.fromLTRB(
          compact ? 12 : 24,
          compact ? 20 : 52,
          compact ? 12 : 24,
          math.max(compact ? 20 : 52, media.viewInsets.bottom + 12),
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: radius,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  key: const ValueKey('command-palette-surface'),
                  width: math.min(700, screenSize.width - (compact ? 24 : 48)),
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        scheme.surface.withValues(alpha: 0.98),
                        Color.alphaBlend(
                          scheme.primary.withValues(alpha: 0.035),
                          scheme.surface.withValues(alpha: 0.98),
                        ),
                      ],
                    ),
                    borderRadius: radius,
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: 48,
                        spreadRadius: -4,
                        offset: const Offset(0, 20),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildHeader(scheme, compact),
                      _buildSearchField(scheme),
                      const SizedBox(height: 8),
                      Flexible(
                        child: AnimatedSwitcher(
                          duration:
                              media.disableAnimations
                                  ? Duration.zero
                                  : AppDesign.animDurationFast,
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          child: KeyedSubtree(
                            key: ValueKey(
                              '${_controller.text}:${_filtered.length}',
                            ),
                            child: _buildResults(scheme),
                          ),
                        ),
                      ),
                      _buildFooter(scheme),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme scheme, bool compact) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 18 : 22,
        compact ? 16 : 20,
        compact ? 14 : 18,
        12,
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(13),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.22),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Icon(Icons.bolt_rounded, size: 21, color: scheme.onPrimary),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Search Tabulr',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                if (!compact)
                  Text(
                    'Navigate, run an action, or open a guide.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          _keycap(scheme, _paletteShortcut),
        ],
      ),
    );
  }

  String get _paletteShortcut =>
      Theme.of(context).platform == TargetPlatform.macOS ? 'Cmd K' : 'Ctrl K';

  Widget _buildSearchField(ColorScheme scheme) {
    final focused = _focusNode.hasFocus;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AnimatedContainer(
        duration:
            MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : AppDesign.animDurationFast,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color:
                focused
                    ? scheme.primary.withValues(alpha: 0.72)
                    : scheme.outline.withValues(alpha: 0.16),
            width: focused ? 1.5 : 1,
          ),
          boxShadow:
              focused
                  ? [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.08),
                      blurRadius: 14,
                    ),
                  ]
                  : const [],
        ),
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: 'Search pages, actions, guides...',
            hintStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.62),
              fontWeight: FontWeight.w400,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: focused ? scheme.primary : scheme.onSurfaceVariant,
            ),
            suffixIcon:
                _controller.text.isEmpty
                    ? null
                    : IconButton(
                      onPressed: () {
                        _controller.clear();
                        _filter('');
                        _focusNode.requestFocus();
                      },
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close_rounded, size: 19),
                    ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 17),
          ),
          onChanged: _filter,
          onSubmitted: (_) => _selectCurrent(),
        ),
      ),
    );
  }

  Widget _buildResults(ColorScheme scheme) {
    if (_filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.search_off_rounded,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Nothing matches "${_controller.text}"',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Try a page name, action, course tool, or guide topic.',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    CommandCategory? lastCategory;
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
      shrinkWrap: true,
      itemCount: _filtered.length,
      itemBuilder: (context, index) {
        final entry = _filtered[index];
        final isSelected = index == _selectedIndex;
        final showHeader =
            entry.category != lastCategory && _controller.text.isEmpty;
        lastCategory = entry.category;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showHeader)
              Padding(
                padding: EdgeInsets.fromLTRB(8, index == 0 ? 6 : 16, 8, 7),
                child: Row(
                  children: [
                    Icon(
                      entry.category.icon,
                      size: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      entry.category.label.toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.05,
                      ),
                    ),
                  ],
                ),
              ),
            Semantics(
              selected: isSelected,
              button: true,
              child: InkWell(
                onTap: () {
                  setState(() => _selectedIndex = index);
                  _selectCurrent();
                },
                onHover: (hovering) {
                  if (hovering) setState(() => _selectedIndex = index);
                },
                borderRadius: BorderRadius.circular(14),
                child: AnimatedContainer(
                  duration:
                      MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : AppDesign.animDurationFast,
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color:
                        isSelected
                            ? scheme.primary.withValues(alpha: 0.095)
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color:
                          isSelected
                              ? scheme.primary.withValues(alpha: 0.16)
                              : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration:
                            MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : AppDesign.animDurationFast,
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color:
                              isSelected
                                  ? scheme.primary
                                  : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          entry.icon,
                          size: 18,
                          color:
                              isSelected
                                  ? scheme.onPrimary
                                  : scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              entry.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(
                                context,
                              ).textTheme.titleSmall?.copyWith(
                                fontFamily: 'SpaceGrotesk',
                                fontWeight:
                                    isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                              ),
                            ),
                            if (entry.subtitle != null) ...[
                              const SizedBox(height: 1),
                              Text(
                                entry.subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (entry.shortcut != null) ...[
                        const SizedBox(width: 10),
                        _keycap(scheme, entry.shortcut!),
                      ],
                      if (isSelected) ...[
                        const SizedBox(width: 10),
                        Icon(
                          Icons.keyboard_return_rounded,
                          size: 16,
                          color: scheme.primary,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFooter(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.72),
        border: Border(
          top: BorderSide(color: scheme.outline.withValues(alpha: 0.1)),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 440;
          return Row(
            children: [
              Text(
                '${_filtered.length} result${_filtered.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (!compact) ...[
                _footerHint(scheme, 'Up/Down', 'navigate'),
                const SizedBox(width: 12),
              ],
              _footerHint(scheme, 'Enter', compact ? null : 'open'),
              const SizedBox(width: 12),
              _footerHint(scheme, 'Esc', compact ? null : 'close'),
            ],
          );
        },
      ),
    );
  }

  Widget _footerHint(ColorScheme scheme, String key, String? label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _keycap(scheme, key),
        if (label != null) ...[
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  Widget _keycap(ColorScheme scheme, String key) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.14)),
      ),
      child: Text(
        key,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.15,
        ),
      ),
    );
  }
}
