import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';

import 'module.dart';
import 'module_widget.dart';

/// Runs [module] as the root of the app.
///
/// With no [onError] this is just `runApp` around a [ModuleWidget]: errors
/// keep going wherever they already went — the console in debug, your crash
/// reporter in release — because a framework has no business quietly
/// deciding that for you.
///
/// Pass [onError] to route every uncaught error through one callback:
/// ```dart
/// void main() => runModuleApp(
///   AppModule(),
///   onError: (error, stackTrace) =>
///       Sentry.captureException(error, stackTrace: stackTrace),
/// );
/// ```
/// Both framework errors ([FlutterError.onError]) and uncaught async errors
/// ([PlatformDispatcher.onError]) reach it, and whatever handler was
/// installed before still runs afterwards, so you don't lose the usual
/// red screen or console output by reporting errors.
void runModuleApp(
  Module module, {
  void Function(Object error, StackTrace stackTrace)? onError,
}) {
  if (onError != null) {
    final previousOnError = FlutterError.onError;

    FlutterError.onError = (details) {
      onError(details.exception, details.stack ?? StackTrace.empty);
      previousOnError?.call(details);
    };

    // Funnel async errors through FlutterError so they take the same path,
    // reaching [onError] exactly once.
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'modulith',
          context: ErrorDescription('while running the app'),
        ),
      );
      return true;
    };
  }

  runApp(ModuleWidget(module: module));
}
