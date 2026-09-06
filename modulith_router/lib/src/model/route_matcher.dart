import 'route_definition.dart';
import 'route_match.dart';
import 'route_pattern.dart';

/// Compiles a route table once, then matches URLs against it.
///
/// Matching walks the compiled tree segment by segment, so the cost is
/// proportional to the length of the URL, not to the number of routes.
/// Siblings are tried most-specific first — literal, then `:param`, then
/// `*`, then `**` — which makes the outcome independent of the order routes
/// happen to be declared in.
class RouteMatcher {
  /// Compiles [routes], validating the table as it goes.
  ///
  /// Throws [StateError] for two siblings with the same pattern, a name used
  /// twice, or a parameter name that shadows one from an ancestor route —
  /// all of which are declaration bugs that would otherwise surface as a
  /// mysterious navigation much later.
  RouteMatcher(List<RouteDefinition> routes) {
    _roots = _compile(routes, null, const {});
  }

  late final List<CompiledRoute> _roots;
  final Map<String, CompiledRoute> _byName = {};
  int _nextId = 0;

  /// The compiled top-level routes, most specific first.
  List<CompiledRoute> get roots => _roots;

  /// Matches [uri] and returns the chain from the root route down to the
  /// leaf, or `null` when nothing matches.
  List<RouteMatch>? match(Uri uri) {
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    return _matchIn(_roots, segments, 0, const {}, const []);
  }

  /// The route declared with [name], or `null`.
  CompiledRoute? routeNamed(String name) => _byName[name];

  /// Builds the URL of the route named [name] — reverse routing, so a
  /// caller never has to string-concatenate a path.
  Uri uriFor(
    String name, {
    Map<String, String> pathParams = const {},
    Map<String, String> queryParameters = const {},
  }) {
    final route = _byName[name];
    if (route == null) {
      throw ArgumentError.value(
        name,
        'name',
        'No route with this name. Declared names: '
            '${_byName.keys.isEmpty ? '(none)' : _byName.keys.join(', ')}',
      );
    }
    final segments = <String>[];
    for (CompiledRoute? node = route; node != null; node = node.parent) {
      segments.insertAll(0, node.pattern.expand(pathParams));
    }
    return Uri(
      path: '/${segments.join('/')}',
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
  }

  List<CompiledRoute> _compile(
    List<RouteDefinition> definitions,
    CompiledRoute? parent,
    Set<String> inheritedParams,
  ) {
    final compiled = <CompiledRoute>[];
    final seen = <String>{};

    for (final definition in definitions) {
      final pattern = RoutePattern.parse(definition.path);
      final key = pattern.toString();
      if (!seen.add(key)) {
        throw StateError(
          'Two routes under ${_describe(parent)} declare the same path '
          '"${definition.path}". Matching is by pattern, so one of them '
          'could never be reached.',
        );
      }

      for (final parameter in pattern.parameterNames) {
        if (inheritedParams.contains(parameter)) {
          throw StateError(
            'Route "${definition.path}" under ${_describe(parent)} declares '
            'the parameter ":$parameter", which an ancestor route already '
            'captures. Path parameters accumulate down the chain, so the '
            'ancestor\'s value would be silently overwritten.',
          );
        }
      }

      final route = CompiledRoute(
        id: _nextId++,
        definition: definition,
        pattern: pattern,
        parent: parent,
      );

      final name = definition.name;
      if (name != null) {
        final existing = _byName[name];
        if (existing != null) {
          throw StateError(
            'Two routes are named "$name": ${existing.debugPath} and '
            '${route.debugPath}',
          );
        }
        _byName[name] = route;
      }

      final children =
          definition is ModuleRoute && definition.branches.isNotEmpty
          ? [for (final branch in definition.branches) ...branch.routes]
          : definition.children;
      if (definition is ModuleRoute && definition.branches.isNotEmpty) {
        final names = <String>{};
        for (final branch in definition.branches) {
          if (!names.add(branch.name)) {
            throw StateError(
              'Route ${route.debugPath} declares branch "${branch.name}" more than once.',
            );
          }
        }
      }
      route.children = _compile(children, route, {
        ...inheritedParams,
        ...pattern.parameterNames,
      });
      compiled.add(route);
    }

    // Sort by specificity, keeping declaration order between equals —
    // List.sort is not stable, so the index is part of the comparison.
    final indexed = [for (var i = 0; i < compiled.length; i++) (i, compiled[i])]
      ..sort((a, b) {
        final bySpecificity = a.$2.pattern.compareTo(b.$2.pattern);
        return bySpecificity != 0 ? bySpecificity : a.$1 - b.$1;
      });
    return List.unmodifiable([for (final entry in indexed) entry.$2]);
  }

  List<RouteMatch>? _matchIn(
    List<CompiledRoute> candidates,
    List<String> segments,
    int start,
    Map<String, String> params,
    List<RouteMatch> chain,
  ) {
    for (final route in candidates) {
      final consumed = _consume(route.pattern, segments, start, params);
      if (consumed == null) continue;

      final (end, nextParams) = consumed;
      final extended = [
        ...chain,
        RouteMatch(
          route: route,
          pathParams: nextParams,
          matchedPath: _pathOf(segments, end),
        ),
      ];

      // Children first: `/` should land on a pathless route's index child
      // rather than stopping at the shell itself.
      if (route.children.isNotEmpty) {
        final deeper = _matchIn(
          route.children,
          segments,
          end,
          nextParams,
          extended,
        );
        if (deeper != null) return deeper;
      }
      if (end == segments.length) return extended;
    }
    return null;
  }

  /// Consumes this pattern's segments starting at [start], returning where
  /// matching continues and the parameters captured so far, or `null` when
  /// the pattern does not fit.
  (int, Map<String, String>)? _consume(
    RoutePattern pattern,
    List<String> segments,
    int start,
    Map<String, String> params,
  ) {
    var index = start;
    Map<String, String>? captured;

    for (final segment in pattern.segments) {
      switch (segment.kind) {
        case RouteSegmentKind.literal:
          if (index >= segments.length || segments[index] != segment.value) {
            return null;
          }
          index++;
        case RouteSegmentKind.parameter:
          if (index >= segments.length) return null;
          captured ??= Map.of(params);
          captured[segment.value] = segments[index];
          index++;
        case RouteSegmentKind.wildcard:
          if (index >= segments.length) return null;
          index++;
        case RouteSegmentKind.catchAll:
          captured ??= Map.of(params);
          captured['**'] = segments.sublist(index).join('/');
          index = segments.length;
      }
    }

    return (index, captured == null ? params : Map.unmodifiable(captured));
  }

  String _pathOf(List<String> segments, int end) =>
      '/${segments.sublist(0, end).join('/')}';

  String _describe(CompiledRoute? parent) =>
      parent == null ? 'the route table' : '"${parent.debugPath}"';
}
