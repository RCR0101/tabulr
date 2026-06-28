import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_constants.dart';
import '../services/data/config_service.dart';
import '../services/data/local_cache_service.dart';
import '../utils/design_constants.dart';

/// A person shown in the credits (creator, contributor, or admin).
class _Person {
  final String name;
  final String? subtitle;
  final String? avatarUrl;
  final String? url;

  const _Person({
    required this.name,
    this.subtitle,
    this.avatarUrl,
    this.url,
  });

  Map<String, dynamic> toMap() =>
      {'name': name, 'subtitle': subtitle, 'avatarUrl': avatarUrl, 'url': url};

  factory _Person.fromMap(Map<String, dynamic> m) => _Person(
        name: m['name'] as String? ?? '',
        subtitle: m['subtitle'] as String?,
        avatarUrl: m['avatarUrl'] as String?,
        url: m['url'] as String?,
      );
}

class CreditsScreen extends StatefulWidget {
  const CreditsScreen({super.key});

  @override
  State<CreditsScreen> createState() => _CreditsScreenState();
}

class _CreditsScreenState extends State<CreditsScreen> {
  // ── Configure these ───────────────────────────────────────────────────────

  /// "owner/repo" on GitHub. When set, the Contributors section is fetched
  /// live from the GitHub API. Leave empty to fall back to [_manualContributors].
  static const String _githubRepoSlug = 'RCR0101/timetable_maker';

  static const _creator = _Person(
    name: 'Aryan Dalmia',
    subtitle: 'Creator & Maintainer',
  );

  /// Used when [_githubRepoSlug] is empty or the GitHub fetch fails.
  static const List<_Person> _manualContributors = [];

  // ── Caching ───────────────────────────────────────────────────────────────
  //
  // Two tiers: a process-wide in-memory cache (survives re-opening the screen
  // within a session, and covers web where the on-disk cache is a no-op) plus
  // [LocalCacheService] (persists across sessions with a 72h TTL on
  // desktop/mobile). Either hit avoids the GitHub call and the billed
  // getAdmins function invocation.

  static List<_Person>? _memContributors;
  static List<_Person>? _memAdmins;

  static const _contributorsCacheKey = 'credits_contributors';
  static const _adminsCacheKey = 'credits_admins';

  /// Credits change very rarely, so cache for 30 days rather than the default 72h.
  static const _cacheTtlHours = 24 * 30;

  final LocalCacheService _localCache = LocalCacheService();

  // ──────────────────────────────────────────────────────────────────────────

  List<_Person> _contributors = _manualContributors;
  bool _loadingContributors = _githubRepoSlug.isNotEmpty;

  List<_Person> _admins = const [];
  bool _loadingAdmins = true;

  @override
  void initState() {
    super.initState();
    if (_githubRepoSlug.isNotEmpty) _loadContributors();
    _loadAdmins();
  }

  Future<void> _loadAdmins() async {
    final cached = _memAdmins ?? await _readCache(_adminsCacheKey);
    if (cached != null) {
      _memAdmins = cached;
      if (mounted) {
        setState(() {
          _admins = cached;
          _loadingAdmins = false;
        });
      }
      return;
    }

    try {
      final res = await FirebaseFunctions.instanceFor(
              region: FirebaseConfig.functionsRegion)
          .httpsCallable('getAdmins')
          .call();
      final list = ((res.data as Map)['admins'] as List? ?? [])
          .cast<Map<dynamic, dynamic>>();
      _admins = list
          .map((a) => _Person(
                name: a['name'] as String? ?? '',
                subtitle: 'Admin',
                avatarUrl: a['photoUrl'] as String?,
              ))
          .where((p) => p.name.isNotEmpty)
          .toList();
      if (_admins.isNotEmpty) {
        _memAdmins = _admins;
        await _writeCache(_adminsCacheKey, _admins);
      }
    } catch (_) {
      // Leave empty on failure; the section shows a friendly note.
    }
    if (mounted) setState(() => _loadingAdmins = false);
  }

  Future<void> _loadContributors() async {
    final cached = _memContributors ?? await _readCache(_contributorsCacheKey);
    if (cached != null) {
      _memContributors = cached;
      if (mounted) {
        setState(() {
          _contributors = cached;
          _loadingContributors = false;
        });
      }
      return;
    }

    try {
      final res = await http.get(
        Uri.parse(
            'https://api.github.com/repos/$_githubRepoSlug/contributors?per_page=50'),
        headers: {'Accept': 'application/vnd.github+json'},
      );
      if (res.statusCode == 200) {
        final list = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
        final fetched = list
            .where((c) => (c['type'] == 'User') &&
                !(c['login'] as String? ?? '').endsWith('[bot]'))
            .map((c) {
              final n = (c['contributions'] as num?)?.toInt() ?? 0;
              return _Person(
                name: c['login'] as String? ?? '',
                subtitle: '$n contribution${n == 1 ? '' : 's'}',
                avatarUrl: c['avatar_url'] as String?,
                url: c['html_url'] as String?,
              );
            }).toList();
        if (fetched.isNotEmpty) {
          _contributors = fetched;
          _memContributors = fetched;
          await _writeCache(_contributorsCacheKey, fetched);
        }
      }
    } catch (_) {
      // Keep the manual fallback on any error.
    }
    if (mounted) setState(() => _loadingContributors = false);
  }

  Future<List<_Person>?> _readCache(String key) async {
    final raw = await _localCache.read(key, maxAgeHours: _cacheTtlHours);
    if (raw == null || raw.isEmpty) return null;
    return raw.map((m) => _Person.fromMap(m)).toList();
  }

  Future<void> _writeCache(String key, List<_Person> people) =>
      _localCache.write(key, people.map((p) => p.toMap()).toList());

  Future<void> _open(String? url) async {
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppDesign.appBar(context, title: 'Credits'),
      body: ListView(
        padding: const EdgeInsets.all(AppDesign.spacingMd),
        children: [
          _appHeader(scheme),
          const SizedBox(height: AppDesign.spacingLg),
          _section('Creator', [_personTile(_creator, scheme)]),
          const SizedBox(height: AppDesign.spacingLg),
          _section('GitHub Contributors', _contributorChildren(scheme)),
          const SizedBox(height: AppDesign.spacingLg),
          _section('Tabulr Admins', _adminChildren(scheme)),
          const SizedBox(height: AppDesign.spacingXl),
        ],
      ),
    );
  }

  List<Widget> _adminChildren(ColorScheme scheme) {
    if (_loadingAdmins) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: AppDesign.spacingMd),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_admins.isEmpty) {
      return [_emptyNote('Admins will be listed here.', scheme)];
    }
    return [for (final a in _admins) _personTile(a, scheme)];
  }

  List<Widget> _contributorChildren(ColorScheme scheme) {
    if (_loadingContributors) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: AppDesign.spacingMd),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_contributors.isEmpty) {
      return [
        _emptyNote(
            'Contributors will appear here once the repository is linked.',
            scheme),
      ];
    }
    // Contributor names are GitHub handles — show them verbatim.
    return [
      for (final c in _contributors) _personTile(c, scheme, titleCase: false)
    ];
  }

  Widget _appHeader(ColorScheme scheme) {
    final config = ConfigService();
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [scheme.primary, scheme.secondary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: Icon(Icons.calendar_month_rounded,
              color: scheme.onPrimary, size: 34),
        ),
        const SizedBox(height: AppDesign.spacingSm + 4),
        Text(config.appName,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text('v${config.appVersion}',
            style: TextStyle(fontSize: 12, color: AppDesign.muted(context))),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Made with ',
                style: TextStyle(fontSize: 12, color: AppDesign.muted(context))),
            Icon(Icons.favorite, size: 12, color: Colors.red.withValues(alpha: 0.7)),
            Text(' for students',
                style: TextStyle(fontSize: 12, color: AppDesign.muted(context))),
          ],
        ),
      ],
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: AppDesign.spacingSm),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: Theme.of(context).colorScheme.primary),
          ),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: AppDesign.cardDecoration(context),
          // ListTiles paint ink/background on the nearest Material; provide a
          // transparent one above the decorated box so they stay visible.
          child: Material(
            color: Colors.transparent,
            child: Column(children: children),
          ),
        ),
      ],
    );
  }

  Widget _personTile(_Person person, ColorScheme scheme,
      {bool titleCase = true}) {
    final initials = person.name.isEmpty
        ? '?'
        : person.name.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0]).join();
    return ListTile(
      onTap: person.url == null ? null : () => _open(person.url),
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: scheme.primary.withValues(alpha: 0.15),
        backgroundImage: (person.avatarUrl != null)
            ? NetworkImage(person.avatarUrl!)
            : null,
        child: person.avatarUrl == null
            ? Text(initials.toUpperCase(),
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary))
            : null,
      ),
      title: Text(titleCase ? _titleCase(person.name) : person.name,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: person.subtitle == null
          ? null
          : Text(person.subtitle!, style: const TextStyle(fontSize: 12)),
      trailing: person.url == null
          ? null
          : Icon(Icons.open_in_new_rounded,
              size: 16, color: AppDesign.muted(context)),
    );
  }

  /// Capitalises the first letter of each word, lowercasing the rest, so names
  /// like "ARYAN DALMIA" or "aryan dalmia" render consistently.
  String _titleCase(String s) => s
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');

  Widget _emptyNote(String text, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.all(AppDesign.spacingMd),
      child: Text(text,
          style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: AppDesign.muted(context))),
    );
  }
}
