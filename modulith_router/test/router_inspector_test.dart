import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modulith/modulith.dart';
import 'package:modulith_router/modulith_router.dart';
import 'package:modulith_router/src/devtools/inspector_serialization.dart';
import 'package:modulith_router/src/devtools/router_inspector.dart';

class SignedIn extends RouteGuard {
  const SignedIn();

  @override
  GuardResult canActivate(GuardContext context) => GuardResult.allow;
}

/// An `extra` of a type the router knows nothing about, to prove it is
/// described rather than serialized.
class TodoArgs {
  const TodoArgs(this.id);

  final int id;
}

/// A value that refuses to describe itself, to prove the inspector does not
/// hand application code a way to break DevTools.
class Hostile {
  @override
  String toString() => throw StateError('no');
}

ViewRoute page(
  String path,
  String label, {
  String? name,
  List<RouteGuard> guards = const [],
  List<RouteDefinition> children = const [],
  ChildRouting childRouting = ChildRouting.stack,
  RouteReuse reuse = RouteReuse.byPathParams,
}) => ViewRoute(
  path: path,
  name: name,
  guards: guards,
  children: children,
  childRouting: childRouting,
  reuse: reuse,
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

class ShellModule extends Module {
  @override
  Widget get view => const ShellView();
}

class ShellView extends ModularWidget {
  const ShellView({super.key});

  @override
  Widget build(ModuleContext context) => const Scaffold(body: RoutingView());
}

Future<RouterService> pumpRouter(
  WidgetTester tester,
  List<RouteDefinition> routes, {
  String initialLocation = '/',
  List<RouteGuard> guards = const [],
}) async {
  await tester.pumpWidget(
    ModuleWidget(
      module: RouterModule(
        routes: routes,
        initialLocation: initialLocation,
        guards: guards,
        appBuilder: (context, routerConfig) =>
            MaterialApp.router(routerConfig: routerConfig),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.element(find.byType(RoutingView).first).router;
}

/// Calls a service extension the way the VM service would, and decodes what
/// comes back.
Future<Map<String, Object?>> call(
  String name, [
  Map<String, String> parameters = const {},
]) async {
  final response = await RouterInspector.invoke(name, parameters);
  expect(
    response.isError(),
    isFalse,
    reason: 'ext.modulith_router.$name failed: ${response.errorDetail}',
  );
  return jsonDecode(response.result!) as Map<String, Object?>;
}

Future<Map<String, Object?>> callOn(
  RouterService router,
  String name, [
  Map<String, String> parameters = const {},
]) => call(name, {
  'routerId': '${RouterInspector.of(router)!.id}',
  ...parameters,
});

List<Object?> listOf(Map<String, Object?> json, String key) =>
    json[key]! as List<Object?>;

Map<String, Object?> mapOf(Object? value) => value! as Map<String, Object?>;

void main() {
  // A widget test does not unmount its tree when it ends, so the router of
  // the previous test is never disposed and would still be attached. The
  // real detach path is covered below, by unmounting on purpose.
  setUp(RouterInspector.instances.clear);

  group('attaching', () {
    testWidgets('a debug router registers itself and lets go on dispose', (
      tester,
    ) async {
      final router = await pumpRouter(tester, [page('/', 'home')]);

      final inspector = RouterInspector.of(router);
      expect(inspector, isNotNull);
      expect(RouterInspector.instances[inspector!.id], same(inspector));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      expect(
        RouterInspector.instances,
        isEmpty,
        reason: 'A disposed router must not stay in the router picker.',
      );
    });

    testWidgets('lists every mounted router', (tester) async {
      final router = await pumpRouter(tester, [page('/', 'home')]);

      final routers = listOf(await call('listRouters'), 'routers');
      expect(routers, hasLength(1));
      expect(mapOf(routers.single)['id'], RouterInspector.of(router)!.id);
      expect(mapOf(routers.single)['currentUri'], '/');
      expect(mapOf(routers.single)['routeCount'], 1);
    });

    testWidgets('answers without a routerId when there is only one router', (
      tester,
    ) async {
      await pumpRouter(tester, [page('/', 'home')]);

      expect((await call('getState'))['currentUri'], '/');
    });
  });

  group('getState', () {
    testWidgets('reports where the router is', (tester) async {
      final router = await pumpRouter(tester, [
        page('users', 'users', children: [page(':id', 'user', name: 'user')]),
      ], initialLocation: '/users');

      await router.go('/users/42');
      await tester.pumpAndSettle();

      final state = await callOn(router, 'getState');
      expect(state['currentUri'], '/users/42');
      expect(state['activeRouteName'], 'user');
      expect(state['canPop'], isTrue);
      expect(state['isNavigating'], isFalse);
      expect(state['revision'], router.revision);
      expect(state['frameCount'], 1);
    });
  });

  group('getRouteTable', () {
    testWidgets('describes the compiled table as a tree', (tester) async {
      final router = await pumpRouter(
        tester,
        [
          page('/', 'home'),
          page(
            'users',
            'users',
            children: [
              page(
                ':id',
                'user',
                name: 'user',
                guards: const [SignedIn()],
                reuse: RouteReuse.always,
              ),
            ],
          ),
          const RedirectRoute(path: 'u', to: '/users'),
        ],
        guards: const [SignedIn()],
      );

      final table = await callOn(router, 'getRouteTable');
      expect(table['globalGuards'], ['SignedIn']);

      final routes = listOf(table, 'routes').map(mapOf).toList();
      final users = routes.firstWhere((route) => route['path'] == 'users');
      expect(users['kind'], 'view');
      expect(users['childRouting'], 'stack');

      final user = mapOf(listOf(users, 'children').single);
      expect(user['debugPath'], '/users/:id');
      expect(user['pattern'], ':id');
      expect(user['name'], 'user');
      expect(user['params'], ['id']);
      expect(user['guards'], ['SignedIn']);
      expect(user['reuse'], 'always');

      final redirect = routes.firstWhere((route) => route['path'] == 'u');
      expect(redirect['kind'], 'redirect');
      expect(redirect['redirectTo'], '/users');
      expect(redirect['isComputedRedirect'], isFalse);
    });

    testWidgets('says a redirect target is computed per navigation', (
      tester,
    ) async {
      final router = await pumpRouter(tester, [
        page('/', 'home'),
        RedirectRoute.builder(
          path: 'u/:id',
          redirect: (context) => '/users/${context.pathParams['id']}',
        ),
      ]);

      final routes = listOf(
        await callOn(router, 'getRouteTable'),
        'routes',
      ).map(mapOf);
      final redirect = routes.firstWhere((route) => route['path'] == 'u/:id');
      expect(redirect['redirectTo'], isNull);
      expect(redirect['isComputedRedirect'], isTrue);
    });

    testWidgets('attributes a route to the branch that declared it', (
      tester,
    ) async {
      final router = await pumpRouter(
        tester,
        branchRoutes(),
        initialLocation: '/todos',
      );

      final shell = mapOf(
        listOf(await callOn(router, 'getRouteTable'), 'routes').single,
      );
      expect(shell['kind'], 'module');
      expect(shell['childRouting'], 'branches');
      expect(shell['branchInitialization'], 'lazy');
      expect(listOf(shell, 'branches').map(mapOf).map((b) => b['name']), [
        'todos',
        'settings',
      ]);
      expect(
        listOf(shell, 'children').map(mapOf).map((child) => child['branch']),
        ['todos', 'settings'],
      );
    });
  });

  group('getNavigationTree', () {
    testWidgets('describes the pages of the root navigator', (tester) async {
      final router = await pumpRouter(tester, [
        page('users', 'users', children: [page(':id', 'user', name: 'user')]),
      ], initialLocation: '/users');

      // Not awaited: a push resolves when the pushed route is popped, and
      // this test wants to look at the stack while it is still up.
      unawaited(router.push<void>('/users/42', extra: const TodoArgs(42)));
      await tester.pumpAndSettle();

      final tree = await callOn(router, 'getNavigationTree');
      expect(tree['currentUri'], '/users/42');

      final frames = listOf(tree, 'frames').map(mapOf).toList();
      expect(frames, hasLength(2));
      expect(frames.last['uri'], '/users/42');
      expect(frames.last['awaitsResult'], isTrue);
      expect(frames.last['extra'], startsWith('TodoArgs#'));

      final pages = listOf(mapOf(tree['root']), 'pages').map(mapOf).toList();
      expect(pages, hasLength(2));
      expect(pages.first['pageKey'], startsWith('modulith_router#'));
      expect(pages.last['frameId'], frames.last['id']);

      final activation = mapOf(pages.last['activation']);
      expect(activation['routePath'], '/users/:id');
      expect(activation['matchedPath'], '/users/42');
      expect(activation['params'], {'id': '42'});
      expect(activation['name'], 'user');
      expect(activation['kind'], 'view');
      expect(activation['module'], isNull);
      expect(activation['extra'], startsWith('TodoArgs#'));
    });

    testWidgets('nests the navigator an outlet route opens', (tester) async {
      final router = await pumpRouter(tester, [
        page(
          '',
          'shell',
          childRouting: ChildRouting.outlet,
          children: [page('settings', 'settings')],
        ),
      ], initialLocation: '/settings');

      final tree = await callOn(router, 'getNavigationTree');
      final shellPage = mapOf(listOf(mapOf(tree['root']), 'pages').single);
      expect(mapOf(shellPage['activation'])['opensOutlet'], isTrue);

      final outlet = mapOf(shellPage['outlet']);
      expect(outlet['ownerActivationId'], mapOf(shellPage['activation'])['id']);
      final nested = mapOf(listOf(outlet, 'pages').single);
      expect(mapOf(nested['activation'])['matchedPath'], '/settings');
    });

    testWidgets('shows the stack a branch retains while in the background', (
      tester,
    ) async {
      final router = await pumpRouter(
        tester,
        branchRoutes(),
        initialLocation: '/todos',
      );
      await router.switchBranch('settings');
      await tester.pumpAndSettle();
      await router.switchBranch('todos');
      await tester.pumpAndSettle();

      final tree = await callOn(router, 'getNavigationTree');
      final shellPage = mapOf(listOf(mapOf(tree['root']), 'pages').single);
      final shell = mapOf(shellPage['activation']);
      expect(shell['kind'], 'module');
      expect(shell['module'], 'ShellModule');
      expect(shell['opensBranches'], isTrue);

      final branches = mapOf(shellPage['branches']);
      expect(branches['active'], 'todos');
      expect(branches['names'], ['todos', 'settings']);

      final outlets = listOf(branches, 'outlets').map(mapOf).toList();
      expect(outlets.map((outlet) => outlet['isActive']), [true, false]);
      expect(
        outlets.last['retainedFrames'],
        1,
        reason: 'The settings branch kept the stack it was left in.',
      );
      final retained = mapOf(
        listOf(mapOf(outlets.last['navigator']), 'pages').single,
      );
      expect(mapOf(retained['activation'])['matchedPath'], '/settings');
    });

    testWidgets('describes the page of a URL nothing matched', (tester) async {
      final router = await pumpRouter(tester, [page('/', 'home')]);

      await router.go('/nope');
      await tester.pumpAndSettle();

      final errorPage = mapOf(
        listOf(
          mapOf((await callOn(router, 'getNavigationTree'))['root']),
          'pages',
        ).single,
      );
      expect(errorPage['isError'], isTrue);
      expect(errorPage['activation'], isNull);
      expect(errorPage['pageKey'], startsWith('modulith_router_error#'));
    });
  });

  group('matchTrace', () {
    testWidgets('explains a match and the guards it would run', (tester) async {
      final router = await pumpRouter(
        tester,
        [
          page('/', 'home'),
          page(
            'todos',
            'todos',
            guards: const [SignedIn()],
            children: [page(':id', 'todo', name: 'todo')],
          ),
        ],
        guards: const [SignedIn()],
      );

      final trace = await callOn(router, 'matchTrace', {
        'location': '/todos/42',
      });

      expect(trace['isMatch'], isTrue);
      expect(trace['uri'], '/todos/42');
      expect(trace['segments'], ['todos', '42']);

      final chain = listOf(trace, 'chain').map(mapOf).toList();
      expect(chain.map((route) => route['debugPath']), [
        '/todos',
        '/todos/:id',
      ]);
      expect(chain.last['params'], {'id': '42'});
      expect(chain.last['name'], 'todo');
      expect(chain.last['matchedPath'], '/todos/42');

      expect(
        listOf(trace, 'guards')
            .map(mapOf)
            .map(
              (guard) =>
                  (guard['guard'], guard['routePath'], guard['isGlobal']),
            ),
        [('SignedIn', null, true), ('SignedIn', '/todos', false)],
        reason: 'The router\'s own guards run before the route\'s.',
      );
    });

    testWidgets('names the routes it tried when nothing matched', (
      tester,
    ) async {
      final router = await pumpRouter(tester, [
        page('/', 'home'),
        page('todos', 'todos', children: [page(':id', 'todo')]),
      ]);

      final trace = await callOn(router, 'matchTrace', {
        'location': '/todos/42/edit',
      });

      expect(trace['isMatch'], isFalse);
      expect(trace['chain'], isEmpty);
      expect(trace['guards'], isEmpty);

      final attempts = listOf(trace, 'attempts').map(mapOf).toList();
      final deepest = attempts.firstWhere(
        (attempt) => attempt['debugPath'] == '/todos/:id',
      );
      expect(deepest['outcome'], 'consumed');
      expect(deepest['consumedUpTo'], 2);
      expect(
        deepest['inChain'],
        isFalse,
        reason:
            'It consumed its segments and was abandoned anyway: nothing '
            'below it took "edit".',
      );
    });

    testWidgets('follows a redirect to where the navigation would land', (
      tester,
    ) async {
      final router = await pumpRouter(tester, [
        page('/', 'home'),
        page(
          'users',
          'users',
          children: [
            page(':id', 'user', guards: const [SignedIn()]),
          ],
        ),
        RedirectRoute.builder(
          path: 'u/:id',
          redirect: (context) => '/users/${context.pathParams['id']}',
        ),
      ]);

      final trace = await callOn(router, 'matchTrace', {'location': '/u/7'});

      expect(trace['isMatch'], isTrue);
      expect(trace['destination'], '/users/7');
      expect(trace['destinationIsMatch'], isTrue);
      expect(trace['redirectLoop'], isFalse);

      final hop = mapOf(listOf(trace, 'redirects').single);
      expect(hop['from'], '/u/7');
      expect(hop['to'], '/users/7');
      expect(hop['routePath'], '/u/:id');

      expect(
        listOf(trace, 'guards').map(mapOf).map((guard) => guard['routePath']),
        ['/users/:id'],
        reason: 'Guards are those of where it lands, not of the redirect.',
      );
    });

    testWidgets('gives up on a redirect loop instead of hanging', (
      tester,
    ) async {
      final router = await pumpRouter(tester, [
        page('/', 'home'),
        const RedirectRoute(path: 'a', to: '/b'),
        const RedirectRoute(path: 'b', to: '/a'),
      ]);

      final trace = await callOn(router, 'matchTrace', {'location': '/a'});

      expect(trace['redirectLoop'], isTrue);
      expect(listOf(trace, 'redirects'), hasLength(5));
    });

    testWidgets('reports a redirect builder that threw', (tester) async {
      final router = await pumpRouter(tester, [
        page('/', 'home'),
        RedirectRoute.builder(
          path: 'boom',
          redirect: (context) => throw StateError('no target'),
        ),
      ]);

      final trace = await callOn(router, 'matchTrace', {'location': '/boom'});

      expect(trace['redirectError'], contains('no target'));
      expect(trace['destination'], '/boom');
    });

    testWidgets('resolves a location the way the router would', (tester) async {
      final router = await pumpRouter(tester, [
        page('/', 'home'),
        page('todos', 'todos'),
      ]);

      final trace = await callOn(router, 'matchTrace', {'location': 'todos'});

      expect(trace['uri'], '/todos');
      expect(trace['isMatch'], isTrue);
    });

    testWidgets('needs a location', (tester) async {
      await pumpRouter(tester, [page('/', 'home')]);

      final response = await RouterInspector.invoke('matchTrace', const {});
      expect(response.isError(), isTrue);
      expect(response.errorDetail, contains('location'));
      expect(response.errorDetail, contains('is required'));
    });
  });

  group('getEventLog', () {
    testWidgets('keeps what an extension that connects late missed', (
      tester,
    ) async {
      final router = await pumpRouter(tester, [
        page('/', 'home'),
        page('about', 'about'),
      ]);

      await router.go('/about');
      await tester.pumpAndSettle();

      final events = listOf(
        await callOn(router, 'getEventLog'),
        'events',
      ).map(mapOf).toList();

      expect(
        events.map((event) => event['event']),
        containsAllInOrder([
          'navigationStarted',
          'routeMatched',
          'stackChanged',
          'navigationEnded',
        ]),
      );
      expect(
        events.map((event) => event['seq']),
        orderedEquals([for (var i = 0; i < events.length; i++) i]),
      );

      final ended = events.lastWhere(
        (event) => event['event'] == 'navigationEnded',
      );
      expect(ended['outcome'], 'completed');
      expect(ended['uri'], '/about');
      expect(ended['durationUs'], isA<int>());
    });

    testWidgets('returns only what the caller has not seen', (tester) async {
      final router = await pumpRouter(tester, [
        page('/', 'home'),
        page('about', 'about'),
      ]);
      final seen =
          listOf(
                await callOn(router, 'getEventLog'),
                'events',
              ).map(mapOf).last['seq']!
              as int;

      await router.go('/about');
      await tester.pumpAndSettle();

      final events = listOf(
        await callOn(router, 'getEventLog', {'since': '$seen'}),
        'events',
      ).map(mapOf);
      expect(events, isNotEmpty);
      expect(events.every((event) => (event['seq']! as int) > seen), isTrue);
      expect(events.first['event'], 'navigationStarted');
    });

    testWidgets('describes a guard with the route it is declared on', (
      tester,
    ) async {
      final router = await pumpRouter(tester, [
        page('/', 'home'),
        page('admin', 'admin', guards: const [SignedIn()]),
      ]);

      await router.go('/admin');
      await tester.pumpAndSettle();

      final guard = listOf(
        await callOn(router, 'getEventLog'),
        'events',
      ).map(mapOf).lastWhere((event) => event['event'] == 'guardEvaluated');
      expect(guard['guard'], 'SignedIn');
      expect(guard['routePath'], '/admin');
      expect(guard['isGlobal'], isFalse);
      expect(guard['result'], 'allow');
    });
  });

  group('bad calls', () {
    testWidgets('names the routers it does know', (tester) async {
      await pumpRouter(tester, [page('/', 'home')]);

      final response = await RouterInspector.invoke('getState', {
        'routerId': '404',
      });
      expect(response.isError(), isTrue);
      expect(
        response.errorCode,
        developer.ServiceExtensionResponse.extensionError,
      );
      expect(response.errorDetail, contains('No router with id 404'));
    });

    testWidgets('rejects a parameter that is not an integer', (tester) async {
      await pumpRouter(tester, [page('/', 'home')]);

      final response = await RouterInspector.invoke('getEventLog', {
        'since': 'yesterday',
      });
      expect(response.isError(), isTrue);
      expect(response.errorDetail, contains('must be an integer'));
    });

    testWidgets('rejects a method it does not have', (tester) async {
      await pumpRouter(tester, [page('/', 'home')]);

      final response = await RouterInspector.invoke('dropDatabase', const {});
      expect(response.isError(), isTrue);
      expect(response.errorDetail, contains('Unknown method'));
    });
  });

  group('describing application values', () {
    test('keeps primitives and identifies everything else', () {
      expect(describeValue(null), isNull);
      expect(describeValue(42), 42);
      expect(describeValue(true), isTrue);
      expect(describeValue('hello'), 'hello');
      expect(describeValue(Uri.parse('/a')), '/a');
      expect(describeValue(NavigationKind.push), 'push');
      expect(describeValue(const TodoArgs(1)), startsWith('TodoArgs#'));
      expect(describeValue({'a': const TodoArgs(1)}), {
        'a': startsWith('TodoArgs#'),
      });
      expect(describeValue([1, 'two']), [1, 'two']);
    });

    test('truncates a long string and a long collection', () {
      expect(describeValue('x' * 500), hasLength(201));
      expect(describeValue(List.filled(50, 1)), hasLength(21));
    });

    test('never asks a value to describe itself', () {
      expect(describeValue(Hostile()), startsWith('Hostile#'));
    });

    testWidgets('encodes a tree that carries a hostile extra', (tester) async {
      final router = await pumpRouter(tester, [
        page('/', 'home'),
        page('about', 'about'),
      ]);

      await router.go('/about', extra: Hostile());
      await tester.pumpAndSettle();

      // The call itself asserts the response is not an error, which is what
      // a throwing serialization would produce.
      final tree = await callOn(router, 'getNavigationTree');
      expect(
        mapOf(listOf(tree, 'frames').last)['extra'],
        startsWith('Hostile#'),
      );
    });
  });
}

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
