import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modulith/modulith.dart';
import 'package:modulith_router/modulith_router.dart';

/// Collects everything the router reports, so a test can assert on the
/// sequence instead of on the router's state after the fact.
class RecordingObserver extends RouterObserver {
  RecordingObserver();

  final List<RouterEvent> events = [];

  @override
  void onEvent(RouterEvent event) => events.add(event);

  Iterable<T> of<T extends RouterEvent>() => events.whereType<T>();

  T single<T extends RouterEvent>() => of<T>().single;

  void clear() => events.clear();
}

class Blocking extends RouteGuard {
  const Blocking();

  @override
  GuardResult canActivate(GuardContext context) => GuardResult.block;
}

class Allowing extends RouteGuard {
  const Allowing();

  @override
  GuardResult canActivate(GuardContext context) => GuardResult.allow;
}

class SendsToLogin extends RouteGuard {
  const SendsToLogin();

  @override
  GuardResult canActivate(GuardContext context) =>
      const GuardResult.redirect('/login');
}

/// Holds a navigation inside its guard until [gate] is completed, so a test
/// can start a second navigation while the first is still deciding.
class Gated extends RouteGuard {
  Gated(this.gate);

  final Completer<void> gate;

  @override
  Future<GuardResult> canActivate(GuardContext context) async {
    await gate.future;
    return GuardResult.allow;
  }
}

class Throwing extends RouterObserver {
  const Throwing();

  @override
  void onEvent(RouterEvent event) => throw StateError('observer is broken');
}

ViewRoute page(
  String path,
  String label, {
  List<RouteGuard> guards = const [],
  List<RouteDefinition> children = const [],
  ChildRouting childRouting = ChildRouting.stack,
  List<RouteBranch> branches = const [],
}) => ViewRoute(
  path: path,
  guards: guards,
  children: children,
  childRouting: childRouting,
  builder: (context, route) => Scaffold(
    body: Column(
      children: [
        Text('screen:$label'),
        if (childRouting != ChildRouting.stack)
          const Expanded(child: RoutingView()),
      ],
    ),
  ),
);

/// A branch host has to be a `ModuleRoute`, so this one mounts an empty
/// module whose only job is to render the outlet.
class ShellModule extends Module {
  @override
  Widget get view => const ShellView();
}

class ShellView extends ModularWidget {
  const ShellView({super.key});

  @override
  Widget build(ModuleContext context) => const Scaffold(body: RoutingView());
}

Future<(RouterService, RecordingObserver)> pumpRouter(
  WidgetTester tester,
  List<RouteDefinition> routes, {
  String initialLocation = '/',
  List<RouteGuard> guards = const [],
  List<RouterObserver> extra = const [],
}) async {
  final observer = RecordingObserver();
  await tester.pumpWidget(
    ModuleWidget(
      module: RouterModule(
        routes: routes,
        initialLocation: initialLocation,
        guards: guards,
        observers: [observer, ...extra],
        appBuilder: (context, routerConfig) =>
            MaterialApp.router(routerConfig: routerConfig),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final router = tester.element(find.byType(RoutingView).first).router;
  return (router, observer);
}

void main() {
  group('navigation events', () {
    testWidgets('reports the initial navigation as coming from the '
        'platform', (tester) async {
      final (_, observer) = await pumpRouter(tester, [page('/', 'home')]);

      final started = observer.single<NavigationStarted>();
      expect(started.kind, NavigationKind.platform);
      expect(started.to, Uri.parse('/'));
      expect(
        observer.single<NavigationEnded>().outcome,
        NavigationOutcome.completed,
      );
    });

    testWidgets('reports a go as started, matched, ended and published', (
      tester,
    ) async {
      final (router, observer) = await pumpRouter(tester, [
        page('/', 'home'),
        page('about', 'about'),
      ]);
      observer.clear();

      await router.go('/about', extra: 'payload');
      await tester.pumpAndSettle();

      expect(observer.events.map((event) => event.runtimeType), [
        NavigationStarted,
        RouteMatched,
        StackChanged,
        NavigationEnded,
      ]);

      final started = observer.single<NavigationStarted>();
      expect(started.kind, NavigationKind.go);
      expect(started.from, Uri.parse('/'));
      expect(started.to, Uri.parse('/about'));
      expect(started.extra, 'payload');

      final matched = observer.single<RouteMatched>();
      expect(matched.isMatch, isTrue);
      expect(matched.matches!.last.route.debugPath, '/about');

      final changed = observer.single<StackChanged>();
      expect(changed.uri, Uri.parse('/about'));
      expect(changed.revision, router.revision);

      final ended = observer.single<NavigationEnded>();
      expect(ended.outcome, NavigationOutcome.completed);
      expect(ended.uri, Uri.parse('/about'));
    });

    testWidgets('ties every event of one navigation to one id', (tester) async {
      final (router, observer) = await pumpRouter(tester, [
        page('/', 'home'),
        page('about', 'about'),
      ]);
      observer.clear();

      await router.go('/about');
      await tester.pumpAndSettle();

      final ids = {
        for (final event in observer.events)
          switch (event) {
            NavigationEvent(:final navigationId) => navigationId,
            StackChanged(:final navigationId) => navigationId,
          },
      };
      expect(ids, hasLength(1));
      expect(ids.single, isNotNull);
    });

    testWidgets('names the call each navigation came from', (tester) async {
      final (router, observer) = await pumpRouter(tester, [
        page('/', 'home'),
        page('about', 'about'),
      ]);
      observer.clear();

      unawaited(router.push<void>('/about'));
      await tester.pumpAndSettle();
      await router.replace('/');
      await tester.pumpAndSettle();
      await router.applyPlatformState(RouterState.single(Uri.parse('/about')));
      await tester.pumpAndSettle();

      expect(observer.of<NavigationStarted>().map((event) => event.kind), [
        NavigationKind.push,
        NavigationKind.replace,
        NavigationKind.platform,
      ]);
    });

    testWidgets('reports a stack change no navigation asked for', (
      tester,
    ) async {
      final (router, observer) = await pumpRouter(tester, [
        page('users', 'users', children: [page(':id', 'user')]),
      ], initialLocation: '/users/42');
      observer.clear();

      await router.pop();
      await tester.pumpAndSettle();

      final changed = observer.single<StackChanged>();
      expect(
        changed.navigationId,
        isNull,
        reason: 'A Navigator removed the page; no navigation call did.',
      );
      expect(changed.uri, Uri.parse('/users'));
      expect(observer.of<NavigationStarted>(), isEmpty);
    });
  });

  group('guards', () {
    testWidgets('reports each guard with the route it is declared on', (
      tester,
    ) async {
      final (router, observer) = await pumpRouter(
        tester,
        [
          page(
            'admin',
            'admin',
            guards: const [Allowing()],
            children: [
              page('users', 'users', guards: const [Allowing()]),
            ],
          ),
          page('/', 'home'),
        ],
        guards: const [Allowing()],
      );
      observer.clear();

      await router.go('/admin/users');
      await tester.pumpAndSettle();

      expect(
        observer.of<GuardEvaluated>().map(
          (event) => (event.guardType, event.routePath, event.isGlobal),
        ),
        [
          (Allowing, null, true),
          (Allowing, '/admin', false),
          (Allowing, '/admin/users', false),
        ],
        reason: 'Global guards first, then route guards root to leaf.',
      );
      expect(
        observer.of<GuardEvaluated>().every(
          (event) => event.result is AllowGuardResult,
        ),
        isTrue,
      );
    });

    testWidgets('reports a blocked navigation and publishes nothing', (
      tester,
    ) async {
      final (router, observer) = await pumpRouter(tester, [
        page('/', 'home'),
        page('admin', 'admin', guards: const [Blocking()]),
      ]);
      observer.clear();

      await router.go('/admin');
      await tester.pumpAndSettle();

      expect(observer.single<GuardEvaluated>().result, isA<BlockGuardResult>());
      expect(
        observer.single<NavigationEnded>().outcome,
        NavigationOutcome.blocked,
      );
      expect(observer.of<StackChanged>(), isEmpty);
    });

    testWidgets('reports a guard redirect as one navigation ending '
        'redirected', (tester) async {
      final (router, observer) = await pumpRouter(tester, [
        page('/', 'home'),
        page('login', 'login'),
        page('admin', 'admin', guards: const [SendsToLogin()]),
      ]);
      observer.clear();

      await router.go('/admin');
      await tester.pumpAndSettle();

      final redirect = observer.single<RedirectApplied>();
      expect(redirect.source, RedirectSource.guard);
      expect(redirect.from, Uri.parse('/admin'));
      expect(redirect.to, Uri.parse('/login'));

      expect(
        observer.of<RouteMatched>().map((event) => event.uri),
        [Uri.parse('/admin'), Uri.parse('/login')],
        reason: 'The target is matched again after the redirect.',
      );

      final ended = observer.single<NavigationEnded>();
      expect(ended.outcome, NavigationOutcome.redirected);
      expect(ended.uri, Uri.parse('/login'));
    });

    testWidgets('reports a RedirectRoute hop', (tester) async {
      final (router, observer) = await pumpRouter(tester, [
        page('/', 'home'),
        page('users', 'users'),
        const RedirectRoute(path: 'u', to: '/users'),
      ]);
      observer.clear();

      await router.go('/u');
      await tester.pumpAndSettle();

      final redirect = observer.single<RedirectApplied>();
      expect(redirect.source, RedirectSource.route);
      expect(redirect.from, Uri.parse('/u'));
      expect(redirect.to, Uri.parse('/users'));
      expect(observer.of<GuardEvaluated>(), isEmpty);
    });

    testWidgets('reports a deactivation guard refusing to leave', (
      tester,
    ) async {
      final (router, observer) = await pumpRouter(tester, [
        page('/', 'home'),
        page('about', 'about'),
      ]);
      router.registerDeactivationGuard(() => false);
      observer.clear();

      await router.go('/about');
      await tester.pumpAndSettle();

      expect(observer.single<DeactivationBlocked>().uri, Uri.parse('/about'));
      expect(
        observer.single<NavigationEnded>().outcome,
        NavigationOutcome.blocked,
      );
      expect(
        observer.of<GuardEvaluated>(),
        isEmpty,
        reason: 'Deactivation is asked before any route guard runs.',
      );
    });

    testWidgets('reports the navigation an async guard let be overtaken', (
      tester,
    ) async {
      final gate = Completer<void>();
      final (router, observer) = await pumpRouter(tester, [
        page('/', 'home'),
        page('about', 'about'),
        page('slow', 'slow', guards: [Gated(gate)]),
      ]);
      observer.clear();

      final slow = router.go('/slow');
      await tester.pump();
      final fast = await router.go('/about');
      gate.complete();

      expect(fast.outcome, NavigationOutcome.completed);
      expect((await slow).outcome, NavigationOutcome.superseded);
      await tester.pumpAndSettle();

      final ends = observer.of<NavigationEnded>().toList();
      expect(
        ends.map((event) => event.outcome),
        [NavigationOutcome.completed, NavigationOutcome.superseded],
        reason:
            'Navigations end in the order they resolve, not in call '
            'order.',
      );
      expect(
        ends.first.navigationId,
        greaterThan(ends.last.navigationId),
        reason: 'Ids are handed out in call order.',
      );
    });
  });

  group('matching', () {
    testWidgets('reports a URL nothing matched', (tester) async {
      final (router, observer) = await pumpRouter(tester, [page('/', 'home')]);
      observer.clear();

      await router.go('/nope');
      await tester.pumpAndSettle();

      final matched = observer.single<RouteMatched>();
      expect(matched.isMatch, isFalse);
      expect(matched.uri, Uri.parse('/nope'));
      expect(
        observer.single<NavigationEnded>().outcome,
        NavigationOutcome.completed,
        reason: 'The error page is where the router meant to end up.',
      );
    });
  });

  group('branches', () {
    List<RouteDefinition> branchRoutes() => [
      ModuleRoute(
        path: '/',
        builder: (route) => ShellModule(),
        childRouting: ChildRouting.branches,
        branches: [
          RouteBranch(
            name: 'todos',
            initialLocation: '/todos',
            routes: [page('/todos', 'todos')],
          ),
          RouteBranch(
            name: 'settings',
            initialLocation: '/settings',
            routes: [page('/settings', 'settings')],
          ),
        ],
      ),
    ];

    testWidgets('reports switching a branch as a navigation of its own', (
      tester,
    ) async {
      final (router, observer) = await pumpRouter(
        tester,
        branchRoutes(),
        initialLocation: '/todos',
      );
      observer.clear();

      await router.switchBranch('settings');
      await tester.pumpAndSettle();

      final started = observer.single<NavigationStarted>();
      expect(started.kind, NavigationKind.switchBranch);
      expect(started.from, Uri.parse('/todos'));
      expect(started.to, Uri.parse('/settings'));

      final ended = observer.single<NavigationEnded>();
      expect(ended.outcome, NavigationOutcome.completed);
      expect(ended.uri, Uri.parse('/settings'));
      expect(
        observer.single<StackChanged>().navigationId,
        started.navigationId,
      );
    });

    testWidgets('reports switching back to a retained branch without '
        'matching again', (tester) async {
      final (router, observer) = await pumpRouter(
        tester,
        branchRoutes(),
        initialLocation: '/todos',
      );
      await router.switchBranch('settings');
      await tester.pumpAndSettle();
      observer.clear();

      await router.switchBranch('todos');
      await tester.pumpAndSettle();

      expect(observer.single<NavigationStarted>().to, Uri.parse('/todos'));
      expect(
        observer.of<RouteMatched>(),
        isEmpty,
        reason: 'The retained history already knows what it matched.',
      );
      expect(observer.single<NavigationEnded>().uri, Uri.parse('/todos'));
    });

    testWidgets('reports switching to the branch already active as a '
        'completed no-op', (tester) async {
      final (router, observer) = await pumpRouter(
        tester,
        branchRoutes(),
        initialLocation: '/todos',
      );
      observer.clear();

      await router.switchBranch('todos');
      await tester.pumpAndSettle();

      expect(
        observer.single<NavigationEnded>().outcome,
        NavigationOutcome.completed,
      );
      expect(observer.of<StackChanged>(), isEmpty);
    });
  });

  group('observer contract', () {
    testWidgets('an observer that throws is reported and the navigation '
        'carries on', (tester) async {
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);

      final (router, observer) = await pumpRouter(
        tester,
        [page('/', 'home'), page('about', 'about')],
        extra: const [Throwing()],
      );
      observer.clear();
      errors.clear();

      await router.go('/about');
      await tester.pumpAndSettle();

      expect(router.currentUri, Uri.parse('/about'));
      expect(find.text('screen:about'), findsOneWidget);
      expect(errors, isNotEmpty);
      expect(errors.first.library, 'modulith_router');
      expect(
        observer.of<NavigationEnded>(),
        hasLength(1),
        reason: 'The observer after the broken one still gets its events.',
      );
    });
  });
}
