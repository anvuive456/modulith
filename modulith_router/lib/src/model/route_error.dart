import 'package:flutter/widgets.dart';

/// A URL the route table has no answer for.
@immutable
class RouteError {
  /// Creates an error for [uri].
  const RouteError({required this.uri, required this.message});

  /// The location that failed to match.
  final Uri uri;

  /// A description safe to show in debug builds.
  final String message;

  @override
  String toString() => 'RouteError($uri: $message)';
}

/// Builds the screen shown when no route matches.
///
/// Declaring a `**` route is the other way to handle this, and the better
/// one when the "not found" screen is a normal part of the app.
typedef RouteErrorBuilder =
    Widget Function(BuildContext context, RouteError error);
