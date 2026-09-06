import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modulith/modulith.dart';
import 'package:modulith_router_example/main.dart';

void main() {
  testWidgets('the tour works end to end', (tester) async {
    await tester.pumpWidget(ModuleWidget(module: AppModule()));
    await tester.pumpAndSettle();

    // Starts in the todos branch.
    expect(find.text('/todos'), findsOneWidget);
    expect(find.text('Switch tabs and come back'), findsOneWidget);

    // Push a detail inside the branch, flip it, pop it with the value.
    await tester.tap(find.text('Push a detail, then pop it with a value'));
    await tester.pumpAndSettle();
    expect(find.text('/todos/2'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back to the list'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    // And the same trip back the other way: a detail that answers `false` is
    // an answer too, not a "nothing happened".
    await tester.tap(find.text('Push a detail, then pop it with a value'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back to the list'));
    await tester.pumpAndSettle();
    expect(
      find.byIcon(Icons.check_circle),
      findsNothing,
      reason: 'The list has to reload when a todo is unticked, too.',
    );

    // The guarded branch redirects out of the shell.
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    expect(find.text('The account tab redirected here.'), findsOneWidget);

    // Signing in lands back in the account branch.
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Signed in'), findsOneWidget);
    expect(find.text('/account'), findsOneWidget);
  });
}
