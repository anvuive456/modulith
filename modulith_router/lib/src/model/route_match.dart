import 'package:meta/meta.dart';

import 'route_definition.dart';
import 'route_pattern.dart';

/// A [RouteDefinition] after the route table has been compiled: its parsed
/// pattern, its place in the tree, and a stable id.
///
/// Users declare [RouteDefinition]s; the router matches against these.
class CompiledRoute {
  /// Wires a compiled node. Built by the router, not by application code.
  @internal
  CompiledRoute({
    required this.id,
    required this.definition,
    required this.pattern,
    required this.parent,
  });

  /// Unique within one route table; part of a page's key.
  final int id;

  /// The declaration this node was compiled from.
  final RouteDefinition definition;

  /// The parsed [RouteDefinition.path].
  final RoutePattern pattern;

  /// The enclosing route, or `null` for a top-level one.
  final CompiledRoute? parent;

  /// Compiled children, sorted most specific first.
  late final List<CompiledRoute> children;

  /// The full declared path from the root, for error messages.
  String get debugPath {
    final parts = <String>[];
    for (CompiledRoute? node = this; node != null; node = node.parent) {
      if (!node.pattern.isPathless) parts.insert(0, node.pattern.toString());
    }
    return '/${parts.join('/')}';
  }

  @override
  String toString() => 'CompiledRoute($debugPath)';
}

/// One route of a matched chain: which route matched, and what it captured.
@immutable
class RouteMatch {
  /// Creates a match. Built by the matcher, not by application code.
  @internal
  const RouteMatch({
    required this.route,
    required this.pathParams,
    required this.matchedPath,
  });

  /// The route that matched.
  final CompiledRoute route;

  /// Path parameters captured so far, including those of ancestor routes.
  final Map<String, String> pathParams;

  /// The part of the URL consumed up to and including this route, e.g.
  /// `/users/42`.
  final String matchedPath;

  /// The declaration behind [route].
  RouteDefinition get definition => route.definition;

  @override
  String toString() => 'RouteMatch(${route.debugPath} -> $matchedPath)';
}
