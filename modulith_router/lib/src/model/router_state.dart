import 'package:flutter/foundation.dart';

/// One entry of the router's stack: a location, plus whatever non-URL
/// payload it was navigated with.
@immutable
class RouteEntry {
  /// Creates an entry for [uri].
  const RouteEntry({required this.uri, this.extra});

  /// The location this entry represents.
  final Uri uri;

  /// The object passed as `extra`. Not part of equality and never
  /// serialized — two entries for the same URL are the same entry as far as
  /// the platform is concerned.
  final Object? extra;

  @override
  bool operator ==(Object other) =>
      other is RouteEntry && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;

  @override
  String toString() => 'RouteEntry($uri)';
}

/// The router's configuration in the Navigation 2.0 sense: everything the
/// platform needs to describe where the app is, and everything the app needs
/// to restore it from a URL.
///
/// Deliberately thin — no matches, no modules. Matching depends on the route
/// table and can change with a redeploy; keeping it out of the configuration
/// means a restored URL is always re-matched rather than replayed stale.
@immutable
class RouterState {
  /// Creates a state from [entries], oldest first.
  const RouterState(this.entries);

  /// Creates a single-entry state for [uri].
  RouterState.single(Uri uri, {Object? extra})
    : entries = [RouteEntry(uri: uri, extra: extra)];

  /// The stack, oldest first. Never empty in practice.
  final List<RouteEntry> entries;

  /// The location shown to the platform: the topmost entry.
  Uri get uri => entries.last.uri;

  @override
  bool operator ==(Object other) =>
      other is RouterState && listEquals(other.entries, entries);

  @override
  int get hashCode => Object.hashAll(entries);

  @override
  String toString() => 'RouterState(${entries.map((e) => e.uri).join(' → ')})';
}
