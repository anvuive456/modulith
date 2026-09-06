# modulith_router

Navigation 2.0 routing for [modulith](https://pub.dev/packages/modulith). A
route table of modules, each mounted with its own scope nested under the route
above it, rendered through `RoutingView` outlets — Angular's
`<router-outlet>`, except an outlet is a real `Navigator`, so children form a
navigable stack.

The router needs **no changes to modulith itself**: it is an ordinary module
declaring an ordinary service.

An app that routes depends on this package only — it re-exports
`package:modulith/modulith.dart`, so one import gives you `Module`,
`Controller`, `Signal` and the routing API together:

```yaml
dependencies:
  modulith_router: ^0.1.0
```

```dart
import 'package:modulith_router/modulith_router.dart';
```

The dependency points one way and stays that way: `modulith` never depends on
this package, so an app that doesn't route pulls in nothing of it. Making the
core re-export the router instead would be a dependency cycle — pub tolerates
it locally, but the two packages could never be published against each other
without leaving users in constraint conflicts.

## Quick start

```dart
final appRoutes = [
  ModuleRoute(
    path: '/',
    builder: (route) => HomeModule(),
    children: [
      ModuleRoute(
        path: 'users/:id',
        name: 'user',
        builder: (route) => UserModule(userId: route.requireParam('id')),
      ),
    ],
  ),
];

class AppModule extends Module {
  @override
  List<Module> get children => [
    RouterModule(
      routes: appRoutes,
      appBuilder: (context, routerConfig) =>
          MaterialApp.router(routerConfig: routerConfig),
    ),
  ];

  @override
  Widget get view => const ChildModuleView<RouterModule>();
}

void main() => runModuleApp(AppModule());
```

Scopes nest the way routes do — `AppModule` → `RouterModule` → each routed
module — so a screen still resolves services declared at the app level.

## Route data reaches a module through its constructor

`ModuleRoute.builder` receives the `ActivatedRoute` and returns a **fresh**
module, so path parameters arrive as plain constructor arguments:

```dart
ModuleRoute(
  path: 'users/:id',
  builder: (route) => UserModule(userId: route.requireParam('id')),
)
```

The controller then depends on a `String`, not on the router, and the screen
can be mounted in a test with `ModuleWidget(module: UserModule(userId: '1'))`
— no router involved.

Widgets below a route can also read `context.route` (params, query, `extra`)
and `context.router` (navigation). `ActivatedRoute` exposes `ValueListenable`s
rather than `Signal`s: a signal must be created by a `Controller` and lives as
long as that controller, so one per navigation would leak. Mirror them into
your own `createSignal` when you want a signal.

## Where children render

Every route decides where its children go:

| `childRouting` | Children render | Use for |
| --- | --- | --- |
| `ChildRouting.stack` (default) | as pages on the same `Navigator` | `/users` → `/users/42` pushes the detail over the list |
| `ChildRouting.outlet` | inside the `RoutingView` in this route's own view | shells: a `Scaffold` with a bottom bar, master-detail, tab hosts |
| `ChildRouting.branches` | in persistent branch `Navigator`s managed by one `RoutingView` | bottom navigation where each tab keeps its own stack |

There is no separate `ShellRoute`: a route with `path: ''` and
`childRouting: ChildRouting.outlet` *is* the shell.

```dart
class ShellView extends ModularWidget {
  @override
  Widget build(ModuleContext context) => Scaffold(
    body: const RoutingView(),               // ← the outlet
    bottomNavigationBar: const AppNavBar(),
  );
}
```

`RoutingView(mode: OutletMode.replace)` swaps a single widget instead of
keeping a stack — for a tab body or a detail pane with no history of its own.

### What a shell shows at its own URL

A shell matching `/` does not pick a child for you. Say which one:

```dart
children: [
  ModuleRoute(path: '', builder: (route) => TodosModule()), // stays at /
  // …or, to move the URL as well:
  RedirectRoute(path: '', to: '/todos'),
  ModuleRoute(path: 'todos', name: 'todos', builder: (route) => TodosModule()),
]
```

An outlet whose parent matched but whose children did not is a hole in the
route table, so in debug it throws with the route to fix rather than rendering
a blank screen. Pass `empty:` when an empty outlet is what you meant.

## Persistent navigation branches

Use branches when each tab needs an independent navigation stack. Branch
routes are routing metadata; the shell does not receive a child widget or a
navigation shell from the router:

```dart
ModuleRoute(
  path: '/',
  builder: (route) => HomeModule(),
  childRouting: ChildRouting.branches,
  branches: [
    RouteBranch(
      name: 'todos',
      initialLocation: '/todos',
      routes: [
        ModuleRoute(
          path: '/todos',
          name: 'todos',
          builder: (route) => TodosModule(),
          children: [
            ModuleRoute(
              path: ':id',
              name: 'todo-detail',
              builder: (route) => TodoDetailModule(
                todoId: route.requireParam('id'),
              ),
            ),
          ],
        ),
      ],
    ),
    RouteBranch(
      name: 'settings',
      initialLocation: '/settings',
      routes: [
        ModuleRoute(
          path: '/settings',
          name: 'settings',
          builder: (route) => SettingsModule(),
        ),
      ],
    ),
  ],
)
```

The shell remains an ordinary module view. `RoutingView` builds and retains
the branch navigators internally:

```dart
class HomeView extends ModularWidget {
  const HomeView({super.key});

  @override
  Widget build(ModuleContext context) {
    final router = context.getService<RouterService>();
    final controller = context.getController<RouterController>();

    return Scaffold(
      body: const RoutingView(),
      bottomNavigationBar: SignalBuilder(
        signal: controller.activeBranchName,
        builder: (branch) => BottomNavigationBar(
          currentIndex: branch == 'settings' ? 1 : 0,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.list), label: 'Todos'),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
          onTap: (index) => router.switchBranch(
            index == 0 ? 'todos' : 'settings',
          ),
        ),
      ),
    );
  }
}
```

`switchBranch(name)` restores that branch's last location and stack. For
example, switching away from `/todos/42` and back to `todos` shows the same
detail page. Only the active branch participates in `canPop`, system back and
the swipe-back gesture. Use `switchBranch(name, reset: true)` to discard the
saved stack and return to the branch's `initialLocation`.

Branches initialize lazily by default. To mount every branch when the host
route activates, opt into eager initialization:

```dart
ModuleRoute(
  path: '/',
  builder: (route) => HomeModule(),
  childRouting: ChildRouting.branches,
  branchInitialization: BranchInitialization.eager,
  branches: [/* ... */],
)
```

Eager initialization makes the first tab switch immediate, but it also runs
module initialization and initial data loading for tabs the user has not
opened. A branch's activation guards still run when that branch becomes
active. A route cannot declare both `children` and `branches`, and every
`initialLocation` must resolve to a route owned by its branch.

## Navigating

`RouterService` is resolved like any other service: `context.router` from a
widget, `injectService<RouterService>()` from a controller.

| Method | |
| --- | --- |
| `go(location)` | replace the whole stack |
| `goNamed(name, pathParams: ..., queryParameters: ...)` | the same, by route name |
| `push<T>(location)` | stack a frame on top and await the value it is popped with |
| `replace(location)` | swap the topmost frame |
| `pop([result])` | pop the deepest outlet that has something to pop |
| `switchBranch(name, reset: false)` | activate a persistent branch and restore or reset its stack |
| `refresh()` | re-run matching and guards on the current URL (after a login) |
| `uriFor(name, ...)` | build a URL without concatenating strings |

Every navigation returns a `NavigationResult` — `completed`, `redirected`,
`blocked` or `superseded` — so a caller can tell why nothing happened.

Reactive state lives on `RouterController`: `uri`, `canPop`, `isNavigating`,
`activeRouteName` and `activeBranchName` as signals, for `SignalBuilder`.

## Guards

```dart
class AuthGuard extends RouteGuard {
  const AuthGuard();

  @override
  GuardResult canActivate(GuardContext context) =>
      context.getService<AuthService>().loggedIn
          ? GuardResult.allow
          : const GuardResult.redirect('/login');
}
```

Global guards run first, then each matched route's, root to leaf; the first
non-allow result wins. Guards may be async, and a newer navigation supersedes
one still waiting.

`context.getService` resolves from the module that declares the router and
upwards — the target route's module is not mounted yet while its guard runs,
the same rule Angular applies.

For "unsaved changes", register from the controller that owns the state:

```dart
@override
void init() {
  final remove = injectService<RouterService>()
      .registerDeactivationGuard(() async => !hasUnsavedChanges);
  addDisposeCallback(remove);
}
```

## Matching

Compiled once into a tree; a match costs the length of the URL, not the size
of the table. Siblings are tried literal → `:param` → `*` → `**`, so the
outcome does not depend on declaration order. Two siblings with the same
pattern, a duplicate route name, or a parameter that shadows an ancestor's all
throw when the table is built rather than during some later navigation.

## Not implemented yet

- Named outlets (`RoutingView(name: ...)` with parallel URL segments).
- Resolvers (prefetching data before activation) — load in a controller and
  show a loading state instead.
- Dialogs and sheets as routes; a custom `pageBuilder` can already return any
  `Page`.
- Restoring more than the topmost frame: a restored URL yields a single frame,
  and `extra` is dropped, since neither survives serialization.

## Testing

The matcher is pure Dart (`RouteMatcher`), so route tables are testable
without pumping widgets — see `test/route_matcher_test.dart`.

For widget tests, mount `RouterModule` inside a `ModuleWidget` and drive the
`RouterService` you read off any context below it
(`tester.element(find.byType(RoutingView).first).router`); `test/router_test.dart`
does exactly that for outlets, module lifecycle, guards and popping. Pass
`routeInformationProvider` when a test needs to feed route information in as
the platform would.

A routed screen needs no router at all: `ModuleWidget(module: TodoModule(todoId: '1'))`
mounts it on its own, with `overrides` for its services.
