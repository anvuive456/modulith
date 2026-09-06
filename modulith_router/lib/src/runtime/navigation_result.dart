import 'package:meta/meta.dart';

/// How a navigation call ended.
enum NavigationOutcome {
  /// The router moved to the requested location.
  completed,

  /// A [RedirectRoute] or a guard sent the navigation elsewhere; it landed
  /// on [NavigationResult.uri].
  redirected,

  /// A guard refused. Nothing changed.
  blocked,

  /// A newer navigation started before this one finished its guards, so this
  /// one was dropped.
  superseded,
}

/// The result of a navigation call, so a caller can tell "it worked" from
/// "a guard sent me back to /login" instead of guessing from silence.
@immutable
class NavigationResult {
  /// Creates a result.
  const NavigationResult(this.outcome, this.uri);

  /// What happened.
  final NavigationOutcome outcome;

  /// Where the router ended up (the requested URL, or the redirect target).
  final Uri uri;

  /// Whether the router actually moved.
  bool get isSuccess =>
      outcome == NavigationOutcome.completed ||
      outcome == NavigationOutcome.redirected;

  @override
  String toString() => 'NavigationResult(${outcome.name}, $uri)';
}
