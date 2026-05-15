enum SourceType {
  officialLink,
  emailScreenshot,
  lmsLink,
  photo,
  crossReference,
  secondhand,
  none,
}

class AnnouncementSource {
  final SourceType type;
  final String? url;
  final String? referenceId;

  const AnnouncementSource({
    this.type = SourceType.none,
    this.url,
    this.referenceId,
  });

  factory AnnouncementSource.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const AnnouncementSource();
    return AnnouncementSource(
      type: _parseType(map['type']),
      url: map['url'],
      referenceId: map['referenceId'],
    );
  }

  Map<String, dynamic> toMap() => {
        'type': type.name,
        'url': url,
        'referenceId': referenceId,
      };

  String get label {
    switch (type) {
      case SourceType.officialLink:
        return 'Official source';
      case SourceType.emailScreenshot:
        return 'Email/notice attached';
      case SourceType.lmsLink:
        return 'LMS source';
      case SourceType.photo:
        return 'Photo evidence';
      case SourceType.crossReference:
        return 'Cross-referenced';
      case SourceType.secondhand:
        return 'Secondhand';
      case SourceType.none:
        return 'Unverified';
    }
  }

  String get trustLevel {
    switch (type) {
      case SourceType.officialLink:
      case SourceType.emailScreenshot:
      case SourceType.lmsLink:
        return 'high';
      case SourceType.photo:
      case SourceType.crossReference:
        return 'medium';
      case SourceType.secondhand:
        return 'low';
      case SourceType.none:
        return 'none';
    }
  }

  int get disputeQuorum {
    switch (trustLevel) {
      case 'high':
        return 8;
      case 'medium':
        return 6;
      case 'low':
        return 4;
      default:
        return 3;
    }
  }

  bool get isSourced => type != SourceType.none;
  bool get isHighOrMedium => trustLevel == 'high' || trustLevel == 'medium';

  static SourceType _parseType(dynamic value) {
    if (value is String) {
      for (final t in SourceType.values) {
        if (t.name == value) return t;
      }
    }
    return SourceType.none;
  }
}
