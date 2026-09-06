import 'package:flutter/widgets.dart';

import '../runtime/activated_route.dart';
import '../runtime/router_service.dart';

/// Publishes the [RouterService] and the current revision of its stack to
/// everything below the root `Router`.
class RouterScope extends InheritedWidget {
  /// Scopes [child] to [service].
  const RouterScope({
    super.key,
    required this.service,
    required this.revision,
    required super.child,
  });

  /// The router driving this subtree.
  final RouterService service;

  /// Bumped whenever the stack changes, so outlets rebuild.
  final int revision;

  /// The nearest scope, throwing a directed error when there is none.
  static RouterScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RouterScope>();
    if (scope == null) {
      throw FlutterError(
        'No RouterScope found. A RoutingView (and context.router) only works '
        'below the Router created by RouterModule.',
      );
    }
    return scope;
  }

  /// The nearest [RouterService] without subscribing to changes — the right
  /// lookup for calling navigation methods.
  static RouterService? maybeServiceOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<RouterScope>()?.service;
  }

  @override
  bool updateShouldNotify(RouterScope oldWidget) =>
      revision != oldWidget.revision || !identical(service, oldWidget.service);
}

/// Identifies the navigation-tree node rendered by a [RoutingView].
class OutletScope extends InheritedWidget {
  /// Scopes [child] to the outlet owned by [ownerActivationId].
  const OutletScope({
    super.key,
    required this.ownerActivationId,
    required this.depth,
    required super.child,
  }) : isRoot = false;

  /// The scope the root `Router` publishes.
  const OutletScope.root({super.key, required super.child})
    : ownerActivationId = null,
      isRoot = true,
      depth = 0;

  /// The activation that owns this outlet, or `null` for the root outlet.
  /// Navigation-tree nodes use this stable id instead of frame positions.
  final int? ownerActivationId;

  /// Distinguishes the root navigator from a `RoutingView` placed below a
  /// route that does not declare an outlet.
  final bool isRoot;

  /// How deeply nested this outlet is; back navigation asks the deepest
  /// outlet first.
  final int depth;

  /// The nearest outlet scope, or `null` outside a router.
  static OutletScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OutletScope>();

  @override
  bool updateShouldNotify(OutletScope oldWidget) =>
      ownerActivationId != oldWidget.ownerActivationId ||
      isRoot != oldWidget.isRoot ||
      depth != oldWidget.depth;
}

/// Publishes the [ActivatedRoute] of the enclosing route to its subtree,
/// which is what `context.route` reads.
class ActivatedRouteScope extends InheritedWidget {
  /// Scopes [child] to [route].
  const ActivatedRouteScope({
    super.key,
    required this.route,
    required super.child,
  });

  /// The route data of the enclosing activation.
  final ActivatedRoute route;

  /// The nearest activated route, or `null` outside any routed screen.
  static ActivatedRoute? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ActivatedRouteScope>()?.route;

  @override
  bool updateShouldNotify(ActivatedRouteScope oldWidget) =>
      !identical(route, oldWidget.route);
}
