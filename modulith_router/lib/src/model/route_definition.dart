import 'package:flutter/widgets.dart';
import 'package:modulith/modulith.dart';

import '../runtime/activated_route.dart';
import '../runtime/guards.dart';

/// Builds the module a [ModuleRoute] mounts.
///
/// Must return a **fresh** instance every call: a `Module` instance backs
/// exactly one live scope. Take what the screen needs off [route] here —
/// that is how route data reaches controllers, no router-specific injection
/// involved.
typedef ModuleRouteBuilder = Module Function(ActivatedRoute route);

/// Builds the widget a [ViewRoute] renders.
typedef ViewRouteBuilder =
    Widget Function(BuildContext context, ActivatedRoute route);

/// Wraps a route's content in a [Page], for custom transitions or
/// `fullscreenDialog` presentation.
typedef RoutePageBuilder =
    Page<Object?> Function(
      BuildContext context,
      ActivatedRoute route,
      Widget child,
    );

/// Computes where a [RedirectRoute] sends the navigation.
typedef RouteRedirectBuilder = String Function(RedirectContext context);

/// What a [RouteRedirectBuilder] gets to decide with.
@immutable
class RedirectContext {
  /// Creates a redirect context. Built by the router.
  const RedirectContext({required this.uri, required this.pathParams});

  /// The URL that matched the redirect route.
  final Uri uri;

  /// Path parameters captured on the way to it, so a redirect can forward
  /// them: `/u/:id` → `/users/${context.pathParams['id']}`.
  final Map<String, String> pathParams;
}

/// Where a route's children are rendered.
enum ChildRouting {
  /// Children become pages **on the same [Navigator]** as this route: going
  /// from `/users` to `/users/42` pushes the detail over the list. The usual
  /// case.
  stack,

  /// Children are rendered into a `RoutingView` inside this route's own
  /// view. This is what makes a route a shell/layout: a `Scaffold` with a
  /// bottom bar around an outlet, a master-detail split, a tab host.
  outlet,

  /// Children are grouped into persistent navigation branches rendered by a
  /// `RoutingView`. Each branch owns an independent [Navigator] stack.
  branches,
}

/// When navigation branches create their initial route.
enum BranchInitialization {
  /// Create a branch when it first becomes active.
  lazy,

  /// Create every branch as soon as its host route is activated.
  eager,
}

/// One persistent navigation branch hosted by a route using
/// [ChildRouting.branches].
@immutable
class RouteBranch {
  /// Declares a named branch and its initial location.
  const RouteBranch({
    required this.name,
    required this.initialLocation,
    required this.routes,
  }) : assert(name != ''),
       assert(routes.length > 0);

  /// Stable identifier used by [RouterService.switchBranch].
  final String name;

  /// Location used the first time this branch is initialized.
  final String initialLocation;

  /// Routes owned by this branch.
  final List<RouteDefinition> routes;
}

/// Whether an activation survives a navigation that lands on the same route
/// with different parameters.
enum RouteReuse {
  /// Same route and same path parameters → keep the module and its scope;
  /// different parameters → tear it down and build a new one. Matches what
  /// Flutter developers expect: `/users/1` and `/users/2` are two screens.
  byPathParams,

  /// Always keep the module alive and push the new values into
  /// [ActivatedRoute.params]. Angular's semantics; good for master-detail
  /// and tab hosts.
  always,

  /// Never reuse, not even for the exact same URL.
  never,
}

/// One node of the route table.
sealed class RouteDefinition {
  /// Declares a route at [path], optionally with [children].
  const RouteDefinition({
    required this.path,
    this.name,
    this.children = const [],
    this.guards = const [],
  });

  /// The path this route consumes, relative to its parent: `users`,
  /// `users/:id`, `**`, or `''` for a pathless (shell) route.
  final String path;

  /// A stable name for reverse routing (`goNamed`, `uriFor`), unique in the
  /// route table.
  final String? name;

  /// Nested routes, rendered per [childRouting].
  final List<RouteDefinition> children;

  /// Checks that run before this route is activated, after its ancestors'.
  final List<RouteGuard> guards;

  /// Where [children] are rendered.
  ChildRouting get childRouting;

  /// Whether an activation of this route survives a parameter change.
  RouteReuse get reuse;

  /// Optional custom [Page] wrapper.
  RoutePageBuilder? get pageBuilder;
}

/// A route that mounts a [Module], with its own controllers, services and
/// scope nested under the route above it.
final class ModuleRoute extends RouteDefinition {
  /// Declares a module route.
  const ModuleRoute({
    required super.path,
    required this.builder,
    super.name,
    super.children,
    super.guards,
    this.childRouting = ChildRouting.stack,
    this.reuse = RouteReuse.byPathParams,
    this.pageBuilder,
    this.branches = const [],
    this.branchInitialization = BranchInitialization.lazy,
  }) : assert(
         branches.length == 0 || children.length == 0,
         'A ModuleRoute cannot declare both children and branches.',
       ),
       assert(
         branches.length == 0 || childRouting == ChildRouting.branches,
         'A ModuleRoute with branches must use ChildRouting.branches.',
       ),
       assert(
         childRouting != ChildRouting.branches || branches.length > 0,
         'A ModuleRoute with ChildRouting.branches must declare branches.',
       );

  /// Creates the module for one activation.
  final ModuleRouteBuilder builder;

  @override
  final ChildRouting childRouting;

  @override
  final RouteReuse reuse;

  @override
  final RoutePageBuilder? pageBuilder;

  /// Persistent navigation branches hosted by this route.
  final List<RouteBranch> branches;

  /// When [branches] create their initial routes.
  final BranchInitialization branchInitialization;
}

/// A route that renders a plain widget in the scope of the route above it —
/// for screens that need no controllers or services of their own.
final class ViewRoute extends RouteDefinition {
  /// Declares a view route.
  const ViewRoute({
    required super.path,
    required this.builder,
    super.name,
    super.children,
    super.guards,
    this.childRouting = ChildRouting.stack,
    this.reuse = RouteReuse.byPathParams,
    this.pageBuilder,
  }) : assert(
         childRouting != ChildRouting.branches,
         'Only a ModuleRoute can host navigation branches.',
       );

  /// Builds the widget for one activation.
  final ViewRouteBuilder builder;

  @override
  final ChildRouting childRouting;

  @override
  final RouteReuse reuse;

  @override
  final RoutePageBuilder? pageBuilder;
}

/// A route that sends navigation somewhere else instead of rendering.
final class RedirectRoute extends RouteDefinition {
  /// Redirects to a fixed location.
  const RedirectRoute({
    required super.path,
    required String this._to,
    super.name,
  }) : redirect = null;

  /// Redirects to a location computed from the URL that matched.
  const RedirectRoute.builder({
    required super.path,
    required RouteRedirectBuilder this.redirect,
    super.name,
  }) : _to = null;

  final String? _to;

  /// Computes the target, or `null` when the target is fixed.
  final RouteRedirectBuilder? redirect;

  /// Where this route sends [context].
  String target(RedirectContext context) => _to ?? redirect!(context);

  @override
  ChildRouting get childRouting => ChildRouting.stack;

  @override
  RouteReuse get reuse => RouteReuse.never;

  @override
  RoutePageBuilder? get pageBuilder => null;
}
