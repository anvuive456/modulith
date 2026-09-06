import 'package:flutter/foundation.dart';

import '../model/route_definition.dart';
import '../model/route_match.dart';

/// The data of one live route activation: its parameters, the URL it was
/// activated with, and whatever was passed as `extra`.
///
/// One `ActivatedRoute` exists per activated route in the current chain, and
/// it is handed to [ModuleRoute.builder] so a module can take what it needs
/// through its own constructor. It is deliberately **not** a `Service` and
/// does not live in a `ModuleScope`: it is owned by the router, its lifetime
/// does not always line up with a module scope, and a lookup that walked up
/// to an ancestor's route would be a silent bug.
///
/// [params], [query] and [uri] are [ValueListenable]s rather than `Signal`s
/// because a `Signal` must be created by a `Controller` and lives until that
/// controller is disposed — one per navigation would leak. A controller that
/// wants a signal mirrors these into its own `createSignal`.
class ActivatedRoute {
  /// Creates the route data for one activation. Built by the router.
  @internal
  ActivatedRoute({
    required RouteMatch match,
    required Uri uri,
    this.parent,
    this._extra,
  }) : _match = match,
       _params = ValueNotifier(match.pathParams),
       _query = ValueNotifier(uri.queryParameters),
       _uri = ValueNotifier(uri);

  RouteMatch _match;
  Object? _extra;
  final ValueNotifier<Map<String, String>> _params;
  final ValueNotifier<Map<String, String>> _query;
  final ValueNotifier<Uri> _uri;

  /// The route data of the enclosing route, or `null` at the top level.
  final ActivatedRoute? parent;

  /// Path parameters captured by this route and its ancestors.
  ValueListenable<Map<String, String>> get params => _params;

  /// The query parameters of the current URL.
  ValueListenable<Map<String, String>> get query => _query;

  /// The full URL this route was activated with.
  ValueListenable<Uri> get uri => _uri;

  /// The object passed to `go`/`push` as `extra`.
  ///
  /// Never serialized into the URL, so it is gone after a reload or a state
  /// restoration. Anything that must survive belongs in the URL.
  Object? get extra => _extra;

  /// The declared name of this route, if it has one.
  String? get name => _match.definition.name;

  /// The part of the URL this route consumed, e.g. `/users/42`.
  String get matchedPath => _match.matchedPath;

  /// The declaration this activation came from.
  RouteDefinition get definition => _match.definition;

  /// The path parameter [name], or `null` if this route did not capture it.
  String? param(String name) => _params.value[name];

  /// The path parameter [name], or a [StateError] naming the route when it
  /// is missing — a typo in a parameter name should not read as `null`.
  String requireParam(String name) {
    final value = _params.value[name];
    if (value == null) {
      throw StateError(
        'Route "${_match.route.debugPath}" has no path parameter "$name". '
        'Captured: ${_params.value.keys.join(', ')}',
      );
    }
    return value;
  }

  /// Pushes new values in when this activation is reused across a
  /// navigation (see `RouteReuse.always`).
  @internal
  void update({required RouteMatch match, required Uri uri, Object? extra}) {
    _match = match;
    _extra = extra;
    if (!mapEquals(_params.value, match.pathParams)) {
      _params.value = match.pathParams;
    }
    if (!mapEquals(_query.value, uri.queryParameters)) {
      _query.value = uri.queryParameters;
    }
    _uri.value = uri;
  }

  @override
  String toString() => 'ActivatedRoute($matchedPath)';
}
