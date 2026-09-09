import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modulith/modulith.dart';

// ---------------------------------------------------------------------------
// Members
// ---------------------------------------------------------------------------

class NavigationService extends Service {
  static int created = 0;

  NavigationService() {
    created++;
  }

  final List<String> visited = [];
  bool torn = false;

  void go(String location) => visited.add(location);

  @override
  void dispose() {
    torn = true;
    super.dispose();
  }
}

class PrivateService extends Service {}

class NavigationController extends Controller {
  late final NavigationService navigation;

  @override
  void init() => navigation = injectService<NavigationService>();
}

/// Lives in the parent module, but depends on a service the child declares.
class ShellController extends Controller {
  late final NavigationService navigation;

  @override
  void init() => navigation = injectService<NavigationService>();
}

class FakeNavigationService extends NavigationService {}

// ---------------------------------------------------------------------------
// Modules
// ---------------------------------------------------------------------------

class RouterLikeModule extends Module {
  RouterLikeModule({this.alsoDeclarePrivate = false, this.children = const []});

  final bool alsoDeclarePrivate;

  @override
  final List<Module> children;

  @override
  List<Provider<Service>> get services => [
    Provider<NavigationService>.singleton(
      create: NavigationService.new,
      exported: true,
    ),
    if (alsoDeclarePrivate)
      Provider<PrivateService>.singleton(create: PrivateService.new),
  ];

  @override
  List<Provider<Controller>> get controllers => [
    Provider<NavigationController>.singleton(
      create: NavigationController.new,
      exported: true,
    ),
  ];

  @override
  Widget get view => const _Probe();
}

class ShellModule extends Module {
  ShellModule({required this.children});

  @override
  final List<Module> children;

  @override
  List<Provider<Controller>> get controllers => [
    Provider<ShellController>.singleton(create: ShellController.new),
  ];

  @override
  Widget get view => const ChildModuleView<RouterLikeModule>();
}

/// A module with no children of its own, sitting between the exporter and
/// the scope that ends up owning the export.
class MiddleModule extends Module {
  MiddleModule({required this.children});

  @override
  final List<Module> children;

  @override
  Widget get view => const ChildModuleView<RouterLikeModule>();
}

class _Probe extends ModularWidget {
  const _Probe();

  @override
  Widget build(ModuleContext context) {
    return Text(
      context.getService<NavigationService>().visited.join(','),
      textDirection: TextDirection.ltr,
    );
  }
}

void main() {
  setUp(() => NavigationService.created = 0);

  group('exported providers', () {
    test('a parent resolves a service its child exports', () {
      final scope = ModuleScope(
        module: ShellModule(children: [RouterLikeModule()]),
      )..initialize();

      final controller = scope.getController<ShellController>();
      controller.navigation.go('/home');
      expect(controller.navigation.visited, ['/home']);

      scope.dispose();
    });

    test('the export is created before the child module ever mounts', () {
      final scope = ModuleScope(
        module: ShellModule(children: [RouterLikeModule()]),
      )..initialize();

      // ShellController is a singleton, so it was built during initialize(),
      // long before a ChildModuleView could mount RouterLikeModule.
      expect(NavigationService.created, 1);
      scope.dispose();
    });

    test('parent and child share one instance', () {
      final parentModule = ShellModule(children: [RouterLikeModule()]);
      final parent = ModuleScope(module: parentModule)..initialize();
      final child = ModuleScope(
        module: parent.childModule<RouterLikeModule>(),
        parent: parent,
      )..initialize();

      expect(NavigationService.created, 1);
      expect(
        identical(
          parent.getController<ShellController>().navigation,
          child.getService<NavigationService>(),
        ),
        isTrue,
      );

      child.dispose();
      parent.dispose();
    });

    test('the instance outlives the mount of the module declaring it', () {
      final parent = ModuleScope(
        module: ShellModule(children: [RouterLikeModule()]),
      )..initialize();
      final navigation = parent.getController<ShellController>().navigation;

      final child = ModuleScope(
        module: parent.childModule<RouterLikeModule>(),
        parent: parent,
      )..initialize();
      child.dispose();

      expect(navigation.torn, isFalse);
      expect(
        identical(parent.getService<NavigationService>(), navigation),
        isTrue,
      );

      parent.dispose();
      expect(navigation.torn, isTrue);
    });

    test('an exported singleton controller is eager in the owning scope', () {
      final scope = ModuleScope(
        module: ShellModule(children: [RouterLikeModule()]),
      )..initialize();

      final controller = scope.getController<NavigationController>();
      expect(controller.navigation, isNotNull);
      scope.dispose();
    });

    test('a provider that is not exported stays private to its module', () {
      final parent = ModuleScope(
        module: ShellModule(
          children: [RouterLikeModule(alsoDeclarePrivate: true)],
        ),
      )..initialize();

      expect(() => parent.getService<PrivateService>(), throwsStateError);

      final child = ModuleScope(
        module: parent.childModule<RouterLikeModule>(),
        parent: parent,
      )..initialize();
      expect(child.getService<PrivateService>(), isA<PrivateService>());

      child.dispose();
      parent.dispose();
    });

    test('an export travels past a module that does not claim it', () {
      final root = ModuleScope(
        module: ShellModule(
          children: [
            MiddleModule(children: [RouterLikeModule()]),
          ],
        ),
      );
      root.initialize();

      // The root owns it, so ShellController — which resolves it in init() —
      // was able to find it.
      expect(root.getController<ShellController>().navigation, isNotNull);
      expect(NavigationService.created, 1);

      final middle = ModuleScope(
        module: root.childModule<MiddleModule>(),
        parent: root,
      )..initialize();
      final leaf = ModuleScope(
        module: middle.childModule<RouterLikeModule>(),
        parent: middle,
      )..initialize();

      expect(NavigationService.created, 1);
      expect(
        identical(
          leaf.getService<NavigationService>(),
          root.getController<ShellController>().navigation,
        ),
        isTrue,
      );

      leaf.dispose();
      middle.dispose();
      root.dispose();
    });

    test('an export colliding with the parent own registration throws', () {
      expect(
        () => ModuleScope(
          module: _CollidingModule(children: [RouterLikeModule()]),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('Duplicate service provider'),
              contains('RouterLikeModule exports it'),
            ),
          ),
        ),
      );
    });

    test('two siblings exporting the same type throw', () {
      expect(
        () => ModuleScope(
          module: ShellModule(
            children: [RouterLikeModule(), _SecondExporter()],
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('a not-found lookup points at exports', () {
      final scope = ModuleScope(
        module: ShellModule(
          children: [RouterLikeModule(alsoDeclarePrivate: true)],
        ),
      )..initialize();

      expect(
        () => scope.getService<PrivateService>(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('exported: true'),
          ),
        ),
      );
      scope.dispose();
    });
  });

  group('overriding an exported provider', () {
    test('the owning scope hands the override to the declaring module', () {
      final parent = ModuleScope(
        module: ShellModule(children: [RouterLikeModule()]),
        overrides: [
          Provider<NavigationService>.singleton(
            create: FakeNavigationService.new,
            exported: true,
          ),
        ],
      )..initialize();

      final child = ModuleScope(
        module: parent.childModule<RouterLikeModule>(),
        parent: parent,
      )..initialize();

      expect(
        child.getService<NavigationService>(),
        isA<FakeNavigationService>(),
      );
      expect(
        parent.getController<ShellController>().navigation,
        isA<FakeNavigationService>(),
      );

      child.dispose();
      parent.dispose();
    });

    test('overriding it on the declaring module fails clearly', () {
      final parent = ModuleScope(
        module: ShellModule(children: [RouterLikeModule()]),
      )..initialize();

      expect(
        () => ModuleScope(
          module: parent.childModule<RouterLikeModule>(),
          parent: parent,
          overrides: [
            Provider<NavigationService>.singleton(
              create: FakeNavigationService.new,
              exported: true,
            ),
          ],
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('an ancestor module owns it'),
          ),
        ),
      );

      parent.dispose();
    });
  });

  group('through the widget tree', () {
    testWidgets('a child view resolves the hoisted instance', (tester) async {
      await tester.pumpWidget(
        ModuleWidget(module: ShellModule(children: [RouterLikeModule()])),
      );

      expect(NavigationService.created, 1);
      expect(find.text(''), findsOneWidget);
    });
  });
}

class _CollidingModule extends Module {
  _CollidingModule({required this.children});

  @override
  final List<Module> children;

  @override
  List<Provider<Service>> get services => [
    Provider<NavigationService>.singleton(create: NavigationService.new),
  ];

  @override
  Widget get view => const SizedBox.shrink();
}

class _SecondExporter extends Module {
  @override
  List<Provider<Service>> get services => [
    Provider<NavigationService>.singleton(
      create: NavigationService.new,
      exported: true,
    ),
  ];

  @override
  Widget get view => const SizedBox.shrink();
}
