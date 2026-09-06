import 'package:flutter/foundation.dart';

import '../model/route_definition.dart';
import '../model/route_match.dart';
import 'guards.dart';
import 'navigation_result.dart';

/// What kind of call started a navigation.
enum NavigationKind {
  /// `RouterService.go` or `goNamed`: the whole stack is replaced.
  go,

  /// `RouterService.push` or `pushNamed`: a frame is added on top.
  push,

  /// `RouterService.replace`: the topmost frame is swapped out.
  replace,

  /// `RouterService.switchBranch`: a persistent branch is activated.
  switchBranch,

  /// A configuration handed over by the platform — a deep link, a browser
  /// back or forward, a state restoration. Applied like [go].
  platform,
}

/// What sent a navigation somewhere other than where it was headed.
enum RedirectSource {
  /// A [RedirectRoute] matched.
  route,

  /// A [RouteGuard] answered with [GuardResult.redirect].
  guard,
}

/// Something the router did, reported to a [RouterObserver].
///
/// Every event of one navigation call carries the same
/// [NavigationEvent.navigationId], so a consumer can group them: a
/// [NavigationStarted], the [GuardEvaluated]s it ran, and the
/// [NavigationEnded] that says how it turned out.
@immutable
sealed class RouterEvent {
  /// Stamps an event.
  const RouterEvent({required this.timestamp});

  /// When the router built this event.
  final DateTime timestamp;
}

/// An event that belongs to one navigation call.
@immutable
sealed class NavigationEvent extends RouterEvent {
  /// Stamps an event of navigation [navigationId].
  const NavigationEvent({required this.navigationId, required super.timestamp});

  /// Unique per navigation call, and shared by every event that call emits.
  ///
  /// Ids are handed out in call order, which is not the order navigations
  /// finish in: an async guard can let a later navigation overtake an
  /// earlier one, which is exactly what [NavigationOutcome.superseded]
  /// reports.
  final int navigationId;
}

/// A navigation call was made. Always the first event of its id.
final class NavigationStarted extends NavigationEvent {
  /// Reports a navigation call.
  const NavigationStarted({
    required super.navigationId,
    required super.timestamp,
    required this.kind,
    required this.from,
    required this.to,
    this.extra,
  });

  /// What kind of call this was.
  final NavigationKind kind;

  /// Where the router was when the call was made.
  final Uri from;

  /// Where the call asked to go, before any redirect.
  final Uri to;

  /// The `extra` the call was made with.
  final Object? extra;

  @override
  String toString() => 'NavigationStarted(#$navigationId ${kind.name}: $to)';
}

/// A URL was matched against the route table.
///
/// Emitted once per attempt, so a navigation that redirects twice reports
/// three matches.
final class RouteMatched extends NavigationEvent {
  /// Reports the outcome of matching [uri].
  const RouteMatched({
    required super.navigationId,
    required super.timestamp,
    required this.uri,
    required this.matches,
  });

  /// The URL that was matched.
  final Uri uri;

  /// The matched chain, root first, or `null` when nothing matched — which
  /// is what puts the error page on screen.
  final List<RouteMatch>? matches;

  /// Whether the route table had an answer for [uri].
  bool get isMatch => matches != null;

  @override
  String toString() =>
      'RouteMatched(#$navigationId $uri -> '
      '${matches == null ? 'no match' : matches!.last.route.debugPath})';
}

/// A navigation was sent somewhere else.
final class RedirectApplied extends NavigationEvent {
  /// Reports a redirect from [from] to [to].
  const RedirectApplied({
    required super.navigationId,
    required super.timestamp,
    required this.from,
    required this.to,
    required this.source,
  });

  /// Where the navigation was headed.
  final Uri from;

  /// Where it is headed now.
  final Uri to;

  /// What decided.
  final RedirectSource source;

  @override
  String toString() =>
      'RedirectApplied(#$navigationId ${source.name}: $from -> $to)';
}

/// A guard ran and answered.
final class GuardEvaluated extends NavigationEvent {
  /// Reports one guard's decision.
  const GuardEvaluated({
    required super.navigationId,
    required super.timestamp,
    required this.guardType,
    required this.routePath,
    required this.result,
    required this.duration,
  });

  /// The runtime type of the guard, for naming it in a log or a timeline.
  final Type guardType;

  /// The declared path of the route this guard is attached to, or `null`
  /// for a guard passed to the router itself.
  final String? routePath;

  /// What the guard answered.
  final GuardResult result;

  /// How long it took — the number that explains a navigation that felt
  /// slow.
  final Duration duration;

  /// Whether this is one of the router's own guards rather than a route's.
  bool get isGlobal => routePath == null;

  @override
  String toString() =>
      'GuardEvaluated(#$navigationId $guardType on '
      '${routePath ?? '<global>'} -> ${result.runtimeType} '
      'in ${duration.inMicroseconds}us)';
}

/// A [DeactivationGuard] refused to leave the current screen.
final class DeactivationBlocked extends NavigationEvent {
  /// Reports a refused departure.
  const DeactivationBlocked({
    required super.navigationId,
    required super.timestamp,
    required this.uri,
  });

  /// The location the navigation was refused on the way to.
  final Uri uri;

  @override
  String toString() => 'DeactivationBlocked(#$navigationId $uri)';
}

/// A navigation call finished. Always the last event of its id.
///
/// Not emitted when the navigation throws — a redirect loop leaves its id
/// open on purpose, because the navigation did not end, it failed.
final class NavigationEnded extends NavigationEvent {
  /// Reports how a navigation turned out.
  const NavigationEnded({
    required super.navigationId,
    required super.timestamp,
    required this.outcome,
    required this.uri,
    required this.duration,
  });

  /// What happened.
  final NavigationOutcome outcome;

  /// Where the router ended up.
  final Uri uri;

  /// How long the whole call took, guards included.
  final Duration duration;

  @override
  String toString() =>
      'NavigationEnded(#$navigationId ${outcome.name} $uri '
      'in ${duration.inMicroseconds}us)';
}

/// The router's stack changed and the outlets are about to rebuild.
final class StackChanged extends RouterEvent {
  /// Reports a new [revision] of the stack.
  const StackChanged({
    required super.timestamp,
    required this.navigationId,
    required this.revision,
    required this.uri,
  });

  /// The navigation that caused the change, or `null` when a [Navigator]
  /// removed a page on its own — a system back, a swipe back, or a `pop`.
  final int? navigationId;

  /// The router's revision after the change. Matches `RouterService.revision`.
  final int revision;

  /// Where the router is now.
  final Uri uri;

  @override
  String toString() =>
      'StackChanged(${navigationId == null ? 'pop' : '#$navigationId'} '
      'rev $revision: $uri)';
}

/// Watches what the router does.
///
/// The router reports through this hook and nothing else — no static event
/// bus, no debug-only back door — so analytics, a screen-time logger and the
/// DevTools extension are all just observers passed to `RouterModule`:
///
/// ```dart
/// RouterModule(routes: appRoutes, observers: [AnalyticsObserver()], ...)
/// ```
///
/// [onEvent] runs synchronously inside the navigation pipeline. Keep it
/// cheap, and do not navigate from it. An observer that throws is reported
/// through [FlutterError.reportError] and the navigation carries on: a
/// broken logger must not break the app's navigation.
abstract class RouterObserver {
  /// Allows `const` observers.
  const RouterObserver();

  /// Called for every [RouterEvent], in the order the router emits them.
  void onEvent(RouterEvent event);
}

/// A [RouterObserver] that prints every event with [debugPrint].
///
/// The quickest way to see what the router is doing:
///
/// ```dart
/// RouterModule(routes: appRoutes, observers: const [LoggingRouterObserver()])
/// ```
class LoggingRouterObserver extends RouterObserver {
  /// Creates a logging observer.
  const LoggingRouterObserver({this.prefix = 'modulith_router'});

  /// Written in front of every line, to find them in a busy log.
  final String prefix;

  @override
  void onEvent(RouterEvent event) => debugPrint('[$prefix] $event');
}
