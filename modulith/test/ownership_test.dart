import 'dart:async';

import 'package:flutter/material.dart';
import 'package:modulith/modulith.dart';
import 'package:flutter_test/flutter_test.dart';

class TestModule extends Module {
  TestModule({
    required this.view,
    this.controllers = const [],
    this.services = const [],
    this.children = const [],
  });

  @override
  final Widget view;

  @override
  final List<Provider<Controller>> controllers;

  @override
  final List<Provider<Service>> services;

  @override
  final List<Module> children;
}

class ChildTestModule extends TestModule {
  ChildTestModule({required super.view, super.controllers, super.services});
}

class CountingService extends Service {
  static int created = 0;
  static int disposed = 0;

  static void reset() {
    created = 0;
    disposed = 0;
  }

  CountingService() {
    created++;
  }
}

class TrackedController extends Controller {
  static int created = 0;
  static int disposed = 0;
  static void reset() {
    created = 0;
    disposed = 0;
  }

  TrackedController() {
    created++;
  }

  late final tick = createSignal<int>(0);

  @override
  void dispose() {
    disposed++;
    super.dispose();
  }
}

class HostController extends Controller {
  late final TrackedController injected;

  @override
  void init() => injected = injectController<TrackedController>();
}

class SlowController extends Controller {
  SlowController({this.guard = true});

  final bool guard;
  late final value = createSignal<int>(0);

  @override
  void init() {
    Future<void>.delayed(const Duration(milliseconds: 500)).then((_) {
      if (guard && isDisposed) return;
      value.value = 1;
    });
  }
}

class CleanupController extends Controller {
  final List<String> log = [];
  Timer? timer;

  @override
  void init() {
    timer = Timer.periodic(const Duration(seconds: 1), (_) {});
    addDisposeCallback(() => log.add('first'));
    addDisposeCallback(() => log.add('second'));
    addDisposeCallback(() {
      timer?.cancel();
      log.add('timer');
    });
  }
}

class FactoryProbe extends ModularWidget {
  const FactoryProbe({required this.tick, super.key});

  final int tick;

  @override
  Widget build(ModuleContext context) {
    context.getController<TrackedController>();
    return Text('$tick', textDirection: TextDirection.ltr);
  }
}

/// Resolves a service and hands it to [onResolved], so an overrides test can
/// check what the module scope actually produced.
class ServiceProbe extends ModularWidget {
  const ServiceProbe({required this.onResolved, super.key});

  final void Function(CountingService service) onResolved;

  @override
  Widget build(ModuleContext context) {
    onResolved(context.getService<CountingService>());
    return const SizedBox.shrink();
  }
}

class Rebuilder extends StatefulWidget {
  const Rebuilder({required this.builder, super.key});

  final Widget Function(int tick) builder;

  @override
  State<Rebuilder> createState() => RebuilderState();
}

class RebuilderState extends State<Rebuilder> {
  int tick = 0;

  void bump() => setState(() => tick++);

  @override
  Widget build(BuildContext context) => widget.builder(tick);
}

void main() {
  setUp(() {
    CountingService.reset();
    TrackedController.reset();
  });

  group('1. disposed scopes', () {
    test('resolving through a disposed ancestor throws instead of leaking', () {
      final parentModule = TestModule(
        view: const SizedBox.shrink(),
        services: [
          Provider<CountingService>.singleton(
            create: CountingService.new,
            dispose: (_) => CountingService.disposed++,
          ),
        ],
      );
      final parent = ModuleScope(module: parentModule)..initialize();
      final child = ModuleScope(
        module: TestModule(view: const SizedBox.shrink()),
        parent: parent,
      )..initialize();

      child.getService<CountingService>();
      parent.dispose();
      expect(CountingService.created, 1);
      expect(CountingService.disposed, 1);

      expect(
        () => child.getService<CountingService>(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('has already been disposed'),
          ),
        ),
      );
      // No orphan instance was created on the dead scope.
      expect(CountingService.created, 1);

      child.dispose();
    });

    test('a disposed scope cannot resolve from itself either', () {
      final context = ModuleScope(
        module: TestModule(
          view: const SizedBox.shrink(),
          services: [
            Provider<CountingService>.singleton(create: CountingService.new),
          ],
        ),
      )..initialize();
      context.dispose();

      expect(() => context.getService<CountingService>(), throwsStateError);
      expect(CountingService.created, 0);
    });
  });

  group('2. signal equality', () {
    test('writing an equal value does not notify', () {
      final controller = TrackedController();
      var notifications = 0;
      controller.tick.addListener(() => notifications++);

      controller.tick.value = 1;
      controller.tick.value = 1;
      controller.tick.value = 1;

      expect(notifications, 1);
      expect(controller.tick.value, 1);
    });

    test('refresh notifies without changing the value', () {
      final controller = TrackedController();
      var notifications = 0;
      controller.tick.addListener(() => notifications++);

      controller.tick.refresh();
      controller.tick.refresh();

      expect(notifications, 2);
      expect(controller.tick.value, 0);
    });

    testWidgets('SignalBuilder does not rebuild for an equal value', (
      tester,
    ) async {
      final controller = TrackedController();
      var builds = 0;

      await tester.pumpWidget(
        SignalBuilder<int>(
          signal: controller.tick,
          builder: (value) {
            builds++;
            return Text('$value', textDirection: TextDirection.ltr);
          },
        ),
      );
      expect(builds, 1);

      controller.tick.value = 0;
      await tester.pump();
      expect(builds, 1);

      controller.tick.value = 1;
      await tester.pump();
      expect(builds, 2);
    });
  });

  group('3. controller teardown', () {
    test('isDisposed is false during a subclass override, true after', () {
      final controller = SlowController();
      expect(controller.isDisposed, isFalse);
      controller.dispose();
      expect(controller.isDisposed, isTrue);
    });

    test('writing a signal after dispose is a no-op', () {
      final controller = TrackedController();
      controller.tick.value = 7;
      controller.dispose();

      controller.tick.value = 42;

      expect(controller.tick.value, 7);
      expect(controller.tick.isDisposed, isTrue);
    });

    test('a signal created after dispose is inert, not leaked', () {
      final controller = TrackedController()..dispose();

      final signal = controller.tick;

      expect(signal.isDisposed, isTrue);
      signal.value = 42;
      expect(signal.value, 0);
    });

    test('dispose callbacks run in reverse order', () {
      final controller = CleanupController()..init();
      expect(controller.timer!.isActive, isTrue);

      controller.dispose();

      expect(controller.log, ['timer', 'second', 'first']);
      expect(controller.timer!.isActive, isFalse);
    });

    test('a dispose callback registered after dispose runs immediately', () {
      final controller = CleanupController()..init();
      controller.dispose();
      controller.log.clear();

      controller.init();

      expect(controller.log, ['first', 'second', 'timer']);
      expect(controller.timer!.isActive, isFalse);
    });

    testWidgets('async work finishing after unmount does not crash', (
      tester,
    ) async {
      await tester.pumpWidget(
        ModuleWidget(
          module: TestModule(
            view: const SizedBox.shrink(),
            controllers: [
              Provider<SlowController>.singleton(
                create: () => SlowController(guard: false),
              ),
            ],
          ),
        ),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
    });
  });

  group('5a. factory ownership', () {
    testWidgets('ModularWidget releases the previous build instances', (
      tester,
    ) async {
      final key = GlobalKey<RebuilderState>();
      await tester.pumpWidget(
        ModuleWidget(
          module: TestModule(
            view: Rebuilder(
              key: key,
              builder: (tick) => FactoryProbe(tick: tick),
            ),
            controllers: [
              Provider<TrackedController>.factory(
                create: TrackedController.new,
              ),
            ],
          ),
        ),
      );

      expect(TrackedController.created, 1);
      expect(TrackedController.disposed, 0);

      for (var i = 0; i < 20; i++) {
        key.currentState!.bump();
        await tester.pump();
      }

      // One instance per build, and only the current build's is alive.
      expect(TrackedController.created, 21);
      expect(TrackedController.disposed, 20);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(TrackedController.disposed, 21);
    });

    test(
      'an injected factory instance dies with the requesting controller',
      () {
        final context = ModuleScope(
          module: TestModule(
            view: const SizedBox.shrink(),
            controllers: [
              Provider<HostController>.factory(create: HostController.new),
              Provider<TrackedController>.factory(
                create: TrackedController.new,
              ),
            ],
          ),
        )..initialize();

        final host = context.getController<HostController>();
        expect(TrackedController.created, 1);
        expect(TrackedController.disposed, 0);

        expect(context.release(host), isTrue);
        expect(TrackedController.disposed, 1);

        context.dispose();
        expect(TrackedController.disposed, 1);
      },
    );

    test('release disposes a factory instance early, singletons never', () {
      final context = ModuleScope(
        module: TestModule(
          view: const SizedBox.shrink(),
          controllers: [
            Provider<TrackedController>.factory(create: TrackedController.new),
          ],
          services: [
            Provider<CountingService>.singleton(create: CountingService.new),
          ],
        ),
      )..initialize();

      final first = context.getController<TrackedController>();
      final service = context.getService<CountingService>();

      expect(context.release(first), isTrue);
      expect(TrackedController.disposed, 1);
      expect(context.release(first), isFalse);

      expect(context.release(service), isFalse);
      expect(identical(context.getService<CountingService>(), service), isTrue);

      context.dispose();
      expect(TrackedController.disposed, 1);
    });

    test('a factory resolved straight from a context lives until teardown', () {
      final context = ModuleScope(
        module: TestModule(
          view: const SizedBox.shrink(),
          controllers: [
            Provider<TrackedController>.factory(create: TrackedController.new),
          ],
        ),
      )..initialize();

      for (var i = 0; i < 5; i++) {
        context.getController<TrackedController>();
      }
      expect(TrackedController.disposed, 0);

      context.dispose();
      expect(TrackedController.disposed, 5);
    });
  });

  group('5b. provider overrides', () {
    testWidgets('an override replaces the declared provider', (tester) async {
      late CountingService resolved;
      final replacement = CountingService();
      final module = TestModule(
        view: ServiceProbe(onResolved: (service) => resolved = service),
        services: [
          Provider<CountingService>.singleton(create: CountingService.new),
        ],
      );

      await tester.pumpWidget(
        ModuleWidget(
          module: module,
          overrides: [
            Provider<CountingService>.singleton(create: () => replacement),
          ],
        ),
      );

      expect(identical(resolved, replacement), isTrue);
      expect(CountingService.created, 1); // only the one built by the test
    });

    test('an override that matches nothing throws', () {
      expect(
        () => ModuleScope(
          module: TestModule(view: const SizedBox.shrink()),
          overrides: [
            Provider<CountingService>.singleton(create: CountingService.new),
          ],
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('does not match any provider'),
          ),
        ),
      );
    });

    test('an override has to match the provider name too', () {
      expect(
        () => ModuleScope(
          module: TestModule(
            view: const SizedBox.shrink(),
            services: [
              Provider<CountingService>.singleton(
                create: CountingService.new,
                name: 'real',
              ),
            ],
          ),
          overrides: [
            Provider<CountingService>.singleton(create: CountingService.new),
          ],
        ),
        throwsStateError,
      );
    });

    testWidgets('ChildModuleView takes overrides for the child module', (
      tester,
    ) async {
      final replacement = CountingService();
      CountingService? resolved;
      final child = ChildTestModule(
        view: ServiceProbe(onResolved: (service) => resolved = service),
        services: [
          Provider<CountingService>.singleton(create: CountingService.new),
        ],
      );

      await tester.pumpWidget(
        ModuleWidget(
          module: TestModule(
            view: ChildModuleView<ChildTestModule>(
              overrides: [
                Provider<CountingService>.singleton(create: () => replacement),
              ],
            ),
            children: [child],
          ),
        ),
      );

      expect(identical(resolved, replacement), isTrue);
    });
  });
}
