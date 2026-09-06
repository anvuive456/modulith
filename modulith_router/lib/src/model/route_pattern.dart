import 'package:meta/meta.dart';

/// What a single segment of a route path matches.
enum RouteSegmentKind {
  /// An exact segment: `users`.
  literal,

  /// A named parameter: `:id`, captured into `pathParams`.
  parameter,

  /// Exactly one segment, whatever it is: `*`.
  wildcard,

  /// Every remaining segment: `**`. Only valid as the last segment.
  catchAll,
}

/// One parsed segment of a [RoutePattern].
@immutable
class RouteSegment {
  /// Creates a segment of [kind], carrying [value] (the literal text for
  /// [RouteSegmentKind.literal], the parameter name for
  /// [RouteSegmentKind.parameter], empty otherwise).
  const RouteSegment(this.kind, this.value);

  /// What this segment matches.
  final RouteSegmentKind kind;

  /// The literal text or the parameter name.
  final String value;

  /// Lower sorts first: a literal always wins over a parameter, which wins
  /// over a wildcard. This is what makes matching independent of the order
  /// routes happen to be declared in.
  int get priority => kind.index;

  @override
  String toString() => switch (kind) {
    RouteSegmentKind.literal => value,
    RouteSegmentKind.parameter => ':$value',
    RouteSegmentKind.wildcard => '*',
    RouteSegmentKind.catchAll => '**',
  };
}

/// A parsed route path, e.g. `users/:id`.
///
/// A pattern with no segments is *pathless*: it consumes nothing and exists
/// only to group children — that is how a shell/layout route is declared.
@immutable
class RoutePattern {
  const RoutePattern._(this.segments, this.raw);

  /// Parses [path] into segments.
  ///
  /// Leading and trailing slashes are insignificant, so `/`, `''` and `//`
  /// all describe the same pathless pattern. Throws [ArgumentError] on a
  /// malformed path: an empty parameter name, or `**` anywhere but last.
  factory RoutePattern.parse(String path) {
    final parts = path.split('/').where((part) => part.isNotEmpty);
    final segments = <RouteSegment>[];
    for (final part in parts) {
      if (part == '**') {
        segments.add(const RouteSegment(RouteSegmentKind.catchAll, ''));
        continue;
      }
      if (part == '*') {
        segments.add(const RouteSegment(RouteSegmentKind.wildcard, ''));
        continue;
      }
      if (part.startsWith(':')) {
        final name = part.substring(1);
        if (name.isEmpty) {
          throw ArgumentError.value(path, 'path', 'Empty parameter name');
        }
        segments.add(RouteSegment(RouteSegmentKind.parameter, name));
        continue;
      }
      segments.add(RouteSegment(RouteSegmentKind.literal, part));
    }

    for (var i = 0; i < segments.length - 1; i++) {
      if (segments[i].kind == RouteSegmentKind.catchAll) {
        throw ArgumentError.value(
          path,
          'path',
          '`**` matches every remaining segment, so it can only be last',
        );
      }
    }

    return RoutePattern._(List.unmodifiable(segments), path);
  }

  /// The parsed segments, in order.
  final List<RouteSegment> segments;

  /// The path exactly as it was declared, for error messages.
  final String raw;

  /// Whether this pattern consumes no segments at all.
  bool get isPathless => segments.isEmpty;

  /// The names of every `:param` in this pattern.
  Iterable<String> get parameterNames => segments
      .where((segment) => segment.kind == RouteSegmentKind.parameter)
      .map((segment) => segment.value);

  /// Renders this pattern back into path segments, substituting
  /// [pathParams]. Throws [ArgumentError] for a missing parameter, or when
  /// the pattern contains a wildcard (nothing to substitute).
  List<String> expand(Map<String, String> pathParams) {
    return [
      for (final segment in segments)
        switch (segment.kind) {
          RouteSegmentKind.literal => segment.value,
          RouteSegmentKind.parameter =>
            pathParams[segment.value] ??
                (throw ArgumentError(
                  'Missing path parameter "${segment.value}" for "$raw"',
                )),
          RouteSegmentKind.wildcard ||
          RouteSegmentKind.catchAll => throw ArgumentError(
            'Cannot build a URL from "$raw": a wildcard has no value to '
            'substitute',
          ),
        },
    ];
  }

  /// Orders two sibling patterns by specificity, most specific first.
  int compareTo(RoutePattern other) {
    final shared = segments.length < other.segments.length
        ? segments.length
        : other.segments.length;
    for (var i = 0; i < shared; i++) {
      final difference = segments[i].priority - other.segments[i].priority;
      if (difference != 0) return difference;
    }
    // Same prefix: the longer pattern pins down more of the URL itself
    // instead of leaving it to a child, so it is the more specific one.
    return other.segments.length - segments.length;
  }

  @override
  String toString() => segments.isEmpty ? '(pathless)' : segments.join('/');
}
