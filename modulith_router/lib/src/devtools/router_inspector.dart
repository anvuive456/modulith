import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../runtime/navigation_tree.dart';
import '../runtime/router_observer.dart';
import '../runtime/router_service.dart';
import 'inspector_serialization.dart';

/// The router's side of the DevTools extension: a [RouterObserver] that
/// posts what it hears onto the VM service, plus the `ext.modulith_router.*`
/// extensions the extension calls back with.
///
/// Attached by [RouterService] from inside an `assert`, so it exists in
/// debug builds and nowhere else — a release build has no inspector, no
/// event log and no registered extensions.
///
/// Events are pushed, everything else is pulled: a navigation posts a small
/// event, and the extension decides whether to ask for the tree behind it.
/// That keeps a burst of navigations cheap and lets DevTools coalesce.
@internal
class RouterInspector implements RouterObserver {
  RouterInspector._(this.id, this._service, this._navigation);

  /// The `postEvent` kind every router event is posted under. DevTools
  /// listens to the `Extension` stream and filters on it.
  static const String eventKind = 'modulith_router:event';

  /// The prefix of every service extension this class registers.
  static const String extensionPrefix = 'ext.modulith_router.';

  /// How many events are kept for an extension that connects late.
  static const int eventLogLimit = 500;

  /// Every attached inspector, by router id. More than one is normal: a
  /// nested `RouterModule` is a second router.
  static final Map<int, RouterInspector> instances = {};

  static int _nextRouterId = 0;
  static bool _registered = false;

  /// Identifies this router in every payload and in every posted event.
  final int id;

  final RouterService _service;
  final NavigationTree _navigation;
  final Queue<Map<String, Object?>> _log = Queue();

  int _nextSequence = 0;
  int _dropped = 0;

  /// Attaches an inspector to [service] and registers the service
  /// extensions the first time it is called.
  ///
  /// The caller adds the returned inspector to the router's observers and
  /// disposes it with [detach].
  static RouterInspector attach(
    RouterService service,
    NavigationTree navigation,
  ) {
    final inspector = RouterInspector._(_nextRouterId++, service, navigation);
    instances[inspector.id] = inspector;
    _registerExtensions();
    return inspector;
  }

  /// Forgets this inspector. Called when the router is disposed, so a hot
  /// reload that rebuilds the module tree does not leave a router behind
  /// that DevTools would still list.
  void detach() {
    instances.remove(id);
    _log.clear();
  }

  /// The inspector attached to [service], or `null` in a release build.
  static RouterInspector? of(RouterService service) {
    for (final inspector in instances.values) {
      if (identical(inspector._service, service)) return inspector;
    }
    return null;
  }

  @override
  void onEvent(RouterEvent event) {
    final json = describeEvent(event)
      ..['routerId'] = id
      ..['seq'] = _nextSequence++;
    _log.add(json);
    while (_log.length > eventLogLimit) {
      _log.removeFirst();
      _dropped++;
    }
    developer.postEvent(eventKind, json);
  }

  // ---------------------------------------------------------------------
  // Payloads
  // ---------------------------------------------------------------------

  /// Where the router is: the header of the extension.
  Map<String, Object?> state() => describeState(_service, id);

  /// The compiled route table — what the app can route to.
  Map<String, Object?> routeTable() => describeRouteTable(_service, id);

  /// The live frames and the navigator tree they were materialized into.
  Map<String, Object?> navigationTree() =>
      describeNavigationTree(_service, _navigation, id);

  /// What matching [location] would do, without doing it.
  Map<String, Object?> matchTrace(String location) =>
      describeMatchTrace(_service, id, _service.currentUri.resolve(location));

  /// The retained event log, so an extension that connects to a running app
  /// starts with the navigations it missed.
  ///
  /// [since] is the last `seq` the caller already has; only newer events are
  /// returned. [dropped] says how many fell out of the buffer, so the UI can
  /// admit to a gap instead of drawing a wrong timeline.
  Map<String, Object?> eventLog({int? since}) => {
    'type': 'modulith_router.eventLog',
    'routerId': id,
    'dropped': _dropped,
    'events': [
      for (final event in _log)
        if (since == null || (event['seq']! as int) > since) event,
    ],
  };

  /// Every router in the app, for the extension's router picker.
  static Map<String, Object?> routers() => {
    'type': 'modulith_router.routers',
    'routers': [
      for (final inspector in instances.values)
        {
          'id': inspector.id,
          'currentUri': inspector._service.currentUri.toString(),
          'routeCount': inspector._service.matcher.roots.length,
          'frameCount': inspector._service.frames.length,
        },
    ],
  };

  // ---------------------------------------------------------------------
  // Service extensions
  // ---------------------------------------------------------------------

  static void _registerExtensions() {
    if (_registered) return;
    _registered = true;
    _register('listRouters', (parameters) => routers());
    _registerOnRouter('getState', (inspector, parameters) => inspector.state());
    _registerOnRouter(
      'getRouteTable',
      (inspector, parameters) => inspector.routeTable(),
    );
    _registerOnRouter(
      'getNavigationTree',
      (inspector, parameters) => inspector.navigationTree(),
    );
    _registerOnRouter(
      'getEventLog',
      (inspector, parameters) =>
          inspector.eventLog(since: _intParam(parameters, 'since')),
    );
    _registerOnRouter(
      'matchTrace',
      (inspector, parameters) =>
          inspector.matchTrace(_requiredParam(parameters, 'location')),
    );
  }

  static final Map<String, Map<String, Object?> Function(Map<String, String>)>
  _handlers = {};

  static void _register(
    String name,
    Map<String, Object?> Function(Map<String, String>) handler,
  ) {
    _handlers[name] = handler;
    try {
      developer.registerExtension(
        '$extensionPrefix$name',
        (method, parameters) async => invoke(name, parameters),
      );
    } catch (error, stack) {
      // Registration fails if something already claimed the name — a second
      // copy of this package, or a hot restart the VM did not reset. The app
      // must not die over a debugging aid.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'modulith_router',
          context: ErrorDescription(
            'while registering the service extension $extensionPrefix$name',
          ),
        ),
      );
    }
  }

  static void _registerOnRouter(
    String name,
    Map<String, Object?> Function(RouterInspector, Map<String, String>) handler,
  ) => _register(name, (parameters) {
    final routerId = _intParam(parameters, 'routerId');
    final inspector = _resolve(routerId);
    return handler(inspector, parameters);
  });

  /// Resolves the router a call is about: the one asked for, or the only one
  /// there is.
  static RouterInspector _resolve(int? routerId) {
    if (routerId != null) {
      final inspector = instances[routerId];
      if (inspector == null) {
        throw _InspectorError(
          'No router with id $routerId. Live routers: '
          '${instances.keys.join(', ')}.',
        );
      }
      return inspector;
    }
    if (instances.isEmpty) {
      throw const _InspectorError('No router is mounted.');
    }
    if (instances.length > 1) {
      throw _InspectorError(
        'This app has ${instances.length} routers; pass routerId. '
        'Live routers: ${instances.keys.join(', ')}.',
      );
    }
    return instances.values.first;
  }

  static String _requiredParam(Map<String, String> parameters, String name) {
    final value = parameters[name];
    if (value == null || value.isEmpty) {
      throw _InspectorError('Parameter "$name" is required.');
    }
    return value;
  }

  static int? _intParam(Map<String, String> parameters, String name) {
    final raw = parameters[name];
    if (raw == null) return null;
    final value = int.tryParse(raw);
    if (value == null) {
      throw _InspectorError(
        'Parameter "$name" must be an integer, got "$raw".',
      );
    }
    return value;
  }

  /// Runs the handler of [name] and encodes its answer the way the VM
  /// service expects.
  ///
  /// This is the whole body of every registered extension, so a test can
  /// exercise the real path — argument parsing, error shape and all —
  /// without a VM service to talk to.
  @visibleForTesting
  static Future<developer.ServiceExtensionResponse> invoke(
    String name,
    Map<String, String> parameters,
  ) async {
    final handler = _handlers[name];
    if (handler == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        jsonEncode({'error': 'Unknown method $extensionPrefix$name.'}),
      );
    }
    try {
      return developer.ServiceExtensionResponse.result(
        jsonEncode(handler(parameters)),
      );
    } on _InspectorError catch (error) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        jsonEncode({'error': error.message}),
      );
    } catch (error, stack) {
      // A bug in the serialization is a bug in this package; report it the
      // usual way rather than leaving DevTools with a silent failure.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'modulith_router',
          context: ErrorDescription('while answering $extensionPrefix$name'),
        ),
      );
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        jsonEncode({'error': '$error'}),
      );
    }
  }
}

/// An answer the caller asked for wrongly — an unknown router id, a
/// malformed parameter. Reported to DevTools, not to the app's error
/// handler: nothing is broken here.
class _InspectorError implements Exception {
  const _InspectorError(this.message);

  final String message;

  @override
  String toString() => 'RouterInspector: $message';
}
