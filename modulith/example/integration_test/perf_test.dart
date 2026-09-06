// Real on-device performance trace: navigates into the Counter feature and
// taps + 20 times, capturing the actual frame build/raster timeline (not
// just Dart-side cost like benchmark/*.dart). Requires --profile (or
// --release) mode to be meaningful — debug builds are unoptimized and their
// timings don't reflect real performance.
//
// Run with (needs a connected device or simulator/desktop target):
//   flutter drive \
//     --driver=test_driver/perf_driver.dart \
//     --target=integration_test/perf_test.dart \
//     --profile -d <device>
//
// Writes build/counter_timeline.timeline_summary.json with frame build/
// raster time percentiles (average, 90th, 99th) and a "missed frame" count.
import 'package:example/app/app_module.dart';
import 'package:flutter/material.dart';
import 'package:modulith/modulith.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tapping Counter.increment repeatedly stays within frame budget', (
    tester,
  ) async {
    await tester.pumpWidget(ModuleWidget(module: AppModule()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Counter'));
    await tester.pumpAndSettle();

    await binding.traceAction(() async {
      for (var i = 0; i < 20; i++) {
        await tester.tap(find.byIcon(Icons.add));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }, reportKey: 'counter_timeline');
  });
}
