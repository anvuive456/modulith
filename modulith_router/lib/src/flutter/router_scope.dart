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

/// Tells a [RoutingView] which slice of the stack it renders.
///
/// The root outlet renders segment 0 of every frame. Each route that opens
/// an outlet publishes the next segment index for the `RoutingView` inside
/// its own view; every other route publishes `null`, so a stray
/// `RoutingView` fails with a clear message instead of rendering its own
/// ancestors again.
class OutletScope extends InheritedWidget {
  /// Scopes [child] to one segment of one frame.
  const OutletScope({
    super.key,
    required this.frameIndex,
    required this.segmentIndex,
    required this.depth,
    required super.child,
  });

  /// The scope the root `Router` publishes.
  const OutletScope.root({super.key, required super.child})
    : frameIndex = null,
      segmentIndex = 0,
      depth = 0;

  /// Which frame this outlet belongs to, or `null` for the root outlet,
  /// which renders across every frame.
  final int? frameIndex;

  /// Which segment of that frame to render, or `null` when the enclosing
  /// route has no outlet slot.
  final int? segmentIndex;

  /// How deeply nested this outlet is; back navigation asks the deepest
  /// outlet first.
  final int depth;

  /// The nearest outlet scope, or `null` outside a router.
  static OutletScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OutletScope>();

  @override
  bool updateShouldNotify(OutletScope oldWidget) =>
      frameIndex != oldWidget.frameIndex ||
      segmentIndex != oldWidget.segmentIndex ||
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
