import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/services/data/admin_audit_logger.dart';

void main() {
  final logger = AdminAuditLogger();

  setUp(() {
    logger.clear();
    logger.actorResolver = () => 'admin@bits.ac.in';
  });

  group('AdminAuditLogger', () {
    test('records success with actor, action, result and outcome', () {
      logger.success('upload_timetable', 'Uploaded 42 courses', {'campus': 'goa'});

      expect(logger.entries, hasLength(1));
      final e = logger.entries.first;
      expect(e.outcome, AuditOutcome.success);
      expect(e.actor, 'admin@bits.ac.in');
      expect(e.action, 'upload_timetable');
      expect(e.result, 'Uploaded 42 courses');
      expect(e.details, containsPair('campus', 'goa'));
    });

    test('warning and error set the right outcome', () {
      logger.warning('rebuild', 'Updated 0 professors');
      logger.error('archive', 'Archive failed');

      expect(logger.entries[0].outcome, AuditOutcome.error);
      expect(logger.entries[1].outcome, AuditOutcome.warning);
    });

    test('error attaches the error object to details', () {
      logger.error('upload_timetable', 'failed', Exception('boom'));

      final e = logger.entries.first;
      expect(e.details!['error'], contains('boom'));
    });

    test('entries are newest first', () {
      logger.success('a', 'first');
      logger.success('b', 'second');

      expect(logger.entries.first.action, 'b');
      expect(logger.entries.last.action, 'a');
    });

    test('uses the injected actor resolver', () {
      logger.actorResolver = () => 'someone-else';
      logger.success('x', 'y');
      expect(logger.entries.first.actor, 'someone-else');
    });

    test('falls back to "unknown" when the resolver throws', () {
      logger.actorResolver = () => throw StateError('no auth');
      logger.success('x', 'y');
      expect(logger.entries.first.actor, 'unknown');
    });

    test('caps the in-memory trail at maxEntries', () {
      for (var i = 0; i < AdminAuditLogger.maxEntries + 25; i++) {
        logger.success('action_$i', 'r');
      }
      expect(logger.entries, hasLength(AdminAuditLogger.maxEntries));
      // Oldest entries are evicted; the most recent survives at the front.
      expect(logger.entries.first.action,
          'action_${AdminAuditLogger.maxEntries + 24}');
    });

    test('format includes outcome label and actor', () {
      logger.error('archive', 'failed');
      final line = logger.entries.first.format();
      expect(line, contains('[ERROR]'));
      expect(line, contains('admin@bits.ac.in'));
      expect(line, contains('archive — failed'));
    });

    test('notifies listeners on record and clear', () {
      var notifications = 0;
      void listener() => notifications++;
      logger.addListener(listener);

      logger.success('x', 'y');
      logger.clear();

      expect(notifications, 2);
      logger.removeListener(listener);
    });
  });
}
