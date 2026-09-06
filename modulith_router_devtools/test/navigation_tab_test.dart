import 'dart:async';

import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modulith_router_devtools/src/model/router_models.dart';
import 'package:modulith_router_devtools/src/router_client.dart';
import 'package:modulith_router_devtools/src/router_controller.dart';
import 'package:modulith_router_devtools/src/ui/extension_body.dart';
import 'package:modulith_router_devtools/src/ui/navigation_rows.dart';
import 'package:modulith_router_devtools/src/ui/page_details_view.dart';
import 'package:modulith_router_devtools/src/ui/route_table_rows.dart';

/// Stands in for a connected app, so the whole extension runs in a widget
/// test without a VM service.
class FakeRouterClient implements RouterClient {
  FakeRouterClient({
    required this.tree,
    this.routers = const [
      RouterHandle(id: 0, currentUri: '/todos', routeCount: 1, frameCount: 1),
    ],
  });

  final _events = StreamController<Map<String, Object?>>.broadcast();

  List<RouterHandle> routers;
  Map<String, Object?> tree;
  int treeCalls = 0;

  /// What `getState` reports. Bumping [revision] is how a test says the app
  /// moved without sending an event, which is every web app.
  int revision = 3;
  String currentUri = '/todos';

  @override
  Stream<Map<String, Object?>> get events => _events.stream;

  @override
  Future<List<RouterHandle>> listRouters() async => routers;

  @override
  Future<RouterStateData> getState(int routerId) async =>
      RouterStateData.fromJson({
        'routerId': routerId,
        'revision': revision,
        'currentUri': currentUri,
        'canPop': false,
        'isNavigating': false,
        'activeRouteName': 'todos',
        'activeBranchName': 'todos',
        'frameCount': 1,
      });

  @override
  Future<NavigationSnapshot> getNavigationTree(int routerId) async {
    treeCalls++;
    return NavigationSnapshot.fromJson(tree);
  }

  @override
  Future<RouteTableData> getRouteTable(int routerId) async =>
      RouteTableData.fromJson(routeTableJson());

  @override
  Future<MatchTraceData> matchTrace(int routerId, String location) async {
    traced.add(location);
    return MatchTraceData.fromJson(traceJson(location));
  }

  final traced = <String>[];

  void postEvent() => _events.add({'event': 'stackChanged', 'revision': 4});

  void close() => _events.close();
}

Map<String, Object?> activation({
  required int id,
  required String routePath,
  required String matchedPath,
  String kind = 'view',
  String? module,
  Map<String, String> params = const {},
  bool opensBranches = false,
}) => {
  'id': id,
  'routeId': id,
  'routePath': routePath,
  'kind': kind,
  'name': null,
  'matchedPath': matchedPath,
  'uri': matchedPath,
  'params': params,
  'query': const <String, String>{},
  'extra': null,
  'module': module,
  'childRouting': opensBranches ? 'branches' : 'stack',
  'reuse': 'byPathParams',
  'guards': const <String>[],
  'opensOutlet': false,
  'opensBranches': opensBranches,
};

Map<String, Object?> navigator(
  List<Map<String, Object?>> pages, {
  int? owner,
}) => {'ownerActivationId': owner, 'pages': pages};

Map<String, Object?> page(
  String key,
  Map<String, Object?>? activation, {
  int frameId = 0,
  Map<String, Object?>? branches,
  Map<String, Object?>? outlet,
}) => {
  'pageKey': key,
  'frameId': frameId,
  'segmentIndex': 0,
  'isError': activation == null,
  'uri': '/todos',
  'activation': activation,
  'outlet': ?outlet,
  'branches': ?branches,
};

/// A shell hosting two branches: `todos` active, `settings` in the
/// background with a stack it is holding on to.
Map<String, Object?> branchTree({
  String activeBranch = 'todos',
  bool settingsInitialized = true,
}) => {
  'routerId': 0,
  'revision': 3,
  'currentUri': '/todos',
  'frames': [
    {
      'id': 0,
      'uri': '/todos',
      'isError': false,
      'renderStart': 0,
      'anchorActivationId': null,
      'awaitsResult': false,
      'extra': null,
      'activations': [1, 2],
      'segments': [
        [1],
        [2],
      ],
    },
  ],
  'root': navigator([
    page(
      'modulith_router#1',
      activation(
        id: 1,
        routePath: '/',
        matchedPath: '/',
        kind: 'module',
        module: 'ShellModule',
        opensBranches: true,
      ),
      branches: {
        'ownerActivationId': 1,
        'active': activeBranch,
        'names': ['todos', 'settings'],
        'outlets': [
          {
            'name': 'todos',
            'isActive': activeBranch == 'todos',
            'retainedFrames': 1,
            'navigator': navigator([
              page(
                'modulith_router#2',
                activation(id: 2, routePath: '/todos', matchedPath: '/todos'),
              ),
            ], owner: 1),
          },
          <String, Object?>{
            'name': 'settings',
            'isActive': activeBranch == 'settings',
            'retainedFrames': settingsInitialized ? 1 : 0,
            'navigator': settingsInitialized
                ? navigator([
                    page(
                      'modulith_router#3',
                      activation(
                        id: 3,
                        routePath: '/settings',
                        matchedPath: '/settings',
                        params: {'tab': 'general'},
                      ),
                    ),
                  ], owner: 1)
                : null,
          },
        ],
      },
    ),
  ]),
};

Map<String, Object?> routeNode({
  required int id,
  required String path,
  required String debugPath,
  String pattern = '',
  String kind = 'view',
  String? name,
  String? branch,
  String childRouting = 'stack',
  List<String> guards = const [],
  List<String> params = const [],
  String? redirectTo,
  List<Map<String, Object?>> children = const [],
}) => {
  'id': id,
  'kind': kind,
  'path': path,
  'pattern': pattern,
  'debugPath': debugPath,
  'name': name,
  'isPathless': pattern.isEmpty,
  'params': params,
  'guards': guards,
  'childRouting': childRouting,
  'reuse': 'byPathParams',
  'hasPageBuilder': false,
  'branch': ?branch,
  'redirectTo': redirectTo,
  'isComputedRedirect': false,
  'children': children,
};

/// `/`, `/todos` with a `:id` child behind a guard, and `/u` redirecting to
/// `/todos`.
Map<String, Object?> routeTableJson() => {
  'routerId': 0,
  'globalGuards': ['SignedIn'],
  'routes': [
    routeNode(id: 0, path: '/', debugPath: '/'),
    routeNode(
      id: 1,
      path: 'todos',
      pattern: 'todos',
      debugPath: '/todos',
      children: [
        routeNode(
          id: 2,
          path: ':id',
          pattern: ':id',
          debugPath: '/todos/:id',
          name: 'todo',
          params: ['id'],
          guards: ['SignedIn'],
        ),
      ],
    ),
    routeNode(
      id: 3,
      path: 'u',
      pattern: 'u',
      debugPath: '/u',
      kind: 'redirect',
      redirectTo: '/todos',
    ),
  ],
};

/// A match for anything under `/todos/`, a miss for everything else.
Map<String, Object?> traceJson(String location) {
  final isMatch = location.startsWith('/todos/');
  return {
    'routerId': 0,
    'uri': location,
    'segments': location.split('/').where((part) => part.isNotEmpty).toList(),
    'isMatch': isMatch,
    'chain': isMatch
        ? [
            {
              'routeId': 1,
              'debugPath': '/todos',
              'pattern': 'todos',
              'kind': 'view',
              'name': null,
              'matchedPath': '/todos',
              'params': const <String, String>{},
            },
            {
              'routeId': 2,
              'debugPath': '/todos/:id',
              'pattern': ':id',
              'kind': 'view',
              'name': 'todo',
              'matchedPath': location,
              'params': {'id': location.split('/').last},
            },
          ]
        : const [],
    'attempts': [
      {
        'routeId': 1,
        'debugPath': '/todos',
        'pattern': 'todos',
        'depth': 0,
        'outcome': isMatch ? 'consumed' : 'patternMismatch',
        'consumedUpTo': isMatch ? 1 : 0,
        'inChain': isMatch,
      },
    ],
    'redirects': const [],
    'redirectError': null,
    'redirectLoop': false,
    'destination': location,
    'destinationIsMatch': isMatch,
    'guards': isMatch
        ? [
            {'guard': 'SignedIn', 'routePath': null, 'isGlobal': true},
            {'guard': 'SignedIn', 'routePath': '/todos/:id', 'isGlobal': false},
          ]
        : const [],
  };
}

Future<void> pumpExtension(WidgetTester tester, FakeRouterClient client) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: RouterExtensionBody(client: client)),
    ),
  );
  await tester.pumpAndSettle();
  // A widget test leaves its tree mounted, and the controller polls on a
  // periodic timer; unmount so the controller is disposed and the timer
  // cancelled before the test ends.
  addTearDown(() => tester.pumpWidget(const SizedBox()));
}

void main() {
  group('flattening', () {
    test('hangs a branch outlet off the page that hosts it', () {
      final rows = flattenNavigation(NavigationSnapshot.fromJson(branchTree()));

      expect(rows.map((row) => row.runtimeType), [
        NavigatorRow,
        PageRow,
        BranchesRow,
        BranchRow,
        PageRow,
        BranchRow,
        PageRow,
      ]);
      expect(rows.map((row) => row.depth), [0, 1, 2, 3, 4, 3, 4]);
      expect((rows[3] as BranchRow).branch.name, 'todos');
      expect((rows[3] as BranchRow).branch.isActive, isTrue);
      expect((rows[5] as BranchRow).branch.isActive, isFalse);
    });

    test('says so when a branch has never been visited', () {
      final rows = flattenNavigation(
        NavigationSnapshot.fromJson(branchTree(settingsInitialized: false)),
      );
      expect(rows.last, isA<EmptyRow>());
      expect((rows.last as EmptyRow).message, 'not initialized yet');
    });
  });

  group('the navigation tab', () {
    testWidgets('shows every branch, background ones included', (tester) async {
      final client = FakeRouterClient(tree: branchTree());
      addTearDown(client.close);

      await pumpExtension(tester, client);

      expect(find.text('Navigator (root)'), findsOneWidget);
      expect(find.textContaining('#1  /'), findsOneWidget);
      expect(find.text('ShellModule'), findsOneWidget);
      expect(find.text('todos'), findsOneWidget);
      expect(find.text('settings'), findsOneWidget);
      expect(find.text('active'), findsOneWidget);
      expect(find.text('1 frame retained'), findsOneWidget);
      expect(find.textContaining('/settings'), findsWidgets);
    });

    testWidgets('describes the page that was tapped', (tester) async {
      final client = FakeRouterClient(tree: branchTree());
      addTearDown(client.close);
      await pumpExtension(tester, client);

      expect(
        find.text('Select a page in the navigation tree.'),
        findsOneWidget,
      );

      await tester.tap(find.textContaining('#3  /settings'));
      await tester.pumpAndSettle();

      expect(find.text('Activation #3'), findsOneWidget);
      expect(find.text('/settings'), findsWidgets);
      expect(find.text('general'), findsOneWidget);

      // The frame that owns the page is the last section, below the fold on
      // a test-sized surface.
      await tester.scrollUntilVisible(
        find.text('Frame #0'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(PageDetailsView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Frame #0'), findsOneWidget);
    });

    testWidgets('refreshes once for a burst of events', (tester) async {
      final client = FakeRouterClient(tree: branchTree());
      addTearDown(client.close);
      await pumpExtension(tester, client);
      expect(client.treeCalls, 1);

      client
        ..postEvent()
        ..postEvent()
        ..postEvent();
      await tester.pump();
      expect(
        client.treeCalls,
        1,
        reason: 'The refresh waits for the burst to settle.',
      );

      client.tree = branchTree(activeBranch: 'settings');
      await tester.pump(RouterExtensionController.refreshDelay);
      await tester.pumpAndSettle();

      expect(client.treeCalls, 2);
      expect(
        find.text('active'),
        findsOneWidget,
        reason: 'The tree redrew with settings active.',
      );
    });

    testWidgets('follows an app that cannot post events', (tester) async {
      final client = FakeRouterClient(tree: branchTree());
      addTearDown(client.close);
      await pumpExtension(tester, client);
      expect(client.treeCalls, 1);

      await tester.pump(RouterExtensionController.pollInterval);
      await tester.pumpAndSettle();
      expect(
        client.treeCalls,
        1,
        reason: 'The revision did not move, so there was nothing to pull.',
      );

      client
        ..revision = 4
        ..currentUri = '/settings'
        ..tree = branchTree(activeBranch: 'settings');
      await tester.pump(RouterExtensionController.pollInterval);
      await tester.pumpAndSettle();

      expect(
        client.treeCalls,
        2,
        reason: 'A new revision is the only signal a web app can give.',
      );
      expect(find.text('/settings'), findsWidgets);
    });

    testWidgets('says when the app has no router', (tester) async {
      final client = FakeRouterClient(tree: branchTree())..routers = const [];
      addTearDown(client.close);

      await pumpExtension(tester, client);

      expect(find.text('No router in this app'), findsOneWidget);
    });
  });

  group('the route table tab', () {
    test('keeps the ancestors of what the filter matched', () {
      final table = RouteTableData.fromJson(routeTableJson());

      final all = flattenRouteTable(table.routes);
      expect(all.map((row) => row.node.debugPath), [
        '/',
        '/todos',
        '/todos/:id',
        '/u',
      ]);
      expect(all.map((row) => row.depth), [0, 0, 1, 0]);

      final filtered = flattenRouteTable(table.routes, query: 'todo');
      expect(
        filtered.map((row) => row.node.debugPath),
        ['/todos', '/todos/:id'],
        reason: 'A match keeps the routes it hangs off, and nothing else.',
      );

      expect(flattenRouteTable(table.routes, query: 'nothing'), isEmpty);
    });

    testWidgets('shows the compiled table', (tester) async {
      final client = FakeRouterClient(tree: branchTree());
      addTearDown(client.close);
      await pumpExtension(tester, client);

      await tester.tap(find.widgetWithText(Tab, 'Route table'));
      await tester.pumpAndSettle();

      expect(find.text('Global guards: SignedIn'), findsOneWidget);
      expect(find.text('todos'), findsWidgets);
      expect(find.text(':id'), findsOneWidget);
      expect(find.text('todo'), findsOneWidget);
      expect(find.text('→ /todos'), findsOneWidget);
      expect(
        find.text(
          'Type a URL above to see which routes the table would try, where a '
          'redirect would send it, and which guards would run.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('traces a URL that matches', (tester) async {
      final client = FakeRouterClient(tree: branchTree());
      addTearDown(client.close);
      await pumpExtension(tester, client);
      await tester.tap(find.widgetWithText(Tab, 'Route table'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '/todos/42');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(client.traced, ['/todos/42']);
      expect(find.text('/todos/42 matches'), findsOneWidget);
      expect(find.text('Matched chain'), findsOneWidget);
      expect(find.text('/todos/:id  →  /todos/42  {id: 42}'), findsOneWidget);
      expect(find.text('SignedIn  (global)'), findsOneWidget);
      expect(find.text('SignedIn  on /todos/:id'), findsOneWidget);
    });

    testWidgets('says which routes were tried when nothing matched', (
      tester,
    ) async {
      final client = FakeRouterClient(tree: branchTree());
      addTearDown(client.close);
      await pumpExtension(tester, client);
      await tester.tap(find.widgetWithText(Tab, 'Route table'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '/nope');
      await tester.tap(find.widgetWithText(DevToolsButton, 'Match'));
      await tester.pumpAndSettle();

      expect(find.text('No route matches /nope'), findsOneWidget);
      expect(find.text('Routes tried'), findsOneWidget);
      expect(find.text('/todos  —  pattern did not fit'), findsOneWidget);
      expect(find.text('None — nothing would be checked.'), findsOneWidget);
    });
  });
}
