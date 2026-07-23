import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/services/ui/remote_log_sink.dart';

void main() {
  final sink = RemoteLogSink();

  // Captured POSTs: (url, headers, decoded-body).
  late List<Map<String, dynamic>> posted;

  setUp(() {
    sink.resetForTest();
    posted = [];
    sink.poster = (url, headers, body) async {
      posted.add({
        'url': url.toString(),
        'headers': headers,
        'body': jsonDecode(body),
      });
    };
  });

  group('RemoteLogSink', () {
    test('does nothing until initialized', () {
      sink.enqueue({'message': 'x'}, levelIndex: 3);
      expect(sink.bufferLength, 0);
    });

    test('buffers records once enabled', () {
      sink.initialize(enabled: true);
      sink.enqueue({'message': 'a'}, levelIndex: 1);
      sink.enqueue({'message': 'b'}, levelIndex: 1);
      expect(sink.bufferLength, 2);
    });

    test('drops records below minLevel', () {
      sink.initialize(enabled: true, minLevelIndex: 2); // warning+
      sink.enqueue({'message': 'debug'}, levelIndex: 0);
      sink.enqueue({'message': 'info'}, levelIndex: 1);
      sink.enqueue({'message': 'warn'}, levelIndex: 2);
      sink.enqueue({'message': 'err'}, levelIndex: 3);
      expect(sink.bufferLength, 2);
    });

    test('drops everything when disabled', () {
      sink.initialize(enabled: false);
      sink.enqueue({'message': 'x'}, levelIndex: 3);
      expect(sink.bufferLength, 0);
    });

    test('flush posts the batch to /log and clears the buffer', () async {
      sink.initialize(enabled: true, workerUrl: 'https://logger.test');
      sink.enqueue({'message': 'a'}, levelIndex: 1);
      sink.enqueue({'message': 'b'}, levelIndex: 1);

      await sink.flush();

      expect(posted, hasLength(1));
      expect(posted.first['url'], 'https://logger.test/log');
      final body = posted.first['body'] as Map<String, dynamic>;
      expect(body['entries'], hasLength(2));
      expect(body['metadata'], isA<Map>());
      expect(sink.bufferLength, 0);
    });

    test('attaches a bearer token when an api key is set', () async {
      sink.initialize(enabled: true, apiKey: 'secret123');
      sink.enqueue({'message': 'a'}, levelIndex: 1);
      await sink.flush();

      final headers = posted.first['headers'] as Map<String, String>;
      expect(headers['Authorization'], 'Bearer secret123');
    });

    test('omits the auth header when no api key is set', () async {
      sink.initialize(enabled: true);
      sink.enqueue({'message': 'a'}, levelIndex: 1);
      await sink.flush();

      final headers = posted.first['headers'] as Map<String, String>;
      expect(headers.containsKey('Authorization'), isFalse);
    });

    test('auto-flushes when the threshold is reached', () {
      sink.initialize(enabled: true);
      for (var i = 0; i < 50; i++) {
        sink.enqueue({'message': 'm$i'}, levelIndex: 1);
      }
      // Threshold (50) triggers a synchronous flush() that empties the buffer.
      expect(sink.bufferLength, 0);
      expect(posted, hasLength(1));
    });

    test('swallows poster errors without throwing', () async {
      sink.initialize(enabled: true);
      sink.poster = (_, __, ___) async => throw Exception('network down');
      sink.enqueue({'message': 'a'}, levelIndex: 1);

      await sink.flush(); // must not throw
      expect(sink.bufferLength, 0); // batch was taken even though POST failed
    });

    test('flush is a no-op with an empty buffer', () async {
      sink.initialize(enabled: true);
      await sink.flush();
      expect(posted, isEmpty);
    });

    test('stamps the app user id onto every buffered record', () async {
      sink.initialize(enabled: true, workerUrl: 'https://logger.test');
      sink.setUserId('f20220123H');
      sink.enqueue({'message': 'a'}, levelIndex: 1);
      sink.enqueue({'message': 'b'}, levelIndex: 2);
      await sink.flush();

      final entries = (posted.first['body'] as Map)['entries'] as List;
      expect(entries, hasLength(2));
      expect(entries.every((e) => e['userId'] == 'f20220123H'), isTrue);
    });

    test('omits userId for guests / signed-out (null id)', () async {
      sink.initialize(enabled: true);
      // No setUserId call → null.
      sink.enqueue({'message': 'a'}, levelIndex: 1);
      await sink.flush();

      final entry = ((posted.first['body'] as Map)['entries'] as List).first;
      expect((entry as Map).containsKey('userId'), isFalse);
    });

    test('a later setUserId(null) stops attributing subsequent records', () async {
      sink.initialize(enabled: true);
      sink.setUserId('f20220123H');
      sink.enqueue({'message': 'signed-in'}, levelIndex: 1);
      sink.setUserId(null); // sign-out
      sink.enqueue({'message': 'signed-out'}, levelIndex: 1);
      await sink.flush();

      final entries = (posted.first['body'] as Map)['entries'] as List;
      expect(entries[0]['userId'], 'f20220123H');
      expect((entries[1] as Map).containsKey('userId'), isFalse);
    });
  });
}
