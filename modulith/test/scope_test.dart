import 'package:flutter/material.dart';
import 'package:modulith/modulith.dart';
import 'package:flutter_test/flutter_test.dart';

class TestModule extends Module {
  TestModule({
    required this.view,
    this.controllers = const [],
    this.services = const [],
    this.children = const [],
    this.name,
  });

  @override
  final Widget view;

  @override
  final List<Provider<Controller>> controllers;

  @override
  final List<Provider<Service>> services;

  @override
  final List<Module> children;

  @override
  final String? name;
}

class LeafModule extends TestModule {
  LeafModule({required super.view, super.name});
}

abstract class Repository extends Service {
  String get label;
}

class RealRepository extends Repository {
  @override
  String get label => 'real';
}

class DepService extends Service {
  final List<String> log = [];
}

class MainService extends Service {
  late final DepService dep;
  bool initialized = false;
  bool torn = false;

  @override
  void init() {
    dep = injectService<DepService>();
    initialized = true;
    addDisposeCallback(() => dep.log.add('callback'));
  }

  @override
  void dispose() {
    torn = true;
    dep.log.add('dispose');
    super.dispose();
  }
}

class PingService extends Service {
  @override
  void init() => injectService<PongService>();
}

class PongService extends Service {
  @override
  void init() => injectService<PingService>();
}

void main() {
  group('2.3 lookup', () {
    test('an exact-type provider wins over an earlier subtype one', () {
      final context = ModuleScope(
        module: TestModule(
          view: const SizedBox.shrink(),
          services: [
            Provider<RealRepository>.singleton(create: RealRepository.new),
            Provider<Repository>.singleton(create: RealRepository.new),
          ],
        ),
      )..initialize();

      // Registered under Repository, so that's what a Repository lookup gets.
      expect(context.getService<Repository>(), isA<RealRepository>());
      expect(
        identical(
          context.getService<Repository>(),
          context.getService<RealRepository>(),
        ),
        isFalse,
      );

      context.dispose();
    });

    test('a subtype provider still satisfies a supertype lookup', () {
      final context = ModuleScope(
        module: TestModule(
          view: const SizedBox.shrink(),
          services: [
            Provider<RealRepository>.singleton(create: RealRepository.new),
          ],
        ),
      )..initialize();

      expect(context.getService<Repository>().label, 'real');
      context.dispose();
    });

    test('repeated lookups keep returning the same singleton', () {
      final root = ModuleScope(
        module: TestModule(
          view: const SizedBox.shrink(),
          services: [Provider<DepService>.singleton(create: DepService.new)],
        ),
      )..initialize();

      var leaf = root;
      for (var i = 0; i < 20; i++) {
        leaf = ModuleScope(
          module: TestModule(view: const SizedBox.shrink()),
          parent: leaf,
        )..initialize();
      }

      final first = leaf.getService<DepService>();
      for (var i = 0; i < 100; i++) {
        expect(identical(leaf.getService<DepService>(), first), isTrue);
      }

      root.dispose();
    });
  });

  group('2.5 service lifecycle', () {
    test('a service is initialized, can inject, and is torn down', () {
      final dep = DepService();
      final context = ModuleScope(
        module: TestModule(
          view: const SizedBox.shrink(),
          services: [
            Provider<DepService>.singleton(create: () => dep),
            Provider<MainService>.singleton(
              create: MainService.new,
              dispose: (value) => value.dep.log.add('provider'),
            ),
          ],
        ),
      )..initialize();

      final service = context.getService<MainService>();
      expect(service.initialized, isTrue);
      expect(identical(service.dep, dep), isTrue);
      expect(service.isDisposed, isFalse);

      context.dispose();

      expect(service.torn, isTrue);
      expect(service.isDisposed, isTrue);
      // Service.dispose runs first, then its callbacks, then Provider.dispose.
      expect(dep.log, ['dispose', 'callback', 'provider']);
    });

    test('a circular dependency between services is caught', () {
      final context = ModuleScope(
        module: TestModule(
          view: const SizedBox.shrink(),
          services: [
            Provider<PingService>.singleton(create: PingService.new),
            Provider<PongService>.singleton(create: PongService.new),
          ],
        ),
      )..initialize();

      expect(
        () => context.getService<PingService>(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Circular dependency detected'),
          ),
        ),
      );
      context.dispose();
    });

    test('a missing dependency reports itself, not the failed rollback', () {
      final context = ModuleScope(
        module: TestModule(
          view: const SizedBox.shrink(),
          services: [Provider<MainService>.singleton(create: MainService.new)],
        ),
      )..initialize();

      // MainService injects DepService, which nothing declares. Its dispose
      // then trips over the `late` field init() never assigned — that must
      // not replace the real error.
      expect(
        () => context.getService<MainService>(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Service of type DepService not found'),
          ),
        ),
      );
      context.dispose();
    });
  });

  group('2.6 child modules', () {
    testWidgets('two children of the same type are told apart by name', (
      tester,
    ) async {
      final module = TestModule(
        view: const Column(
          children: [
            ChildModuleView<LeafModule>(name: 'left'),
            ChildModuleView<LeafModule>(name: 'right'),
          ],
        ),
        children: [
          LeafModule(
            name: 'left',
            view: const Text('left leaf', textDirection: TextDirection.ltr),
          ),
          LeafModule(
            name: 'right',
            view: const Text('right leaf', textDirection: TextDirection.ltr),
          ),
        ],
      );

      await tester.pumpWidget(ModuleWidget(module: module));

      expect(find.text('left leaf'), findsOneWidget);
      expect(find.text('right leaf'), findsOneWidget);
    });

    test('declaring two children with the same type and name throws', () {
      expect(
        () => ModuleScope(
          module: TestModule(
            view: const SizedBox.shrink(),
            children: [
              LeafModule(view: const SizedBox.shrink()),
              LeafModule(view: const SizedBox.shrink()),
            ],
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Duplicate child module'),
          ),
        ),
      );
    });

    testWidgets('asking for a child that is not declared fails clearly', (
      tester,
    ) async {
      await tester.pumpWidget(
        ModuleWidget(
          module: TestModule(view: const ChildModuleView<LeafModule>()),
        ),
      );

      expect(
        tester.takeException(),
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Child module of type LeafModule not found'),
        ),
      );
    });

    testWidgets('the same Module instance cannot back two live scopes', (
      tester,
    ) async {
      final shared = LeafModule(view: const SizedBox.shrink());

      await tester.pumpWidget(
        Column(
          children: [
            ModuleWidget(module: shared),
            ModuleWidget(module: shared),
          ],
        ),
      );

      expect(
        tester.takeException(),
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('already mounted somewhere else'),
        ),
      );
    });

    testWidgets('a Module instance can be mounted again after unmounting', (
      tester,
    ) async {
      final module = LeafModule(
        view: const Text('leaf', textDirection: TextDirection.ltr),
      );

      await tester.pumpWidget(ModuleWidget(module: module));
      expect(find.text('leaf'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(ModuleWidget(module: module));

      expect(find.text('leaf'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
