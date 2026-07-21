import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/utils/debouncer.dart';

void main() {
  group('Debouncer', () {
    test('runs the action once after the quiet period', () {
      fakeAsync((async) {
        final d = Debouncer(duration: const Duration(milliseconds: 250));
        var calls = 0;
        d.run(() => calls++);

        async.elapse(const Duration(milliseconds: 249));
        expect(calls, 0);
        async.elapse(const Duration(milliseconds: 1));
        expect(calls, 1);
      });
    });

    test('a burst collapses to the last call', () {
      fakeAsync((async) {
        final d = Debouncer(duration: const Duration(milliseconds: 250));
        final seen = <int>[];
        for (var i = 0; i < 5; i++) {
          d.run(() => seen.add(i));
          async.elapse(const Duration(milliseconds: 100)); // never quiet enough
        }
        expect(seen, isEmpty);

        async.elapse(const Duration(milliseconds: 250));
        expect(seen, [4]); // only the final scheduled call survives
      });
    });

    test('cancel drops a pending call', () {
      fakeAsync((async) {
        final d = Debouncer(duration: const Duration(milliseconds: 250));
        var calls = 0;
        d.run(() => calls++);
        d.cancel();
        async.elapse(const Duration(seconds: 1));
        expect(calls, 0);
      });
    });

    test('dispose prevents a queued call from firing later', () {
      // The reason every owner must dispose: otherwise the callback can run
      // after the widget is gone and touch a disposed State.
      fakeAsync((async) {
        final d = Debouncer(duration: const Duration(milliseconds: 250));
        var calls = 0;
        d.run(() => calls++);
        d.dispose();
        async.elapse(const Duration(seconds: 1));
        expect(calls, 0);
      });
    });

    test('isActive reflects whether a call is pending', () {
      fakeAsync((async) {
        final d = Debouncer(duration: const Duration(milliseconds: 250));
        expect(d.isActive, isFalse);
        d.run(() {});
        expect(d.isActive, isTrue);
        async.elapse(const Duration(milliseconds: 250));
        expect(d.isActive, isFalse);
      });
    });
  });
}
