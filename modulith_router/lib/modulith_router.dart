/// Navigation 2.0 routing for modulith.
///
/// A route table of [ModuleRoute]s, each mounting a `Module` whose scope
/// nests under the route above it, rendered through [RoutingView] outlets.
/// The router is itself a module ([RouterModule]) and its API is an ordinary
/// `Service` ([RouterService]) — there is no global navigator singleton.
///
/// An app that routes depends on this package *and* on
/// `package:modulith/modulith.dart`, and imports both: this library exports
/// the routing API only. The dependency only ever points this way — modulith
/// knows nothing about routing, and an app that doesn't route never pulls
/// this package in.
library;

export 'src/flutter/context_extensions.dart';
export 'src/flutter/route_information_parser.dart';
export 'src/flutter/router_delegate.dart';
export 'src/flutter/router_module.dart';
export 'src/flutter/router_scope.dart';
export 'src/flutter/routing_view.dart';
export 'src/flutter/no_transition_page.dart';
export 'src/model/route_definition.dart';
export 'src/model/route_error.dart';
export 'src/model/route_match.dart';
export 'src/model/route_matcher.dart';
export 'src/model/route_pattern.dart';
export 'src/model/router_state.dart';
export 'src/runtime/activated_route.dart';
export 'src/runtime/activation.dart';
export 'src/runtime/guards.dart';
export 'src/runtime/navigation_result.dart';
export 'src/runtime/router_controller.dart';
export 'src/runtime/router_service.dart';
