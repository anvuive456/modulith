import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:modulith/modulith.dart';

import '../model/route_definition.dart';
import '../model/route_match.dart';
import 'activated_route.dart';

/// One live route in the current chain: the match it came from, its
/// [ActivatedRoute], and — for a [ModuleRoute] — the single [Module]
/// instance mounted for it.
///
/// The module instance lives here rather than being built in `build`, because
/// `ModuleWidget` tears down and rebuilds its scope whenever it is handed a
/// different `Module` instance. Building one per frame would dispose every
/// controller on every rebuild.
class RouteActivation {
  /// Creates an activation. Built by the router.
  @internal
  RouteActivation({
    required this.id,
    required this.match,
    required this.route,
    required this.module,
  });

  /// Unique per activation, so pushing the same location twice yields two
  /// pages with distinct keys instead of one page the [Navigator] mistakes
  /// for the other.
  final int id;

  /// Route data handed to the module and published to the subtree.
  final ActivatedRoute route;

  /// The mounted module, or `null` for a [ViewRoute].
  final Module? module;

  /// The match this activation currently represents. Rebound by [update]
  /// when the activation is reused across a navigation.
  RouteMatch match;

  /// The key of the page this activation renders as.
  ValueKey<String> get pageKey => ValueKey('modulith_router#$id');

  /// Whether this route's children render into a `RoutingView` inside its
  /// own view instead of onto the same [Navigator].
  bool get opensOutlet => match.definition.childRouting == ChildRouting.outlet;

  /// Whether this route hosts persistent navigation branches.
  bool get opensBranches =>
      match.definition.childRouting == ChildRouting.branches;

  /// Whether this activation starts a child navigator boundary.
  bool get opensNavigationBoundary => opensOutlet || opensBranches;

  /// Rebinds this activation to a new match when it is reused across a
  /// navigation.
  @internal
  void update({required RouteMatch match, required Uri uri, Object? extra}) {
    this.match = match;
    route.update(match: match, uri: uri, extra: extra);
  }

  @override
  String toString() => 'RouteActivation(${match.matchedPath})';
}

/// One frame of the router's stack: a location, and the chain of
/// activations it resolved to.
///
/// A frame maps to one entry of `RouterState`. `go` replaces every frame,
/// `push` appends one — which is how an imperative push can sit on top of a
/// location that is not a descendant of the current one.
class RouteFrame {
  /// Creates a frame. Built by the router.
  @internal
  RouteFrame({
    required this.id,
    required this.uri,
    required this.matches,
    required this.activations,
    this.renderStart = 0,
    this.anchorActivationId,
    this.extra,
    this.completer,
  }) : assert(renderStart >= 0 && renderStart <= activations.length),
       assert(matches.length == activations.length || activations.isEmpty),
       segments = _split(activations.skip(renderStart).toList());

  /// Unique per frame, so an error page gets a stable key too.
  final int id;

  /// The location this frame represents.
  final Uri uri;

  /// The complete matched chain for [uri], including reused ancestors that
  /// this frame does not render itself.
  final List<RouteMatch> matches;

  /// The matched chain, root first. Empty when nothing matched, which is
  /// what renders the error page.
  final List<RouteActivation> activations;

  /// The first activation owned and rendered by this frame. Activations before
  /// this index are shared ancestors that locate an imperative push inside an
  /// already-mounted outlet.
  final int renderStart;

  /// The activation whose `RoutingView` renders this frame, or `null` for the
  /// root navigator.
  final int? anchorActivationId;

  /// Activations for which this frame owns pages and module lifecycles.
  Iterable<RouteActivation> get renderedActivations =>
      activations.skip(renderStart);

  /// The activations split into outlet segments: `segments[0]` renders on
  /// the enclosing [Navigator], `segments[1]` inside the `RoutingView` of
  /// the last activation of `segments[0]`, and so on.
  final List<List<RouteActivation>> segments;

  /// The `extra` this frame was navigated with.
  final Object? extra;

  /// Completed when this frame leaves the stack, with the value passed to
  /// `pop`. Only set for frames created by `push`.
  final Completer<Object?>? completer;

  /// Whether this frame failed to match any route.
  bool get isError => activations.isEmpty;

  /// The chain's last activation, or `null` for an error frame.
  RouteActivation? get leaf => activations.isEmpty ? null : activations.last;

  static List<List<RouteActivation>> _split(List<RouteActivation> chain) {
    final segments = <List<RouteActivation>>[];
    var current = <RouteActivation>[];
    for (final activation in chain) {
      current.add(activation);
      if (activation.opensNavigationBoundary) {
        segments.add(List.unmodifiable(current));
        current = <RouteActivation>[];
      }
    }
    if (current.isNotEmpty) segments.add(List.unmodifiable(current));
    return List.unmodifiable(segments);
  }

  @override
  String toString() => 'RouteFrame($uri, ${activations.length} activations)';
}
