# modulith

A lightweight module system for Flutter. Compose your app as a tree of
`Module`s, each owning its own `Controller`s and `Service`s, with reactive
state via `Signal`.

## Features

- **Module** — declares `view`, `controllers`, `services`, and child modules
  through getters. Declarations are captured once per mount.
- **Provider** — creates module-owned dependencies as a `singleton` or
  `factory`. An optional `name` distinguishes providers of the same type.
  Lookups match the type a provider is *registered under*, so register
  against the type callers ask for:
  `Provider<AuthService>.singleton(create: FirebaseAuth.new)`.
- **ModuleScope** — owns provider instances, resolves through parent module
  scopes, and handles initialization and disposal. Lookups are indexed by
  type and name and memoized per scope, so walking up a deep module tree
  costs the same as resolving from the current one. Resolving through a
  scope that has already been disposed throws instead of quietly building an
  instance nobody will ever dispose.
- **Controller** — attach to a module; `createSignal<T>()` builds a
  `Signal` owned by the controller, disposed automatically with it.
  `isDisposed` and `addDisposeCallback()` cover work that outlives a frame —
  timers, subscriptions, in-flight requests.
- **Service** — a plain class you attach to a module for anything that
  isn't per-view reactive state (e.g. a repository). Same lifecycle as a
  controller — `init()`, `dispose()`, `injectService`/`injectController`,
  `addDisposeCallback`, `isDisposed` — minus `createSignal`, because state
  the UI watches belongs in a controller. (Both inherit that from
  `ModuleMember`; you still extend `Controller` or `Service`.)
- Controllers and services resolve their own dependencies in `init()`,
  which runs after their context has been attached.
- **Signal** — a minimal observable (`ChangeNotifier`-based) with a
  `SignalBuilder` widget to rebuild on change. Listeners fire only when the
  value actually changed (`!=`); for state mutated in place, call
  `refresh()`. Writing to a signal whose controller is gone is a no-op, so
  a late async callback can't crash the app. Only ever create one via
  `Controller.createSignal()` — nothing else tracks a `Signal`, so one built
  anywhere else (inside a `Service`, say) leaks. Its constructor is
  `@internal`, so the analyzer flags that.
- **ModularWidget** — the base class for a module's views. `build` gets a
  **ModuleContext**: an ordinary `BuildContext` that also has
  `getController<C>()` / `getService<S>()`, resolving from the current
  module and walking up to ancestor modules if not found locally. Views
  never need a `State` of their own — all state, including Flutter objects
  like a `TextEditingController`, lives in a `Controller`.
- **ChildModuleView\<M\>** — mounts a child module (declared in
  `Module.children`) into the widget tree, scoped under its parent. Several
  children of the same type are told apart by `Module.name`.
- **Provider overrides** — `ModuleWidget(module: ..., overrides: [...])`
  swaps a module's providers for test doubles. See *Testing* below.
- **Module.onInit(context)** / **Module.onDispose(context)** — optional
  lifecycle hooks. The context initializes controllers before `onInit` and
  disposes owned instances after `onDispose`; no `super` call is required.
- **Controller.init()** / **Controller.dispose()** — per-controller setup
  and cleanup driven by `ModuleScope`. Singleton controllers are created
  during mount; factory controllers are created on every lookup. Prefer
  `init()` for injection, subscriptions, timers, and other active-scope work.

## Getting started

Add the dependency and create a `Module`:

```dart
class AppController extends Controller {
  late final name = createSignal<String>('');

  void setName(String value) => name.value = value;
}

class AppModule extends Module {
  @override
  Widget get view => const MainApp();

  @override
  List<Provider<Controller>> get controllers => [
    Provider<AppController>.singleton(create: AppController.new),
  ];
}
```

Then run it:

```dart
void main() => runModuleApp(AppModule());
```

## Usage

A view extends `ModularWidget` and reads its controllers off the
`ModuleContext` it builds with:

```dart
class MainApp extends ModularWidget {
  const MainApp({super.key});

  @override
  Widget build(ModuleContext context) {
    return SignalBuilder(
      signal: context.getController<AppController>().name,
      builder: (value) => Text('Hello, $value!'),
    );
  }
}
```

`ModuleContext` **is** a `BuildContext`, so `Theme.of(context)`,
`Navigator.of(context)` and the rest work exactly as usual.

Views stay stateless. Flutter objects a view would normally keep in a
`State` — a `TextEditingController`, a `ScrollController`, a `FocusNode` —
belong to the controller, which already has a place to dispose them:

```dart
class SearchController extends Controller {
  final input = TextEditingController();

  @override
  void init() => addDisposeCallback(input.dispose);
}

// in the view:
TextField(controller: context.getController<SearchController>().input)
```

To nest modules, declare them in `children` and mount them with
`ChildModuleView`, which stays scoped under the parent module so
`getController`/`getService` can still resolve the parent's dependencies:

```dart
class NameModule extends Module {
  NameModule({this.name});

  @override
  final String? name;

  @override
  Widget get view => const NameView();
}

// inside a parent module's view:
const ChildModuleView<NameModule>()
```

`Module.children` is read once per mount, and a `Module` instance backs
exactly one live scope — mounting the same instance in two places at once
throws. Return fresh instances from the getter:

```dart
class SplitModule extends Module {
  @override
  List<Module> get children => [
    NameModule(name: 'left'),
    NameModule(name: 'right'),
  ];

  @override
  Widget get view => const Row(
    children: [
      ChildModuleView<NameModule>(name: 'left'),
      ChildModuleView<NameModule>(name: 'right'),
    ],
  );
}
```

Controllers may resolve dependencies in `init()`. The context is already
attached at this point, and lookup checks the current module before walking
up through its parents:

```dart
class TodoController extends Controller {
  late final TodoService service;

  @override
  void init() {
    service = injectService<TodoService>();
  }
}

class TodoModule extends Module {
  @override
  List<Provider<Service>> get services => [
    Provider<TodoService>.singleton(create: TodoService.new),
  ];

  @override
  List<Provider<Controller>> get controllers => [
    Provider<TodoController>.singleton(create: TodoController.new),
  ];

  @override
  Widget get view => const TodoPage();
}
```

### Factory lifetimes

`Provider.factory` returns a new instance for every lookup, initialized
immediately. Whoever resolved it owns it:

| Resolved through | Disposed when |
| --- | --- |
| a `ModuleContext` | that widget rebuilds, or leaves the tree |
| `injectController` / `injectService` | the controller or service that asked for it is disposed |
| a `ModuleScope` directly | the module unmounts, or `scope.release(instance)` |

So a `build` method that resolves a factory can't pile up instances — each
build disposes the previous one.

### Async work that outlives the screen

A controller can be disposed while a request is still in flight. Bail out
on `isDisposed`, and register cleanup for anything long-lived:

```dart
class TodoController extends Controller {
  late final todos = createSignal<List<String>>(const []);

  @override
  void init() {
    addDisposeCallback(_subscription.cancel);
    _load();
  }

  Future<void> _load() async {
    final items = await service.fetchInitialTodos();
    if (isDisposed) return;
    todos.value = items;
  }
}
```

Writes to a signal of a disposed controller are ignored rather than
throwing, so a missed guard degrades to a no-op instead of a crash.

## Testing

`overrides` replaces providers a module declares, matched by type and name,
so a feature module can be mounted on its own with fakes in place:

```dart
await tester.pumpWidget(
  MaterialApp(
    home: ModuleWidget(
      module: TodoModule(),
      overrides: [
        Provider<TodoService>.singleton(create: FakeTodoService.new),
      ],
    ),
  ),
);
```

Overrides apply to that module only — override a child module's providers
on its own `ChildModuleView`. An override that matches nothing throws, so a
stale test double fails loudly instead of being silently ignored.

## Error handling

`runModuleApp` is `runApp` around a `ModuleWidget`, and by default it leaves
error handling exactly where Flutter puts it. Pass `onError` to route
everything — framework errors and uncaught async errors alike — through one
callback, without losing the usual console output or red screen:

```dart
void main() => runModuleApp(
  AppModule(),
  onError: (error, stackTrace) =>
      Sentry.captureException(error, stackTrace: stackTrace),
);
```

See `/example` for a complete, feature-first app: five independent feature
modules (counter, todo, profile, stopwatch, dashboard), each pushed as its
own screen and demonstrating a different piece of the framework —
`Controller`/`Signal`, `Controller` + `Service` collaboration, cross-module
`getService` resolution, `init()`/`dispose()` lifecycle with a real `Timer`,
nested modules via `ChildModuleView`, and controller-owned
`TextEditingController`s keeping every view stateless.

## Routing

Routing lives in a separate package, [`modulith_router`](packages/modulith_router),
so an app that doesn't need it doesn't pay for it. It builds on Navigation 2.0
and needs no changes to this package: a route mounts a `Module` whose scope
nests under the route above it, and `RoutingView` is the outlet those children
render into.

An app that routes depends on `modulith_router` **instead of** this package —
it re-exports everything here, so one import covers both.

```dart
RouterModule(
  routes: [
    ModuleRoute(
      path: '/',
      childRouting: ChildRouting.outlet,          // children render in a RoutingView
      builder: (route) => ShellModule(),
      children: [
        ModuleRoute(
          path: 'todos/:id',
          builder: (route) => TodoModule(todoId: route.requireParam('id')),
        ),
      ],
    ),
  ],
  appBuilder: (context, routerConfig) =>
      MaterialApp.router(routerConfig: routerConfig),
)
```

## Performance

Three layers, in order of how much they're worth trusting:

1. **`test/performance_test.dart`** — deterministic rebuild-count assertions
   (part of `flutter test`, runs in CI): a `Signal` update must only rebuild
   the `SignalBuilder` wrapping it, never the enclosing view, a sibling
   `SignalBuilder`, or a parent/child module's view.
2. **`benchmark/`** — informational µs-level micro-benchmarks (`Signal.value
   =` cost vs. listener count, `getController` cost vs. module nesting
   depth). Not run by plain `flutter test`; see `benchmark/README.md`.
3. **`example/integration_test/perf_test.dart`** — a real on-device frame
   -timeline trace via `flutter drive --profile`, for actual jank/frame
   -budget numbers (the other two only measure Dart-side cost, not real
   rendering). Needs a connected device/simulator; see the file header for
   the exact command.

## Additional information

This package is in early development; the API may still change. Issues and
contributions are welcome.
