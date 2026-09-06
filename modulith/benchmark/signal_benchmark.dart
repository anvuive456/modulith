// Micro-benchmark for Signal.value= (set + notifyListeners) at varying
// listener counts. Informational only — no pass/fail threshold, since wall
// -clock numbers vary by machine and would make CI flaky. Run it and read
// the printed µs numbers; use it to catch a regression that changes the
// complexity class (e.g. an accidental O(n²)), not to gate on an exact
// number.
//
// Run with:
//   flutter test benchmark/signal_benchmark.dart
import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:modulith/modulith.dart';
import 'package:flutter_test/flutter_test.dart';

class SignalSetBenchmark extends BenchmarkBase {
  SignalSetBenchmark(this.listenerCount)
    : super('Signal.value= with $listenerCount listener(s)');

  final int listenerCount;
  late Signal<int> signal;
  int _next = 0;

  @override
  void setup() {
    signal = Signal<int>(0);
    for (var i = 0; i < listenerCount; i++) {
      signal.addListener(() {});
    }
  }

  @override
  void run() {
    signal.value = _next++;
  }

  @override
  void teardown() {
    signal.dispose();
  }
}

void main() {
  test('Signal.value= scaling with listener count', () {
    for (final listenerCount in [0, 1, 10, 100]) {
      SignalSetBenchmark(listenerCount).report();
    }
  });
}
