// A single-file tour of modulith_router.
//
// Two persistent branches, each keeping its own navigation stack; a detail
// screen pushed inside one of them that answers the push with a value; a
// guard that redirects out of a branch; and reverse routing by name.
//
// The directory ships without platform folders: run `flutter create .` here
// once, then `flutter run`.

import 'package:flutter/material.dart';
import 'package:modulith/modulith.dart';
import 'package:modulith_router/modulith_router.dart';

void main() => runModuleApp(AppModule());

// ---------------------------------------------------------------------------
// The route table
// ---------------------------------------------------------------------------

/// The shell route hosts two branches. Each branch owns an independent
/// `Navigator`, so pushing a todo detail leaves the account tab untouched and
/// coming back to a tab restores the stack it was left in.
final routes = <RouteDefinition>[
  ModuleRoute(
    path: '/',
    builder: (route) => ShellModule(),
    childRouting: ChildRouting.branches,
    branches: [
      RouteBranch(
        name: 'todos',
        initialLocation: '/todos',
        routes: [
          ModuleRoute(
            path: '/todos',
            name: 'todos',
            builder: (route) => TodoListModule(),
            children: [
              // A child of a `ChildRouting.stack` route: it is pushed onto
              // the same navigator, which here is the branch's own.
              ModuleRoute(
                path: ':id',
                name: 'todo',
                builder: (route) =>
                    TodoDetailModule(id: route.requireParam('id')),
              ),
            ],
          ),
        ],
      ),
      RouteBranch(
        name: 'account',
        initialLocation: '/account',
        routes: [
          ModuleRoute(
            path: '/account',
            name: 'account',
            guards: const [SignedIn()],
            builder: (route) => AccountModule(),
          ),
        ],
      ),
    ],
  ),
  // Outside the shell, so signing in covers the tabs entirely.
  ModuleRoute(
    path: '/sign-in',
    name: 'sign-in',
    builder: (route) => SignInModule(),
  ),
];

// ---------------------------------------------------------------------------
// The app module: services declared here resolve from every routed module,
// because route scopes nest under the module that mounts the router.
// ---------------------------------------------------------------------------

class AppModule extends Module {
  @override
  List<Provider<Service>> get services => [
    Provider<TodoService>.singleton(create: TodoService.new),
    Provider<SessionService>.singleton(create: SessionService.new),
  ];

  @override
  List<Module> get children => [
    RouterModule(
      routes: routes,
      initialLocation: '/todos',
      appBuilder: (context, routerConfig) => MaterialApp.router(
        title: 'modulith_router',
        theme: ThemeData(colorSchemeSeed: Colors.indigo),
        routerConfig: routerConfig,
      ),
    ),
  ];

  @override
  Widget get view => const ChildModuleView<RouterModule>();
}

class Todo {
  Todo(this.id, this.title);

  final String id;
  final String title;
  bool done = false;
}

class TodoService extends Service {
  final List<Todo> todos = [
    Todo('1', 'Switch tabs and come back'),
    Todo('2', 'Push a detail, then pop it with a value'),
    Todo('3', 'Open the guarded account tab'),
  ];

  Todo byId(String id) => todos.firstWhere((todo) => todo.id == id);
}

class SessionService extends Service {
  bool signedIn = false;
}

/// Guards read services, never controllers: the target route's module is not
/// mounted yet while its guard runs.
class SignedIn extends RouteGuard {
  const SignedIn();

  @override
  GuardResult canActivate(GuardContext context) =>
      context.getService<SessionService>().signedIn
      ? GuardResult.allow
      : const GuardResult.redirect('/sign-in');
}

// ---------------------------------------------------------------------------
// The shell: an ordinary module view with a `RoutingView` in it. The router
// hands it no navigation shell and no child widget.
// ---------------------------------------------------------------------------

class ShellModule extends Module {
  @override
  Widget get view => const ShellView();
}

class ShellView extends ModularWidget {
  const ShellView({super.key});

  @override
  Widget build(ModuleContext context) {
    final router = context.router;
    final state = context.getController<RouterController>();

    return Scaffold(
      appBar: AppBar(
        // Router state a widget *displays* comes from RouterController's
        // signals; `context.router` is for navigating and subscribes to
        // nothing.
        title: SignalBuilder(signal: state.uri, builder: (uri) => Text('$uri')),
        actions: [
          IconButton(
            tooltip: "goNamed('todo', {'id': '3'})",
            icon: const Icon(Icons.bolt_outlined),
            onPressed: () =>
                router.goNamed('todo', pathParams: const {'id': '3'}),
          ),
        ],
      ),
      body: const RoutingView(),
      bottomNavigationBar: SignalBuilder(
        signal: state.activeBranchName,
        builder: (branch) => NavigationBar(
          selectedIndex: branch == 'account' ? 1 : 0,
          onDestinationSelected: (index) =>
              router.switchBranch(index == 0 ? 'todos' : 'account'),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.checklist_outlined),
              label: 'Todos',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              label: 'Account',
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The todos branch
// ---------------------------------------------------------------------------

class TodoListModule extends Module {
  @override
  List<Provider<Controller>> get controllers => [
    Provider<TodoListController>.singleton(create: TodoListController.new),
  ];

  @override
  Widget get view => const TodoListView();
}

class TodoListController extends Controller {
  late final TodoService _todos;

  /// A signal is created by a controller and disposed with it.
  late final items = createSignal<List<Todo>>(const []);

  @override
  void init() {
    _todos = injectService<TodoService>();
    reload();
  }

  void reload() => items.value = List.of(_todos.todos);
}

class TodoListView extends ModularWidget {
  const TodoListView({super.key});

  @override
  Widget build(ModuleContext context) {
    final router = context.router;
    final controller = context.getController<TodoListController>();

    return Scaffold(
      body: SignalBuilder(
        signal: controller.items,
        builder: (items) => ListView(
          children: [
            for (final todo in items)
              ListTile(
                leading: Icon(
                  todo.done ? Icons.check_circle : Icons.circle_outlined,
                ),
                title: Text(todo.title),
                subtitle: Text('/todos/${todo.id}'),
                // `push` resolves with whatever the detail passes to `pop`,
                // so the list learns what happened without any shared state.
                // It resolves with null when the screen is dismissed instead.
                onTap: () async {
                  final changed = await router.push<bool>('/todos/${todo.id}');
                  if (changed ?? false) controller.reload();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class TodoDetailModule extends Module {
  TodoDetailModule({required this.id});

  /// Route data reaches a module through its constructor, so the controller
  /// below depends on a `String` rather than on the router.
  final String id;

  @override
  List<Provider<Controller>> get controllers => [
    Provider<TodoDetailController>.singleton(
      create: () => TodoDetailController(id),
    ),
  ];

  @override
  Widget get view => const TodoDetailView();
}

class TodoDetailController extends Controller {
  TodoDetailController(this.id);

  final String id;
  late final Todo _todo;
  late final done = createSignal<bool>(false);

  String get title => _todo.title;

  @override
  void init() {
    _todo = injectService<TodoService>().byId(id);
    done.value = _todo.done;
  }

  void toggle() {
    _todo.done = !_todo.done;
    done.value = _todo.done;
  }
}

class TodoDetailView extends ModularWidget {
  const TodoDetailView({super.key});

  @override
  Widget build(ModuleContext context) {
    final router = context.router;
    final controller = context.getController<TodoDetailController>();

    // Pushed inside the branch navigator, so the tab bar stays put and the
    // back arrow pops this page only.
    return Scaffold(
      appBar: AppBar(title: Text(controller.title)),
      body: Center(
        child: SignalBuilder(
          signal: controller.done,
          builder: (done) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('Done'),
                value: done,
                onChanged: (_) => controller.toggle(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                // Answers the awaiting `push` with the value.
                onPressed: () => router.pop(done),
                child: const Text('Back to the list'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The guarded branch
// ---------------------------------------------------------------------------

class AccountModule extends Module {
  @override
  Widget get view => const AccountView();
}

class AccountView extends ModularWidget {
  const AccountView({super.key});

  @override
  Widget build(ModuleContext context) {
    final router = context.router;
    final session = context.getService<SessionService>();

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Signed in'),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                session.signedIn = false;
                // Leaves the branch host entirely; the todos branch is built
                // again from its initial location when it is next opened.
                router.go('/todos');
              },
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}

class SignInModule extends Module {
  @override
  Widget get view => const SignInView();
}

class SignInView extends ModularWidget {
  const SignInView({super.key});

  @override
  Widget build(ModuleContext context) {
    final router = context.router;
    final session = context.getService<SessionService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('The account tab redirected here.'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                session.signedIn = true;
                router.go('/account');
              },
              child: const Text('Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}
