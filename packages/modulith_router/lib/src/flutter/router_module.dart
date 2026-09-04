import 'package:flutter/widgets.dart';
import 'package:modulith/modulith.dart';

import '../model/route_definition.dart';
import '../model/route_error.dart';
import '../model/router_state.dart';
import '../runtime/guards.dart';
import '../runtime/router_controller.dart';
import '../runtime/router_service.dart';

/// Builds the app around the router's [RouterConfig] — normally
/// `MaterialApp.router(routerConfig: routerConfig, ...)`.
///
/// The app builds its own `MaterialApp`, so themes, localizations and
/// builders stay where they belong instead of being proxied through the
/// router.
typedef RouterAppBuilder =
    Widget Function(
      BuildContext context,
      RouterConfig<RouterState> routerConfig,
    );

/// The router as a module.
///
/// Mount it as a child of the app module:
///
/// ```dart
/// class AppModule extends Module {
///   @override
///   List<Module> get children => [
///     RouterModule(
///       routes: appRoutes,
///       appBuilder: (context, routerConfig) =>
///           MaterialApp.router(routerConfig: routerConfig),
///     ),
///   ];
///
///   @override
///   Widget get view => const ChildModuleView<RouterModule>();
/// }
/// ```
///
/// Scopes then nest the way routes do: `AppModule` → `RouterModule` → each
/// routed module, so a screen still resolves services declared at the app
/// level.
class RouterModule extends Module {
  /// Declares a router over [routes].
  RouterModule({
    required this.routes,
    required this.appBuilder,
    this.initialLocation = '/',
    this.guards = const [],
    this.errorBuilder,
    this.routeInformationProvider,
    this.backButtonDispatcher,
    this.splash,
  });

  /// The route table.
  final List<RouteDefinition> routes;

  /// Builds the `MaterialApp.router` (or `WidgetsApp.router`) around the
  /// router config.
  final RouterAppBuilder appBuilder;

  /// Where to start when the platform has no deep link of its own.
  final String initialLocation;

  /// Guards that run before every navigation, ahead of any route's own.
  final List<RouteGuard> guards;

  /// What to show for a URL nothing matches. A `**` route takes precedence.
  final RouteErrorBuilder? errorBuilder;

  /// Overrides where route information comes from. Meant for tests, which
  /// want to drive the router without touching the platform.
  final RouteInformationProvider? routeInformationProvider;

  /// Overrides how the system back button reaches the router.
  final BackButtonDispatcher? backButtonDispatcher;

  /// Shown until the first navigation clears its guards.
  final Widget? splash;

  @override
  List<Provider<Service>> get services => [
    Provider<RouterService>.singleton(
      create: () => RouterService(
        routes: routes,
        initialLocation: initialLocation,
        guards: guards,
        errorBuilder: errorBuilder,
        routeInformationProvider: routeInformationProvider,
        backButtonDispatcher: backButtonDispatcher,
        splash: splash,
      ),
    ),
  ];

  @override
  List<Provider<Controller>> get controllers => [
    Provider<RouterController>.singleton(create: RouterController.new),
  ];

  @override
  Widget get view => RouterAppView(appBuilder: appBuilder);
}

/// The view of a [RouterModule]: resolves the router and hands its config to
/// the app builder.
class RouterAppView extends ModularWidget {
  /// Creates the router's view.
  const RouterAppView({super.key, required this.appBuilder});

  /// Builds the app around the router config.
  final RouterAppBuilder appBuilder;

  @override
  Widget build(ModuleContext context) =>
      appBuilder(context, context.getService<RouterService>().config);
}
