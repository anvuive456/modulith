import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../model/router_state.dart';

/// Turns platform route information into a [RouterState] and back.
///
/// Deliberately dumb: it does not match, redirect or run guards. Matching
/// depends on the route table and guards are asynchronous and need
/// dependencies — both belong in the delegate, which gets to be `async` and
/// has a module scope to resolve from.
class ModulithRouteInformationParser extends RouteInformationParser<RouterState> {
  /// Creates a parser.
  const ModulithRouteInformationParser();

  @override
  Future<RouterState> parseRouteInformation(RouteInformation routeInformation) {
    return SynchronousFuture(RouterState.single(routeInformation.uri));
  }

  @override
  RouteInformation? restoreRouteInformation(RouterState configuration) {
    return RouteInformation(uri: configuration.uri);
  }
}
