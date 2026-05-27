import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/announcement_source.dart';

void main() {
  group('AnnouncementSource', () {
    test('fromMap -> toMap roundtrip', () {
      final source = AnnouncementSource(
        type: SourceType.officialLink,
        url: 'https://example.com',
        referenceId: 'ref-1',
      );

      final map = source.toMap();
      final restored = AnnouncementSource.fromMap(map);

      expect(restored.type, SourceType.officialLink);
      expect(restored.url, 'https://example.com');
      expect(restored.referenceId, 'ref-1');
    });

    test('fromMap with null returns default', () {
      final source = AnnouncementSource.fromMap(null);
      expect(source.type, SourceType.none);
      expect(source.url, isNull);
    });

    test('label returns correct string for each type', () {
      expect(const AnnouncementSource(type: SourceType.officialLink).label, 'Official source');
      expect(const AnnouncementSource(type: SourceType.emailScreenshot).label, 'Email/notice attached');
      expect(const AnnouncementSource(type: SourceType.lmsLink).label, 'LMS source');
      expect(const AnnouncementSource(type: SourceType.photo).label, 'Photo evidence');
      expect(const AnnouncementSource(type: SourceType.crossReference).label, 'Cross-referenced');
      expect(const AnnouncementSource(type: SourceType.secondhand).label, 'Secondhand');
      expect(const AnnouncementSource(type: SourceType.none).label, 'Unverified');
    });

    test('trustLevel categorization', () {
      expect(const AnnouncementSource(type: SourceType.officialLink).trustLevel, 'high');
      expect(const AnnouncementSource(type: SourceType.emailScreenshot).trustLevel, 'high');
      expect(const AnnouncementSource(type: SourceType.lmsLink).trustLevel, 'high');
      expect(const AnnouncementSource(type: SourceType.photo).trustLevel, 'medium');
      expect(const AnnouncementSource(type: SourceType.crossReference).trustLevel, 'medium');
      expect(const AnnouncementSource(type: SourceType.secondhand).trustLevel, 'low');
      expect(const AnnouncementSource(type: SourceType.none).trustLevel, 'none');
    });

    test('disputeQuorum varies by trust level', () {
      expect(const AnnouncementSource(type: SourceType.officialLink).disputeQuorum, 8);
      expect(const AnnouncementSource(type: SourceType.photo).disputeQuorum, 6);
      expect(const AnnouncementSource(type: SourceType.secondhand).disputeQuorum, 4);
      expect(const AnnouncementSource(type: SourceType.none).disputeQuorum, 3);
    });

    test('isSourced returns false only for none', () {
      expect(const AnnouncementSource(type: SourceType.officialLink).isSourced, isTrue);
      expect(const AnnouncementSource(type: SourceType.none).isSourced, isFalse);
    });

    test('isHighOrMedium', () {
      expect(const AnnouncementSource(type: SourceType.officialLink).isHighOrMedium, isTrue);
      expect(const AnnouncementSource(type: SourceType.photo).isHighOrMedium, isTrue);
      expect(const AnnouncementSource(type: SourceType.secondhand).isHighOrMedium, isFalse);
      expect(const AnnouncementSource(type: SourceType.none).isHighOrMedium, isFalse);
    });

    test('fromMap handles unknown type string', () {
      final source = AnnouncementSource.fromMap({'type': 'unknownType'});
      expect(source.type, SourceType.none);
    });
  });
}
