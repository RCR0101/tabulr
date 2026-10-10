import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/utils/download_failure.dart';

void main() {
  test('each failure gets its own plain reason', () {
    final reasons = {
      downloadFailureReason(),
      downloadFailureReason(insecure: true),
      downloadFailureReason(status: 403),
      downloadFailureReason(status: 404),
      downloadFailureReason(status: 429),
      downloadFailureReason(status: 503),
      downloadFailureReason(status: 418),
      downloadFailureReason(error: TimeoutException('slow')),
      downloadFailureReason(error: Exception('XMLHttpRequest error')),
    };
    expect(reasons, hasLength(9));
    expect(downloadFailureReason(status: 401), downloadFailureReason(status: 403));
    expect(downloadFailureReason(status: 503), contains('503'));
    expect(reasons.where((r) => r.contains('Exception') || r.contains('XMLHttpRequest')), isEmpty);
  });
}
