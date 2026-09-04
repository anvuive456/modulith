import 'package:flutter/widgets.dart';

import '../runtime/activated_route.dart';
import '../runtime/router_service.dart';
import 'router_scope.dart';

/// Shortcuts for widgets below the router.
///
/// Neither is a new mechanism: [router] is the service the module scope
/// already holds, [route] is the [ActivatedRoute] the enclosing outlet
/// published.
extension ModulithRouterContext on BuildContext {
  /// The router, for navigating from a callback.
  ///
  /// Does not subscribe to anything: navigating from a button should not
  /// make that button rebuild on every navigation. Watch
  /// `RouterController`'s signals when you need to *display* router state.
  RouterService get router {
    final service = RouterScope.maybeServiceOf(this);
    if (service == null) {
      throw FlutterError(
        'context.router was used outside the router. It is available below '
        'the Router that RouterModule creates.',
      );
    }
    return service;
  }

  /// The route data of the screen this widget belongs to.
  ActivatedRoute get route {
    final route = ActivatedRouteScope.maybeOf(this);
    if (route == null) {
      throw FlutterError(
        'context.route was used outside a routed screen. Only widgets below '
        'a RoutingView have an ActivatedRoute.',
      );
    }
    return route;
  }

  /// The route data of the screen this widget belongs to, or `null` when it
  /// is not part of one.
  ActivatedRoute? get routeOrNull => ActivatedRouteScope.maybeOf(this);
}
