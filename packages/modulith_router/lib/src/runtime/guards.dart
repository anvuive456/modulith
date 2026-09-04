import 'dart:async';

import 'package:modulith/modulith.dart';

import '../model/route_match.dart';

/// What a [RouteGuard] decided.
sealed class GuardResult {
  /// Allows subclassing inside this library.
  const GuardResult();

  /// Let the navigation continue.
  static const GuardResult allow = AllowGuardResult();

  /// Stop the navigation and stay where we are.
  static const GuardResult block = BlockGuardResult();

  /// Stop the navigation and go to [location] instead.
  const factory GuardResult.redirect(String location) = RedirectGuardResult;
}

/// The result of a guard that lets navigation through.
final class AllowGuardResult extends GuardResult {
  /// Prefer [GuardResult.allow].
  const AllowGuardResult();
}

/// The result of a guard that refuses navigation outright.
final class BlockGuardResult extends GuardResult {
  /// Prefer [GuardResult.block].
  const BlockGuardResult();
}

/// The result of a guard that sends navigation somewhere else.
final class RedirectGuardResult extends GuardResult {
  /// Redirects to [location].
  const RedirectGuardResult(this.location);

  /// Where to go instead, resolved against the target URL.
  final String location;
}

/// What a guard is given to make its decision.
class GuardContext {
  /// Creates a guard context. Built by the router.
  GuardContext({
    required this.uri,
    required this.matches,
    required this.match,
    required this.extra,
    required S Function<S extends Service>({String? name}) resolve,
  }) : _resolver = resolve;

  /// The URL being navigated to.
  final Uri uri;

  /// The whole matched chain, root first.
  final List<RouteMatch> matches;

  /// The route this guard is declared on.
  final RouteMatch match;

  /// The `extra` passed to the navigation call.
  final Object? extra;

  final S Function<S extends Service>({String? name}) _resolver;

  /// Resolves a service to decide with.
  ///
  /// Resolution starts at the scope of the module that declares the router
  /// (so everything an ancestor module provides is reachable). The target
  /// route's own module is *not* mounted yet while a guard runs, so its
  /// services cannot be resolved here — same rule as Angular, where a guard
  /// runs in the parent route's injector.
  S getService<S extends Service>({String? name}) => _resolver<S>(name: name);

  /// The path parameters captured for [match].
  Map<String, String> get pathParams => match.pathParams;
}

/// A check that runs before a route is activated.
///
/// Guards run root-first, global guards before route guards, and the first
/// non-allow result wins.
abstract class RouteGuard {
  /// Allows `const` guards.
  const RouteGuard();

  /// Decides whether [context] may be activated.
  FutureOr<GuardResult> canActivate(GuardContext context);
}

/// A callback asked before the screen that registered it is navigated away
/// from — the "unsaved changes" hook.
///
/// Returning `false` blocks the navigation. Register it from the controller
/// that owns the state in question, and remove it when that controller is
/// disposed, so its lifetime is exactly the screen's lifetime.
typedef DeactivationGuard = FutureOr<bool> Function();
