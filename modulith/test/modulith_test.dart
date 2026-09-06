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

class CounterController extends Controller {
  late final count = createSignal<int>(0);
}

class DisposableController extends Controller {
  int initCount = 0;
  int disposeCount = 0;

  @override
  void init() => initCount++;

  @override
  void dispose() {
    disposeCount++;
    super.dispose();
  }
}

class TestService extends Service {}

class InjectingController extends Controller {
  late final TestService service;
  late final CounterController parentController;

  @override
  void init() {
    service = injectService<TestService>();
    parentController = injectController<CounterController>();
  }
}

class FirstCircularController extends Controller {
  @override
  void init() => injectController<SecondCircularController>();
}

class SecondCircularController extends Controller {
  @override
  void init() => injectController<FirstCircularController>();
}

/// Keeps the [ModuleContext] handed to [ProbeView] around so a test can
/// resolve through it after the build.
class RefProbe {
  ModuleContext? _context;

  C getController<C extends Controller>({String? name}) =>
      _context!.getController<C>(name: name);

  S getService<S extends Service>({String? name}) =>
      _context!.getService<S>(name: name);
}

class ProbeView extends ModularWidget {
  const ProbeView({required this.probe, super.key});

  final RefProbe probe;

  @override
  Widget build(ModuleContext context) {
    probe._context = context;
    return const SizedBox.shrink();
  }
}

class ModularProbe extends ModularWidget {
  const ModularProbe({super.key});

  @override
  Widget build(ModuleContext context) {
    final controller = context.getController<CounterController>();
    return Text('${controller.count.value}', textDirection: TextDirection.ltr);
  }
}

class EchoProbe extends ModularWidget {
  const EchoProbe({required this.label, super.key});

  final String label;

  @override
  Widget build(ModuleContext context) =>
      Text(label, textDirection: TextDirection.ltr);
}

class LabelHost extends StatefulWidget {
  const LabelHost({super.key});

  @override
  State<LabelHost> createState() => LabelHostState();
}

class LabelHostState extends State<LabelHost> {
  String label = 'first';

  void setLabel(String value) => setState(() => label = value);

  @override
  Widget build(BuildContext context) => EchoProbe(label: label);
}

class LifecycleModule extends TestModule {
  LifecycleModule({required super.view, required super.controllers});

  int initCount = 0;
  int disposeCount = 0;

  @override
  void onInit(ModuleScope scope) => initCount++;

  @override
  void onDispose(ModuleScope scope) => disposeCount++;
}

class DisposeLookupModule extends TestModule {
  DisposeLookupModule({required super.view, required super.controllers});

  bool resolvedDuringDispose = false;

  @override
  void onDispose(ModuleScope scope) {
    scope.getController<DisposableController>();
    resolvedDuringDispose = true;
  }
}

class CountingDeclarationsModule extends Module {
  int controllerReads = 0;
  int serviceReads = 0;
  int childrenReads = 0;

  @override
  Widget get view => const SizedBox.shrink();

  @override
  List<Provider<Controller>> get controllers {
    controllerReads++;
    return [
      Provider<CounterController>.singleton(create: CounterController.new),
    ];
  }

  @override
  List<Provider<Service>> get services {
    serviceReads++;
    return [Provider<TestService>.singleton(create: TestService.new)];
  }

  @override
  List<Module> get children {
    childrenReads++;
    return const [];
  }
}

void main() {
  test('Signal notifies listeners on value change', () {
    final signal = Signal<int>(0);
    var notifications = 0;
    signal.addListener(() => notifications++);

    signal.value = 1;

    expect(signal.value, 1);
    expect(notifications, 1);
  });

  testWidgets('resolves a singleton controller from the current module', (
    tester,
  ) async {
    final probe = RefProbe();
    final module = TestModule(
      view: ProbeView(probe: probe),
      controllers: [
        Provider<CounterController>.singleton(create: CounterController.new),
      ],
    );

    await tester.pumpWidget(ModuleWidget(module: module));

    final first = probe.getController<CounterController>();
    final second = probe.getController<CounterController>();
    expect(identical(first, second), isTrue);
    expect(probe.getController<Controller>(), same(first));
  });

  testWidgets('walks up to an ancestor module', (tester) async {
    final probe = RefProbe();
    final child = ChildTestModule(view: ProbeView(probe: probe));
    final parentController = CounterController();
    final parent = TestModule(
      view: const ChildModuleView<ChildTestModule>(),
      controllers: [
        Provider<CounterController>.singleton(create: () => parentController),
      ],
      children: [child],
    );

    await tester.pumpWidget(ModuleWidget(module: parent));

    expect(probe.getController<CounterController>(), same(parentController));
  });

  testWidgets('ModularWidget resolves controllers through its context', (
    tester,
  ) async {
    final module = TestModule(
      view: const ModularProbe(),
      controllers: [
        Provider<CounterController>.singleton(create: CounterController.new),
      ],
    );

    await tester.pumpWidget(ModuleWidget(module: module));

    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('ModularWidget rebuilds when its parent passes new values', (
    tester,
  ) async {
    final key = GlobalKey<LabelHostState>();
    // The module and its context stay put: the only thing that changes is
    // the value the parent hands to the ModularWidget.
    await tester.pumpWidget(
      ModuleWidget(
        module: TestModule(view: LabelHost(key: key)),
      ),
    );
    expect(find.text('first'), findsOneWidget);

    key.currentState!.setLabel('second');
    await tester.pump();

    expect(find.text('second'), findsOneWidget);
  });

  testWidgets('provider name is part of the lookup key', (tester) async {
    final probe = RefProbe();
    final primary = CounterController();
    final secondary = CounterController();
    final module = TestModule(
      view: ProbeView(probe: probe),
      controllers: [
        Provider<CounterController>.singleton(
          name: 'primary',
          create: () => primary,
        ),
        Provider<CounterController>.singleton(
          name: 'secondary',
          create: () => secondary,
        ),
      ],
    );

    await tester.pumpWidget(ModuleWidget(module: module));

    expect(
      probe.getController<CounterController>(name: 'secondary'),
      same(secondary),
    );
    expect(() => probe.getController<CounterController>(), throwsStateError);
  });

  testWidgets(
    'controller injects local services and parent controllers in init',
    (tester) async {
      final parentController = CounterController();
      final service = TestService();
      final injecting = InjectingController();
      final child = ChildTestModule(
        view: const SizedBox.shrink(),
        controllers: [
          Provider<InjectingController>.singleton(create: () => injecting),
        ],
        services: [Provider<TestService>.singleton(create: () => service)],
      );
      final parent = TestModule(
        view: const ChildModuleView<ChildTestModule>(),
        controllers: [
          Provider<CounterController>.singleton(create: () => parentController),
        ],
        children: [child],
      );

      await tester.pumpWidget(ModuleWidget(module: parent));

      expect(injecting.service, same(service));
      expect(injecting.parentController, same(parentController));
    },
  );

  testWidgets('factory initializes and disposes every controller instance', (
    tester,
  ) async {
    final probe = RefProbe();
    final created = <DisposableController>[];
    final module = TestModule(
      view: ProbeView(probe: probe),
      controllers: [
        Provider<DisposableController>.factory(
          create: () {
            final controller = DisposableController();
            created.add(controller);
            return controller;
          },
        ),
      ],
    );

    await tester.pumpWidget(ModuleWidget(module: module));
    final first = probe.getController<DisposableController>();
    final second = probe.getController<DisposableController>();

    expect(identical(first, second), isFalse);
    expect(created.map((item) => item.initCount), everyElement(1));

    await tester.pumpWidget(const SizedBox.shrink());
    expect(created.map((item) => item.disposeCount), everyElement(1));
  });

  testWidgets('controller lifecycle surrounds module lifecycle', (
    tester,
  ) async {
    final controller = DisposableController();
    final module = LifecycleModule(
      view: const SizedBox.shrink(),
      controllers: [
        Provider<DisposableController>.singleton(create: () => controller),
      ],
    );

    await tester.pumpWidget(ModuleWidget(module: module));
    expect(controller.initCount, 1);
    expect(module.initCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(module.disposeCount, 1);
    expect(controller.disposeCount, 1);
  });

  testWidgets('replacing ModuleWidget.module replaces its ModuleScope', (
    tester,
  ) async {
    final firstController = DisposableController();
    final secondController = DisposableController();
    final first = LifecycleModule(
      view: const SizedBox.shrink(),
      controllers: [
        Provider<DisposableController>.singleton(create: () => firstController),
      ],
    );
    final second = LifecycleModule(
      view: const SizedBox.shrink(),
      controllers: [
        Provider<DisposableController>.singleton(
          create: () => secondController,
        ),
      ],
    );

    await tester.pumpWidget(ModuleWidget(module: first));
    await tester.pumpWidget(ModuleWidget(module: second));

    expect(first.disposeCount, 1);
    expect(firstController.disposeCount, 1);
    expect(second.initCount, 1);
    expect(secondController.initCount, 1);
  });

  testWidgets('module declaration getters are captured once per mount', (
    tester,
  ) async {
    final module = CountingDeclarationsModule();

    await tester.pumpWidget(ModuleWidget(module: module));
    await tester.pump();

    expect(module.controllerReads, 1);
    expect(module.serviceReads, 1);
    expect(module.childrenReads, 1);
  });

  test('duplicate provider keys fail when the context is created', () {
    final module = TestModule(
      view: const SizedBox.shrink(),
      controllers: [
        Provider<CounterController>.singleton(create: CounterController.new),
        Provider<CounterController>.factory(create: CounterController.new),
      ],
    );

    expect(() => ModuleScope(module: module), throwsStateError);
  });

  test('injecting before a controller is attached fails clearly', () {
    final controller = InjectingController();

    expect(controller.init, throwsStateError);
  });

  test('circular controller injection fails with a StateError', () {
    final module = TestModule(
      view: const SizedBox.shrink(),
      controllers: [
        Provider<FirstCircularController>.singleton(
          create: FirstCircularController.new,
        ),
        Provider<SecondCircularController>.singleton(
          create: SecondCircularController.new,
        ),
      ],
    );
    final context = ModuleScope(module: module);

    expect(context.initialize, throwsStateError);
  });

  test('provider disposer runs for a created service', () {
    var disposeCount = 0;
    final module = TestModule(
      view: const SizedBox.shrink(),
      services: [
        Provider<TestService>.singleton(
          create: TestService.new,
          dispose: (_) => disposeCount++,
        ),
      ],
    );
    final context = ModuleScope(module: module)..initialize();

    context.getService<TestService>();
    context.dispose();

    expect(disposeCount, 1);
  });

  testWidgets('Module.onDispose can resolve instances before teardown', (
    tester,
  ) async {
    final module = DisposeLookupModule(
      view: const SizedBox.shrink(),
      controllers: [
        Provider<DisposableController>.singleton(
          create: DisposableController.new,
        ),
      ],
    );

    await tester.pumpWidget(ModuleWidget(module: module));
    await tester.pumpWidget(const SizedBox.shrink());

    expect(module.resolvedDuringDispose, isTrue);
  });
}
