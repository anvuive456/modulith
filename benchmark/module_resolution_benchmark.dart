// Micro-benchmark for ModuleScope.getController across nested scopes.
//
// Run with:
//   flutter test benchmark/module_resolution_benchmark.dart
import 'package:flutter/widgets.dart';
import 'package:modulith/modulith.dart';
import 'package:flutter_test/flutter_test.dart';

class EmptyModule extends Module {
  @override
  Widget get view => const SizedBox.shrink();
}

class TargetController extends Controller {}

class RootModule extends Module {
  RootModule(this.controller);

  final TargetController controller;

  @override
  Widget get view => const SizedBox.shrink();

  @override
  List<Provider<Controller>> get controllers => [
    Provider<TargetController>.singleton(create: () => controller),
  ];
}

void main() {
  test('getController resolution time vs. module nesting depth', () {
    const iterations = 20000;

    for (final depth in [1, 10, 50, 100]) {
      final contexts = <ModuleScope>[];
      var current = ModuleScope(module: RootModule(TargetController()))
        ..initialize();
      contexts.add(current);

      for (var i = 0; i < depth; i++) {
        current = ModuleScope(module: EmptyModule(), parent: current)
          ..initialize();
        contexts.add(current);
      }

      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < iterations; i++) {
        current.getController<TargetController>();
      }
      stopwatch.stop();

      final perCallUs = stopwatch.elapsedMicroseconds / iterations;
      // ignore: avoid_print
      print(
        'depth=$depth: ${perCallUs.toStringAsFixed(3)} us/call '
        '($iterations calls)',
      );

      for (final context in contexts.reversed) {
        context.dispose();
      }
    }
  });
}
