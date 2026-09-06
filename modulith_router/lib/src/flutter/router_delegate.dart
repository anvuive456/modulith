import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import '../model/router_state.dart';
import '../runtime/router_service.dart';
import 'router_scope.dart';
import 'routing_view.dart';

/// The Navigation 2.0 delegate: it owns nothing but the plumbing.
///
/// Matching, guards and the stack live in [RouterService]; this class turns
/// them into what the `Router` widget expects — a configuration to report to
/// the platform, a hook for incoming route information, and a widget tree.
class ModulithRouterDelegate extends RouterDelegate<RouterState>
    with ChangeNotifier {
  /// Creates the delegate for [service].
  ModulithRouterDelegate({required this.service, this.splash});

  /// The router this delegate renders.
  final RouterService service;

  /// Shown for the frame or two before the first navigation resolves — the
  /// initial route still has to go through matching and guards.
  final Widget? splash;

  @override
  RouterState? get currentConfiguration => service.currentState;

  @override
  Future<void> setNewRoutePath(RouterState configuration) =>
      service.applyPlatformState(configuration);

  @override
  Future<void> setRestoredRoutePath(RouterState configuration) =>
      setNewRoutePath(configuration);

  @override
  Future<bool> popRoute() => service.popRoute();

  @override
  Widget build(BuildContext context) {
    if (service.frames.isEmpty) return splash ?? const SizedBox.shrink();
    return RouterScope(
      service: service,
      revision: service.revision,
      child: const OutletScope.root(child: RoutingView()),
    );
  }

  /// Tells the `Router` that the stack changed.
  @internal
  void notify() => notifyListeners();
}
