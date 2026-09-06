// Performance tests for the reactive/rebuild story: they don't measure wall
// -clock time (flaky across machines/CI), they assert *how many times*
// something rebuilds. This is the property that actually matters for a
// signal-based state system: a change to one Signal must only rebuild the
// [SignalBuilder] wrapping it, never the enclosing view/module, and never an
// unrelated [SignalBuilder] watching a different signal.
import 'package:flutter/material.dart';
import 'package:modulith/modulith.dart';
import 'package:flutter_test/flutter_test.dart';

class CounterController extends Controller {
  late final count = createSignal<int>(0);
}

class ChildTestModule extends Module {
  ChildTestModule({required this.view, required this.controllers});

  @override
  final Widget view;

  @override
  final List<Provider<Controller>> controllers;
}

class TestModule extends Module {
  TestModule({
    required this.view,
    this.controllers = const [],
    this.children = const [],
  });

  @override
  final Widget view;

  @override
  final List<Provider<Controller>> controllers;

  @override
  final List<Module> children;
}

int viewBuildCount = 0;
int signalBuilderCount = 0;

class CountingView extends ModularWidget {
  const CountingView({super.key});

  @override
  Widget build(ModuleContext context) {
    viewBuildCount++;
    final controller = context.getController<CounterController>();
    return SignalBuilder(
      signal: controller.count,
      builder: (value) {
        signalBuilderCount++;
        return Text('$value', textDirection: TextDirection.ltr);
      },
    );
  }
}

int parentViewBuildCount = 0;
int childViewBuildCount = 0;

class ChildCountingView extends ModularWidget {
  const ChildCountingView({super.key});

  @override
  Widget build(ModuleContext context) {
    childViewBuildCount++;
    final controller = context.getController<CounterController>();
    return SignalBuilder(
      signal: controller.count,
      builder: (value) =>
          Text('child:$value', textDirection: TextDirection.ltr),
    );
  }
}

class ParentCountingView extends ModularWidget {
  const ParentCountingView({super.key});

  @override
  Widget build(ModuleContext context) {
    parentViewBuildCount++;
    return const ChildModuleView<ChildTestModule>();
  }
}

void main() {
  setUp(() {
    viewBuildCount = 0;
    signalBuilderCount = 0;
    parentViewBuildCount = 0;
    childViewBuildCount = 0;
  });

  testWidgets('SignalBuilder only rebuilds for its own signal, not a sibling', (
    tester,
  ) async {
    final a = Signal<int>(0);
    final b = Signal<int>(0);
    var aBuilds = 0;
    var bBuilds = 0;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            SignalBuilder(
              signal: a,
              builder: (value) {
                aBuilds++;
                return Text('a:$value');
              },
            ),
            SignalBuilder(
              signal: b,
              builder: (value) {
                bBuilds++;
                return Text('b:$value');
              },
            ),
          ],
        ),
      ),
    );
    expect(aBuilds, 1);
    expect(bBuilds, 1);

    a.value = 1;
    await tester.pump();
    expect(aBuilds, 2); // only a's SignalBuilder rebuilt...
    expect(bBuilds, 1); // ...b's is untouched

    b.value = 1;
    await tester.pump();
    expect(aBuilds, 2);
    expect(bBuilds, 2);

    a.dispose();
    b.dispose();
  });

  testWidgets(
    'updating a Signal rebuilds only its SignalBuilder, not the enclosing ModularWidget',
    (tester) async {
      final controller = CounterController();
      final module = TestModule(
        view: const CountingView(),
        controllers: [
          Provider<CounterController>.singleton(create: () => controller),
        ],
      );

      await tester.pumpWidget(ModuleWidget(module: module));
      expect(viewBuildCount, 1);
      expect(signalBuilderCount, 1);

      // Mutate the signal 5 times; the ModularWidget above it must not
      // rebuild at all (its build() only runs once, on mount), while the
      // SignalBuilder rebuilds once per change.
      for (var i = 1; i <= 5; i++) {
        controller.count.value = i;
        await tester.pump();
      }

      expect(
        viewBuildCount,
        1,
        reason: 'the view itself must not rebuild on signal changes',
      );
      expect(signalBuilderCount, 6, reason: '1 initial build + 5 updates');
    },
  );

  testWidgets('a child module signal update does not rebuild the parent view', (
    tester,
  ) async {
    final childController = CounterController();
    final child = ChildTestModule(
      view: const ChildCountingView(),
      controllers: [
        Provider<CounterController>.singleton(create: () => childController),
      ],
    );
    final parent = TestModule(
      view: const ParentCountingView(),
      children: [child],
    );

    await tester.pumpWidget(ModuleWidget(module: parent));
    expect(parentViewBuildCount, 1);
    expect(childViewBuildCount, 1);

    childController.count.value = 1;
    await tester.pump();
    childController.count.value = 2;
    await tester.pump();

    expect(
      childViewBuildCount,
      1,
      reason: "ChildCountingView's own build() doesn't re-run either",
    );
    expect(
      parentViewBuildCount,
      1,
      reason: 'the parent view must never rebuild for this at all',
    );
    expect(
      find.text('child:2'),
      findsOneWidget,
    ); // the SignalBuilder itself did update
  });
}
