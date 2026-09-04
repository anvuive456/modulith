import 'package:example/app/app_module.dart';
import 'package:example/features/todo/todo_module.dart';
import 'package:example/features/todo/todo_service.dart';
import 'package:flutter/material.dart';
import 'package:modulith/modulith.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeTodoService extends TodoService {
  @override
  Future<List<String>> fetchInitialTodos() async => const ['Fake item'];
}

void main() {
  testWidgets('home screen lists every feature', (tester) async {
    await tester.pumpWidget(ModuleWidget(module: AppModule()));
    await tester.pumpAndSettle();

    for (final title in [
      'Counter',
      'Todo list',
      'Profile',
      'Stopwatch',
      'Dashboard',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
  });

  testWidgets('Counter: increments, decrements, resets via its controller', (
    tester,
  ) async {
    await tester.pumpWidget(ModuleWidget(module: AppModule()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Counter'));
    await tester.pumpAndSettle();
    expect(find.text('0'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    expect(find.text('0'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'Todo: loads seeded items via an injected Service, then adds/removes',
    (tester) async {
      await tester.pumpWidget(ModuleWidget(module: AppModule()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Todo list'));
      await tester.pump(); // start the push transition

      // Let TodoController.init()'s fake fetch (600ms) resolve.
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Read the README'), findsOneWidget);
      expect(find.text('Try the Stopwatch feature'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Write more tests');
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(find.text('Write more tests'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pump();
      expect(find.text('Read the README'), findsNothing);

      await tester.pageBack();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Profile: getController resolves SettingsController from the app module',
    (tester) async {
      await tester.pumpWidget(ModuleWidget(module: AppModule()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(
        find.text('Guest'),
        findsOneWidget,
      ); // default SettingsController value

      await tester.enterText(find.byType(TextField), 'Alex');
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text('Saved!'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      // The change persists on the shared, app-level SettingsController.
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('Alex'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Stopwatch: starts a timer in init() and cancels it in dispose()',
    (tester) async {
      await tester.pumpWidget(ModuleWidget(module: AppModule()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Stopwatch'));
      await tester.pumpAndSettle();
      expect(find.text('00:00'), findsOneWidget);

      // Pop immediately: this must cancel the periodic Timer (via
      // StopwatchController.dispose()), otherwise flutter_test would fail
      // this test for a pending timer.
      await tester.pageBack();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Dashboard: mounts WeatherModule as a child via ChildModuleView',
    (tester) async {
      await tester.pumpWidget(ModuleWidget(module: AppModule()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Dashboard module mounted at'),
        findsOneWidget,
      );

      // Let WeatherController.init()'s fake fetch (800ms) resolve.
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.textContaining('Hi Guest, today:'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Todo: overrides swap in a fake Service for the test', (
    tester,
  ) async {
    // The feature module is mounted on its own, with its real TodoService
    // replaced — no fake AppModule, no network-shaped wait.
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
    await tester.pumpAndSettle();

    expect(find.text('Fake item'), findsOneWidget);
    expect(find.text('Read the README'), findsNothing);
  });
}
