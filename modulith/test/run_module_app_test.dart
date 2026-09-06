import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:modulith/modulith.dart';
import 'package:flutter_test/flutter_test.dart';

class AppModule extends Module {
  @override
  Widget get view => const Text('mounted', textDirection: TextDirection.ltr);
}

/// Swaps the global error handlers out for the duration of [body] and puts
/// them back before returning.
///
/// Every assertion has to happen *after* the restore: while the test
/// binding's own `FlutterError.onError` is replaced it can't see failures,
/// and it asserts about exactly that.
Future<void> withRestoredHandlers(Future<void> Function() body) async {
  final bindingOnError = FlutterError.onError;
  final bindingPlatformOnError = PlatformDispatcher.instance.onError;
  try {
    await body();
  } finally {
    FlutterError.onError = bindingOnError;
    PlatformDispatcher.instance.onError = bindingPlatformOnError;
  }
}

void main() {
  testWidgets('mounts the module and leaves error handling alone', (
    tester,
  ) async {
    final before = FlutterError.onError;
    final platformBefore = PlatformDispatcher.instance.onError;

    runModuleApp(AppModule());
    await tester.pump();

    expect(find.text('mounted'), findsOneWidget);
    expect(identical(FlutterError.onError, before), isTrue);
    expect(
      identical(PlatformDispatcher.instance.onError, platformBefore),
      isTrue,
    );
  });

  testWidgets('onError sees framework errors, and the handler that was '
      'installed before still runs', (tester) async {
    final reported = <Object>[];
    final presented = <Object>[];
    final failure = StateError('boom');

    await withRestoredHandlers(() async {
      FlutterError.onError = (details) => presented.add(details.exception);

      runModuleApp(AppModule(), onError: (error, _) => reported.add(error));
      await tester.pump();

      FlutterError.onError!(FlutterErrorDetails(exception: failure));
    });

    expect(reported, [failure]);
    expect(presented, [failure]);
  });

  testWidgets('onError sees uncaught async errors exactly once', (
    tester,
  ) async {
    final reported = <Object>[];
    final failure = StateError('async boom');
    var handled = false;

    await withRestoredHandlers(() async {
      FlutterError.onError = (_) {};

      runModuleApp(AppModule(), onError: (error, _) => reported.add(error));
      await tester.pump();

      handled = PlatformDispatcher.instance.onError!(
        failure,
        StackTrace.current,
      );
    });

    expect(handled, isTrue);
    expect(reported, [failure]);
  });
}
