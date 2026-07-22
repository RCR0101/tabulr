import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/data/auth_service.dart';
import '../screens/profile_screen.dart';
import '../models/timetable_selection_link.dart';
import '../services/ui/theme_service.dart';
import '../utils/design_constants.dart';
import '../utils/page_transitions.dart';
import 'app_destinations.dart';
import 'app_tools.dart';

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
  action('Actions', Icons.bolt);

  final String label;
  final IconData icon;
  const CommandCategory(this.label, this.icon);
}

/// Screens register their context-specific actions here.
/// Keyed by screen identity so only the active screen's actions show.
class CommandPaletteActions {
  CommandPaletteActions._();

  static final Map<DrawerScreen, List<CommandPaletteEntry> Function()> _providers = {};
  static final List<String> _recentLabels = [];
  static const int _maxRecent = 5;

  static void register(DrawerScreen screen, List<CommandPaletteEntry> Function() provider) {
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
  final DrawerScreen currentScreen;
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
    required DrawerScreen currentScreen,
    List<CommandPaletteEntry> contextEntries = const [],
    VoidCallback? onToggleTheme,
    VoidCallback? onSignOut,
    VoidCallback? onReplayTour,
    TimetableSelectionLink? selectionLink,
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => CommandPalette(
        onNavigate: onNavigate,
        currentScreen: currentScreen,
        contextEntries: contextEntries,
        onToggleTheme: onToggleTheme,
        onSignOut: onSignOut,
        onReplayTour: onReplayTour,
        selectionLink: selectionLink,
      ),
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
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<CommandPaletteEntry> _buildEntries() {
    final entries = <CommandPaletteEntry>[];
    final auth = AuthService();
    final nav = Navigator.of(context);

    // All non-recent entries first (we'll inject recents at the end)
    final nonRecentEntries = <CommandPaletteEntry>[];

    // Context-specific actions for the current screen (shown first)
    if (widget.contextEntries.isNotEmpty) {
      nonRecentEntries.addAll(widget.contextEntries);
    } else {
      nonRecentEntries.addAll(CommandPaletteActions.entriesFor(widget.currentScreen));
    }

    // Every shell destination, straight from the registry. Hand-listing these
    // is what let Minors and Academic FAQ ship to the sidebar and never appear
    // here; now a new DrawerScreen shows up in both or compiles in neither.
    // A tool that is also a shell destination wins when there's a timetable to
    // add to — pushing it keeps the editor underneath, navigating would not.
    final linkedScreens = widget.selectionLink == null
        ? const <DrawerScreen>{}
        : {for (final info in AppTools.all) if (info.screen != null) info.screen!};

    nonRecentEntries.addAll([
      for (final destination in AppDestinations.visible)
        if (!linkedScreens.contains(destination.screen))
          CommandPaletteEntry(
            label: destination.label,
            subtitle: destination.description,
            icon: destination.icon,
            category: CommandCategory.navigation,
            onSelect: () => widget.onNavigate(destination.screen),
          ),
    ]);

    if (auth.isAuthenticated) {
      // Not a shell destination — Profile is a pushed route.
      nonRecentEntries.add(CommandPaletteEntry(
        label: 'Profile',
        subtitle: 'Your ID, branch & semester defaults',
        icon: Icons.badge_outlined,
        category: CommandCategory.navigation,
        onSelect: () => nav.push(FadeSlidePageRoute(page: const ProfileScreen())),
      ));
    }

    nonRecentEntries.addAll([
      for (final info in AppTools.all)
        if (info.screen == null || widget.selectionLink != null)
          CommandPaletteEntry(
            label: info.label,
            subtitle: info.description,
            icon: info.icon,
            category: CommandCategory.navigation,
            onSelect: () => nav.push(
                FadeSlidePageRoute(page: info.build(widget.selectionLink))),
          ),
    ]);

    // Global actions
    if (widget.onReplayTour != null) {
      nonRecentEntries.add(CommandPaletteEntry(
        label: 'Show me around',
        subtitle: 'Replay the guided tour for this page',
        icon: Icons.explore_outlined,
        category: CommandCategory.action,
        onSelect: widget.onReplayTour!,
      ));
    }

    if (widget.onToggleTheme != null) {
      nonRecentEntries.add(CommandPaletteEntry(
        label: 'Change Theme',
        subtitle: 'Open the theme picker',
        icon: Icons.brightness_6,
        category: CommandCategory.action,
        onSelect: widget.onToggleTheme!,
      ));
    }

    // Direct theme + mode switches — type "drac", "light", etc. to apply
    // instantly without opening the picker dialog.
    final themeService = ThemeService();
    for (final theme in AppTheme.values) {
      nonRecentEntries.add(CommandPaletteEntry(
        label: 'Theme: ${theme.displayName}',
        subtitle: theme == themeService.currentTheme ? 'Current theme' : 'Apply this theme',
        icon: theme.icon,
        category: CommandCategory.action,
        onSelect: () => themeService.setTheme(theme),
      ));
    }
    nonRecentEntries.addAll([
      CommandPaletteEntry(
        label: 'Dark Mode',
        subtitle: 'Always use the dark palette',
        icon: Icons.dark_mode,
        category: CommandCategory.action,
        onSelect: () => themeService.setThemeMode(ThemeMode.dark),
      ),
      CommandPaletteEntry(
        label: 'Light Mode',
        subtitle: 'Always use the light palette',
        icon: Icons.light_mode,
        category: CommandCategory.action,
        onSelect: () => themeService.setThemeMode(ThemeMode.light),
      ),
      CommandPaletteEntry(
        label: 'System Theme Mode',
        subtitle: 'Match your device setting',
        icon: Icons.brightness_auto,
        category: CommandCategory.action,
        onSelect: () => themeService.setThemeMode(ThemeMode.system),
      ),
    ]);

    if (widget.onSignOut != null && auth.isAuthenticated) {
      nonRecentEntries.add(CommandPaletteEntry(
        label: 'Sign Out',
        icon: Icons.logout,
        category: CommandCategory.action,
        onSelect: widget.onSignOut!,
      ));
    }

    // Inject recent entries at the top
    final recentLabels = CommandPaletteActions.recentLabels;
    if (recentLabels.isNotEmpty) {
      for (final label in recentLabels) {
        final match = nonRecentEntries.where((e) => e.label == label).firstOrNull;
        if (match != null) {
          entries.add(CommandPaletteEntry(
            label: match.label,
            subtitle: match.subtitle,
            icon: match.icon,
            category: CommandCategory.recent,
            onSelect: match.onSelect,
            shortcut: match.shortcut,
          ));
        }
      }
    }

    entries.addAll(nonRecentEntries);
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
    if (queryWords.length > 1 && queryWords.every((qw) => combined.contains(qw))) {
      return 60;
    }

    // Subtitle matches
    if (subtitle.startsWith(query)) return 50;
    if (subtitle.contains(query)) return 40;
    if (queryWords.length > 1 && queryWords.every((qw) => subtitle.contains(qw))) {
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
      const itemHeight = 56.0;
      final targetOffset = _selectedIndex * itemHeight;
      final viewportHeight = _scrollController.position.viewportDimension;
      final currentScroll = _scrollController.offset;

      if (targetOffset < currentScroll) {
        _scrollController.animateTo(targetOffset,
            duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
      } else if (targetOffset + itemHeight > currentScroll + viewportHeight) {
        _scrollController.animateTo(targetOffset + itemHeight - viewportHeight,
            duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final screenSize = MediaQuery.sizeOf(context);
    final maxHeight = math.min(screenSize.height * 0.6, 480.0);

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _moveSelection(1);
          return KeyEventResult.handled;
        } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _moveSelection(-1);
          return KeyEventResult.handled;
        } else if (event.logicalKey == LogicalKeyboardKey.enter) {
          _selectCurrent();
          return KeyEventResult.handled;
        } else if (event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Align(
        alignment: const Alignment(0, -0.3),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: math.min(560.0, screenSize.width - 48),
            constraints: BoxConstraints(maxHeight: maxHeight),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: scheme.outline.withValues(alpha: 0.15)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 40,
                  spreadRadius: 4,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSearchField(scheme),
                Divider(height: 1, color: scheme.outline.withValues(alpha: 0.12)),
                Flexible(child: _buildResults(scheme)),
                _buildFooter(scheme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          Icon(Icons.search, size: 20, color: scheme.primary.withValues(alpha: 0.7)),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: scheme.onSurface),
              decoration: InputDecoration(
                hintText: 'Jump to a feature or action...',
                hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.35),
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: _filter,
              onSubmitted: (_) => _selectCurrent(),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
            ),
            child: Text(
              'Cmd+K',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.4),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(ColorScheme scheme) {
    if (_filtered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'No results found',
          style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5)),
        ),
      );
    }

    CommandCategory? lastCategory;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 4),
      shrinkWrap: true,
      itemCount: _filtered.length,
      itemBuilder: (context, index) {
        final entry = _filtered[index];
        final isSelected = index == _selectedIndex;
        final showHeader = entry.category != lastCategory && _controller.text.isEmpty;
        lastCategory = entry.category;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showHeader)
              Padding(
                padding: EdgeInsets.only(
                  left: 16, right: 16,
                  top: index == 0 ? 4 : 12,
                  bottom: 4,
                ),
                child: Text(
                  entry.category.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface.withValues(alpha: 0.45),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            InkWell(
              onTap: () {
                setState(() => _selectedIndex = index);
                _selectCurrent();
              },
              onHover: (hovering) {
                if (hovering) setState(() => _selectedIndex = index);
              },
              borderRadius: AppDesign.borderRadiusSm,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? scheme.primary.withValues(alpha: 0.1) : null,
                  borderRadius: AppDesign.borderRadiusSm,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? scheme.primary.withValues(alpha: 0.15)
                            : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(entry.icon, size: 16,
                          color: isSelected ? scheme.primary : scheme.onSurface.withValues(alpha: 0.5)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            entry.label,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                              color: isSelected ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.85),
                            ),
                          ),
                          if (entry.subtitle != null)
                            Text(
                              entry.subtitle!,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurface.withValues(alpha: 0.45),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    if (entry.shortcut != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
                          ),
                          child: Text(
                            entry.shortcut!,
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurface.withValues(alpha: 0.4)),
                          ),
                        ),
                      ),
                    if (isSelected)
                      Icon(Icons.keyboard_return, size: 14,
                          color: scheme.onSurface.withValues(alpha: 0.3)),
                  ],
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outline.withValues(alpha: 0.12))),
      ),
      child: Row(
        children: [
          _footerHint(scheme, '↑↓', 'Navigate'),
          const SizedBox(width: 16),
          _footerHint(scheme, '↵', 'Select'),
          const SizedBox(width: 16),
          _footerHint(scheme, 'esc', 'Close'),
        ],
      ),
    );
  }

  Widget _footerHint(ColorScheme scheme, String key, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: scheme.outline.withValues(alpha: 0.15)),
          ),
          child: Text(key, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurface.withValues(alpha: 0.5))),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: scheme.onSurface.withValues(alpha: 0.4))),
      ],
    );
  }
}
