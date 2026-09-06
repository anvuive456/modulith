import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modulith/modulith.dart';
import 'package:modulith_router/modulith_router.dart';

/// Records module lifecycle so a test can assert what was torn down.
final lifecycle = <String>[];

class ScreenController extends Controller {
  ScreenController(this.label);

  final String label;

  @override
  void init() => lifecycle.add('init:$label');

  @override
  void dispose() {
    lifecycle.add('dispose:$label');
    super.dispose();
  }
}

class ScreenModule extends Module {
  ScreenModule(this.label, {this.outlet = false});

  final String label;
  final bool outlet;

  @override
  List<Provider<Controller>> get controllers => [
    Provider<ScreenController>.singleton(create: () => ScreenController(label)),
  ];

  @override
  Widget get view => ScreenView(label: label, outlet: outlet);
}

class ScreenView extends ModularWidget {
  const ScreenView({super.key, required this.label, this.outlet = false});

  final String label;
  final bool outlet;

  @override
  Widget build(ModuleContext context) {
    final controller = context.getController<ScreenController>();
    final route = context.routeOrNull;
    return Scaffold(
      body: Column(
        children: [
          Text('screen:${controller.label}'),
          if (route != null)
            ValueListenableBuilder(
              valueListenable: route.params,
              builder: (context, params, _) =>
                  Text('params:${params['id'] ?? '-'}'),
            ),
          if (outlet) const Expanded(child: RoutingView()),
        ],
      ),
    );
  }
}

class EmptyOutletShellModule extends Module {
  @override
  Widget get view => const EmptyOutletShellView();
}

class EmptyOutletShellView extends ModularWidget {
  const EmptyOutletShellView({super.key});

  @override
  Widget build(ModuleContext context) => Scaffold(
    body: RoutingView(empty: (context) => const Text('nothing selected')),
  );
}

class AuthService extends Service {
  AuthService({required this.loggedIn});

  final bool loggedIn;
}

/// An app module above the router, to prove a guard resolves through the
/// module tree rather than from a global.
class AppModule extends Module {
  AppModule({required this.router, required this.loggedIn});

  final RouterModule router;
  final bool loggedIn;

  @override
  List<Module> get children => [router];

  @override
  List<Provider<Service>> get services => [
    Provider<AuthService>.singleton(
      create: () => AuthService(loggedIn: loggedIn),
    ),
  ];

  @override
  Widget get view => const ChildModuleView<RouterModule>();
}

class AuthGuard extends RouteGuard {
  const AuthGuard();

  @override
  GuardResult canActivate(GuardContext context) {
    return context.getService<AuthService>().loggedIn
        ? GuardResult.allow
        : const GuardResult.redirect('/login');
  }
}

class RecordingGuard extends RouteGuard {
  RecordingGuard(this.label, this.log, {this.result = GuardResult.allow});

  final String label;
  final List<String> log;
  final GuardResult result;

  @override
  Future<GuardResult> canActivate(GuardContext context) async {
    log.add(label);
    return result;
  }
}

ModuleRoute screen(
  String path,
  String label, {
  String? name,
  List<RouteDefinition> children = const [],
  List<RouteBranch> branches = const [],
  BranchInitialization branchInitialization = BranchInitialization.lazy,
  ChildRouting childRouting = ChildRouting.stack,
  RouteReuse reuse = RouteReuse.byPathParams,
  List<RouteGuard> guards = const [],
  Page<Object?> Function(BuildContext, ActivatedRoute, Widget)? pageBuilder,
}) => ModuleRoute(
  path: path,
  name: name,
  guards: guards,
  children: children,
  branches: branches,
  branchInitialization: branchInitialization,
  childRouting: childRouting,
  reuse: reuse,
  pageBuilder: pageBuilder,
  builder: (route) {
    final id = route.param('id');
    return ScreenModule(
      id == null ? label : '$label:$id',
      outlet: childRouting != ChildRouting.stack,
    );
  },
);

RouterModule routerModule(
  List<RouteDefinition> routes, {
  String initialLocation = '/',
  List<RouteGuard> guards = const [],
  RouteErrorBuilder? errorBuilder,
}) => RouterModule(
  routes: routes,
  initialLocation: initialLocation,
  guards: guards,
  errorBuilder: errorBuilder,
  appBuilder: (context, routerConfig) =>
      MaterialApp.router(routerConfig: routerConfig),
);

Future<RouterService> pumpModule(WidgetTester tester, Module module) async {
  await tester.pumpWidget(ModuleWidget(module: module));
  await tester.pumpAndSettle();
  return tester.element(find.byType(RoutingView).first).router;
}

Future<RouterService> pumpRouter(
  WidgetTester tester,
  List<RouteDefinition> routes, {
  String initialLocation = '/',
  List<RouteGuard> guards = const [],
  RouteErrorBuilder? errorBuilder,
}) => pumpModule(
  tester,
  routerModule(
    routes,
    initialLocation: initialLocation,
    guards: guards,
    errorBuilder: errorBuilder,
  ),
);

void main() {
  setUp(lifecycle.clear);

  group('mounting', () {
    testWidgets('renders the initial route', (tester) async {
      await pumpRouter(tester, [screen('/', 'home')]);

      expect(find.text('screen:home'), findsOneWidget);
      expect(lifecycle, ['init:home']);
    });

    testWidgets('hands path parameters to the module through its '
        'constructor', (tester) async {
      final router = await pumpRouter(tester, [
        screen('/', 'home'),
        screen('users/:id', 'user'),
      ]);

      await router.go('/users/42');
      await tester.pumpAndSettle();

      expect(find.text('screen:user:42'), findsOneWidget);
    });

    testWidgets('nests child routes as pages on the same navigator', (
      tester,
    ) async {
      final router = await pumpRouter(tester, [
        screen('users', 'users', children: [screen(':id', 'user')]),
      ], initialLocation: '/users');

      expect(find.text('screen:users'), findsOneWidget);
      expect(find.text('screen:user:42'), findsNothing);

      await router.go('/users/42');
      await tester.pumpAndSettle();

      expect(find.text('screen:user:42'), findsOneWidget);
      expect(router.canPop, isTrue);
    });

    testWidgets('renders children of an outlet route inside its '
        'RoutingView', (tester) async {
      final router = await pumpRouter(tester, [
        screen(
          '',
          'shell',
          childRouting: ChildRouting.outlet,
          children: [screen('', 'home'), screen('settings', 'settings')],
        ),
      ]);

      expect(find.text('screen:shell'), findsOneWidget);
      expect(find.text('screen:home'), findsOneWidget);

      await router.go('/settings');
      await tester.pumpAndSettle();

      expect(find.text('screen:shell'), findsOneWidget);
      expect(find.text('screen:settings'), findsOneWidget);
      // The shell was never rebuilt from scratch: only the outlet changed.
      expect(lifecycle, [
        'init:shell',
        'init:home',
        'init:settings',
        'dispose:home',
      ]);
    });

    testWidgets('updates an outlet when sibling routes use NoTransitionPage', (
      tester,
    ) async {
      NoTransitionPage noTransitionPage(
        BuildContext context,
        ActivatedRoute route,
        Widget child,
      ) => NoTransitionPage(child: child);

      final router = await pumpRouter(tester, [
        screen(
          '/',
          'shell',
          childRouting: ChildRouting.outlet,
          children: [
            const RedirectRoute(path: '/', to: '/todos'),
            screen(
              '/todos',
              'todos',
              name: 'todos',
              pageBuilder: noTransitionPage,
            ),
            screen(
              '/settings',
              'settings',
              name: 'settings',
              pageBuilder: noTransitionPage,
            ),
          ],
        ),
      ]);

      expect(find.text('screen:todos'), findsOneWidget);

      await router.go('/settings');
      await tester.pumpAndSettle();

      expect(router.currentUri, Uri.parse('/settings'));
      expect(router.activeRouteName, 'settings');
      expect(find.text('screen:settings'), findsOneWidget);
      expect(find.text('screen:todos'), findsNothing);
    });
  });

  group('what a shell shows at its own URL', () {
    testWidgets('an index child renders without changing the URL', (
      tester,
    ) async {
      final router = await pumpRouter(tester, [
        screen(
          '/',
          'shell',
          childRouting: ChildRouting.outlet,
          children: [screen('', 'todos'), screen('settings', 'settings')],
        ),
      ]);

      expect(find.text('screen:todos'), findsOneWidget);
      expect(router.currentUri, Uri.parse('/'));
    });

    testWidgets('a redirect child sends the shell to a real child URL', (
      tester,
    ) async {
      final router = await pumpRouter(tester, [
        screen(
          '/',
          'shell',
          childRouting: ChildRouting.outlet,
          children: [
            const RedirectRoute(path: '', to: '/todos'),
            screen('todos', 'todos'),
          ],
        ),
      ]);

      expect(find.text('screen:todos'), findsOneWidget);
      expect(router.currentUri, Uri.parse('/todos'));
    });

    testWidgets('an outlet with no matching child says so instead of '
        'rendering blank', (tester) async {
      await pumpRouter(tester, [
        screen(
          '/',
          'shell',
          childRouting: ChildRouting.outlet,
          children: [screen('todos', 'todos')],
        ),
      ]);

      expect(
        tester.takeException(),
        isA<FlutterError>().having(
          (error) => error.message,
          'message',
          allOf(contains('No child route matched'), contains("path: ''")),
        ),
      );
    });

    testWidgets('an outlet given `empty` stays quiet', (tester) async {
      await tester.pumpWidget(
        ModuleWidget(
          module: routerModule([
            ModuleRoute(
              path: '/',
              childRouting: ChildRouting.outlet,
              children: [screen('todos', 'todos')],
              builder: (route) => EmptyOutletShellModule(),
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('nothing selected'), findsOneWidget);
    });
  });

  group('navigation branches', () {
    List<RouteDefinition> routes({
      BranchInitialization initialization = BranchInitialization.lazy,
    }) => [
      screen(
        '/',
        'shell',
        childRouting: ChildRouting.branches,
        branchInitialization: initialization,
        branches: [
          RouteBranch(
            name: 'todos',
            initialLocation: '/todos',
            routes: [
              screen(
                '/todos',
                'todos',
                name: 'todos',
                children: [screen(':id', 'todo-detail', name: 'todo-detail')],
              ),
            ],
          ),
          RouteBranch(
            name: 'settings',
            initialLocation: '/settings',
            routes: [screen('/settings', 'settings', name: 'settings')],
          ),
        ],
      ),
    ];

    testWidgets('restores each branch stack without passing a shell widget', (
      tester,
    ) async {
      final router = await pumpRouter(
        tester,
        routes(),
        initialLocation: '/todos',
      );

      var pushCompleted = false;
      unawaited(
        router.push<void>('/todos/42').then((_) => pushCompleted = true),
      );
      await tester.pumpAndSettle();
      expect(find.text('screen:todo-detail:42'), findsOneWidget);

      await router.switchBranch('settings');
      await tester.pumpAndSettle();
      expect(router.activeBranchName, 'settings');
      expect(router.currentUri, Uri.parse('/settings'));
      expect(find.text('screen:settings'), findsOneWidget);
      expect(find.text('screen:todo-detail:42'), findsNothing);
      expect(router.canPop, isFalse);
      expect(pushCompleted, isFalse);

      await router.switchBranch('todos');
      await tester.pumpAndSettle();
      expect(router.activeBranchName, 'todos');
      expect(router.currentUri, Uri.parse('/todos/42'));
      expect(find.text('screen:todo-detail:42'), findsOneWidget);
      expect(router.canPop, isTrue);
      expect(lifecycle.where((event) => event == 'init:shell'), hasLength(1));
      expect(lifecycle.where((event) => event == 'init:todos'), hasLength(1));

      await router.pop();
      await tester.pumpAndSettle();
      expect(find.text('screen:todos'), findsOneWidget);
      expect(find.text('screen:todo-detail:42'), findsNothing);
      expect(pushCompleted, isTrue);
    });

    testWidgets('completes a push left pending when the outlet itself is '
        'gone', (tester) async {
      final router = await pumpRouter(tester, [
        ...routes(),
        screen('/login', 'login'),
      ], initialLocation: '/todos');

      var pushCompleted = false;
      unawaited(
        router.push<void>('/todos/42').then((_) => pushCompleted = true),
      );
      await tester.pumpAndSettle();

      await router.switchBranch('settings');
      await tester.pumpAndSettle();
      expect(pushCompleted, isFalse);

      await router.go('/login');
      await tester.pumpAndSettle();

      expect(find.text('screen:login'), findsOneWidget);
      expect(
        pushCompleted,
        isTrue,
        reason:
            'Leaving the host drops the stacks it retained, so nothing '
            'can ever pop that frame and answer the push.',
      );
    });

    testWidgets('keeps a nested branch outlet while the branch above it is '
        'in the background', (tester) async {
      final router = await pumpRouter(tester, [
        screen(
          '/',
          'shell',
          childRouting: ChildRouting.branches,
          branches: [
            RouteBranch(
              name: 'todos',
              initialLocation: '/todos/open',
              routes: [
                screen(
                  '/todos',
                  'todos',
                  childRouting: ChildRouting.branches,
                  branches: [
                    RouteBranch(
                      name: 'open',
                      initialLocation: '/todos/open',
                      routes: [screen('open', 'open')],
                    ),
                    RouteBranch(
                      name: 'done',
                      initialLocation: '/todos/done',
                      routes: [screen('done', 'done')],
                    ),
                  ],
                ),
              ],
            ),
            RouteBranch(
              name: 'settings',
              initialLocation: '/settings',
              routes: [screen('/settings', 'settings')],
            ),
          ],
        ),
      ], initialLocation: '/todos/open');

      // switchBranch addresses the innermost outlet of the active route.
      await router.switchBranch('done');
      await tester.pumpAndSettle();
      expect(router.currentUri, Uri.parse('/todos/done'));

      await router.go('/settings');
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason:
            'The nested outlet must not be rebuilt into a plain '
            'navigator when its branch goes to the background.',
      );
      expect(find.text('screen:settings'), findsOneWidget);

      await router.switchBranch('todos');
      await tester.pumpAndSettle();
      expect(router.currentUri, Uri.parse('/todos/done'));

      await router.switchBranch('open');
      await tester.pumpAndSettle();
      expect(router.currentUri, Uri.parse('/todos/open'));
      expect(find.text('screen:open'), findsOneWidget);
      expect(
        lifecycle.where((event) => event == 'init:open'),
        hasLength(1),
        reason: 'The nested branch kept its own stack across the round trip.',
      );
    });

    testWidgets('eagerly initializes every branch', (tester) async {
      final router = await pumpRouter(
        tester,
        routes(initialization: BranchInitialization.eager),
        initialLocation: '/todos',
      );

      expect(router.activeBranchName, 'todos');
      expect(
        lifecycle,
        containsAll(['init:shell', 'init:todos', 'init:settings']),
      );
      expect(find.text('screen:todos'), findsOneWidget);
      expect(find.text('screen:settings'), findsNothing);
    });
  });

  group('lifecycle', () {
    testWidgets('disposes the module of a route it navigates away from', (
      tester,
    ) async {
      final router = await pumpRouter(tester, [
        screen('/', 'home'),
        screen('about', 'about'),
      ]);

      await router.go('/about');
      await tester.pumpAndSettle();

      expect(lifecycle, ['init:home', 'init:about', 'dispose:home']);
    });

    testWidgets('rebuilds the module when path parameters change', (
      tester,
    ) async {
      final router = await pumpRouter(tester, [
        screen('users/:id', 'user'),
      ], initialLocation: '/users/1');

      await router.go('/users/2');
      await tester.pumpAndSettle();

      expect(lifecycle, ['init:user:1', 'init:user:2', 'dispose:user:1']);
      expect(find.text('screen:user:2'), findsOneWidget);
    });

    testWidgets('keeps the module and updates params with RouteReuse.always', (
      tester,
    ) async {
      final router = await pumpRouter(tester, [
        screen('users/:id', 'user', reuse: RouteReuse.always),
      ], initialLocation: '/users/1');

      await router.go('/users/2');
      await tester.pumpAndSettle();

      expect(lifecycle, ['init:user:1']);
      // The constructor value is frozen at activation; the listenable moved.
      expect(find.text('screen:user:1'), findsOneWidget);
      expect(find.text('params:2'), findsOneWidget);
    });
  });

  group('popping', () {
    testWidgets('pop goes back to the page below and updates the URL', (
      tester,
    ) async {
      final router = await pumpRouter(tester, [
        screen('users', 'users', children: [screen(':id', 'user')]),
      ], initialLocation: '/users/42');

      expect(find.text('screen:user:42'), findsOneWidget);

      await router.pop();
      await tester.pumpAndSettle();

      expect(find.text('screen:user:42'), findsNothing);
      expect(router.currentUri, Uri.parse('/users'));
      expect(router.canPop, isFalse);
      expect(lifecycle.last, 'dispose:user:42');
    });

    testWidgets('push resolves with the value passed to pop', (tester) async {
      final router = await pumpRouter(tester, [
        screen('/', 'home'),
        screen('picker', 'picker'),
      ]);

      final picked = router.push<String>('/picker');
      await tester.pumpAndSettle();
      expect(find.text('screen:picker'), findsOneWidget);
      expect(router.canPop, isTrue);

      unawaited(router.pop('chosen'));
      await tester.pumpAndSettle();

      expect(await picked, 'chosen');
      expect(find.text('screen:picker'), findsNothing);
      // The frame it was pushed over is still there, untouched.
      expect(find.text('screen:home'), findsOneWidget);
      expect(router.currentUri, Uri.parse('/'));
      expect(lifecycle, ['init:home', 'init:picker', 'dispose:picker']);
    });

    testWidgets(
      'pushing a descendant of an outlet does not duplicate its shell',
      (tester) async {
        final router = await pumpRouter(tester, [
          screen(
            '/',
            'shell',
            childRouting: ChildRouting.outlet,
            children: [
              const RedirectRoute(path: '/', to: '/todos'),
              screen(
                '/todos',
                'todos',
                name: 'todos',
                children: [screen(':id', 'todo-detail', name: 'todo-detail')],
              ),
            ],
          ),
        ]);

        unawaited(
          router.pushNamed<void>('todo-detail', pathParams: const {'id': '42'}),
        );
        await tester.pumpAndSettle();

        expect(find.text('screen:todo-detail:42'), findsOneWidget);
        expect(
          lifecycle.where((event) => event == 'init:shell'),
          hasLength(1),
          reason: 'A descendant push must stay inside the existing shell.',
        );
        final navigators = tester
            .stateList<NavigatorState>(find.byType(Navigator))
            .toList();
        expect(navigators, hasLength(2));
        expect(
          navigators.where((navigator) => navigator.canPop()),
          hasLength(1),
          reason: 'Only the shell outlet may pop the pushed detail.',
        );
      },
    );

    testWidgets('one pop completes a descendant push inside an outlet', (
      tester,
    ) async {
      final router = await pumpRouter(tester, [
        screen(
          '/',
          'shell',
          childRouting: ChildRouting.outlet,
          children: [
            const RedirectRoute(path: '/', to: '/todos'),
            screen('/todos', 'todos', children: [screen(':id', 'todo-detail')]),
          ],
        ),
      ]);
      var completed = false;
      String? result;
      final pushed = router.push<String>('/todos/42');
      unawaited(
        pushed.then((value) {
          completed = true;
          result = value;
        }),
      );
      await tester.pumpAndSettle();

      await router.pop('saved');
      await tester.pumpAndSettle();

      expect(find.text('screen:todo-detail:42'), findsNothing);
      expect(router.currentUri, Uri.parse('/todos'));
      expect(
        completed,
        isTrue,
        reason: 'Popping the pushed detail must complete the push Future.',
      );
      expect(result, 'saved');
      expect(router.canPop, isFalse);
    });

    testWidgets('pops the deepest outlet first', (tester) async {
      final router = await pumpRouter(tester, [
        screen(
          '',
          'shell',
          childRouting: ChildRouting.outlet,
          children: [
            screen('users', 'users', children: [screen(':id', 'user')]),
          ],
        ),
      ], initialLocation: '/users/42');

      expect(find.text('screen:shell'), findsOneWidget);
      expect(find.text('screen:user:42'), findsOneWidget);

      await router.pop();
      await tester.pumpAndSettle();

      expect(find.text('screen:user:42'), findsNothing);
      expect(find.text('screen:shell'), findsOneWidget);
      expect(router.currentUri, Uri.parse('/users'));
    });
  });

  group('replacing', () {
    testWidgets('replaces the top frame without rebuilding the shell it was '
        'pushed into', (tester) async {
      final router = await pumpRouter(tester, [
        screen(
          '/',
          'shell',
          childRouting: ChildRouting.outlet,
          children: [
            const RedirectRoute(path: '/', to: '/todos'),
            screen(
              '/todos',
              'todos',
              children: [
                screen(
                  ':id',
                  'detail',
                  childRouting: ChildRouting.outlet,
                  children: [
                    screen('edit', 'edit'),
                    screen('preview', 'preview'),
                  ],
                ),
              ],
            ),
          ],
        ),
      ]);

      unawaited(router.push<void>('/todos/42/edit'));
      await tester.pumpAndSettle();
      expect(find.text('screen:edit:42'), findsOneWidget);

      await router.replace('/todos/42/preview');
      await tester.pumpAndSettle();

      expect(router.currentUri, Uri.parse('/todos/42/preview'));
      expect(find.text('screen:preview:42'), findsOneWidget);
      expect(find.text('screen:edit:42'), findsNothing);
      expect(
        lifecycle.where((event) => event == 'init:detail:42'),
        hasLength(1),
        reason: 'Only the replaced page changes; the shell around it stays.',
      );
    });
  });

  group('guards and redirects', () {
    testWidgets('a guard resolves services through the module tree', (
      tester,
    ) async {
      final router = await pumpModule(
        tester,
        AppModule(
          loggedIn: false,
          router: routerModule([
            screen('/', 'home'),
            screen('login', 'login'),
            screen('secret', 'secret', guards: const [AuthGuard()]),
          ]),
        ),
      );

      final result = await router.go('/secret');
      await tester.pumpAndSettle();

      expect(result.outcome, NavigationOutcome.redirected);
      expect(find.text('screen:login'), findsOneWidget);
      expect(find.text('screen:secret'), findsNothing);
    });

    testWidgets('lets navigation through when the guard allows', (
      tester,
    ) async {
      final router = await pumpModule(
        tester,
        AppModule(
          loggedIn: true,
          router: routerModule([
            screen('/', 'home'),
            screen('login', 'login'),
            screen('secret', 'secret', guards: const [AuthGuard()]),
          ]),
        ),
      );

      final result = await router.go('/secret');
      await tester.pumpAndSettle();

      expect(result.outcome, NavigationOutcome.completed);
      expect(find.text('screen:secret'), findsOneWidget);
    });

    testWidgets('runs global guards first, then root to leaf', (tester) async {
      final log = <String>[];
      final router = await pumpRouter(
        tester,
        [
          screen(
            'users',
            'users',
            guards: [RecordingGuard('users', log)],
            children: [
              screen(':id', 'user', guards: [RecordingGuard('detail', log)]),
            ],
          ),
        ],
        guards: [RecordingGuard('global', log)],
      );

      log.clear();
      await router.go('/users/42');
      await tester.pumpAndSettle();

      expect(log, ['global', 'users', 'detail']);
    });

    testWidgets('a blocking guard leaves the router where it was', (
      tester,
    ) async {
      final log = <String>[];
      final router = await pumpRouter(tester, [
        screen('/', 'home'),
        screen(
          'secret',
          'secret',
          guards: [RecordingGuard('secret', log, result: GuardResult.block)],
        ),
      ]);

      final result = await router.go('/secret');
      await tester.pumpAndSettle();

      expect(result.outcome, NavigationOutcome.blocked);
      expect(router.currentUri, Uri.parse('/'));
      expect(find.text('screen:home'), findsOneWidget);
    });

    testWidgets('follows a RedirectRoute', (tester) async {
      final router = await pumpRouter(tester, [
        screen('/', 'home'),
        screen('users/:id', 'user'),
        const RedirectRoute(path: 'u/:id', to: '/users/7'),
      ]);

      final result = await router.go('/u/7');
      await tester.pumpAndSettle();

      expect(result.outcome, NavigationOutcome.redirected);
      expect(find.text('screen:user:7'), findsOneWidget);
    });

    testWidgets('a deactivation guard can refuse to leave', (tester) async {
      final router = await pumpRouter(tester, [
        screen('/', 'home'),
        screen('about', 'about'),
      ]);
      final remove = router.registerDeactivationGuard(() => false);

      expect((await router.go('/about')).outcome, NavigationOutcome.blocked);
      await tester.pumpAndSettle();
      expect(find.text('screen:home'), findsOneWidget);

      remove();
      await router.go('/about');
      await tester.pumpAndSettle();
      expect(find.text('screen:about'), findsOneWidget);
    });
  });

  group('errors', () {
    testWidgets('shows the error screen for a URL nothing matches', (
      tester,
    ) async {
      final router = await pumpRouter(
        tester,
        [screen('/', 'home')],
        errorBuilder: (context, error) =>
            Scaffold(body: Text('missing:${error.uri.path}')),
      );

      await router.go('/nope');
      await tester.pumpAndSettle();

      expect(find.text('missing:/nope'), findsOneWidget);
    });

    testWidgets('prefers a declared ** route over the error screen', (
      tester,
    ) async {
      final router = await pumpRouter(tester, [
        screen('/', 'home'),
        screen('**', 'notFound'),
      ]);

      await router.go('/nope');
      await tester.pumpAndSettle();

      expect(find.text('screen:notFound'), findsOneWidget);
    });
  });

  group('reverse routing', () {
    testWidgets('goNamed builds the URL from name and parameters', (
      tester,
    ) async {
      final router = await pumpRouter(tester, [
        screen('/', 'home'),
        screen('users/:id', 'user', name: 'user'),
      ]);

      await router.goNamed('user', pathParams: {'id': '9'});
      await tester.pumpAndSettle();

      expect(router.currentUri, Uri.parse('/users/9'));
      expect(find.text('screen:user:9'), findsOneWidget);
    });
  });
}
