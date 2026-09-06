import 'package:flutter/material.dart';
import 'package:modulith/modulith.dart';

import '../model/route_definition.dart';
import '../runtime/activation.dart';
import '../runtime/navigation_tree.dart';
import '../runtime/router_service.dart';
import 'router_scope.dart';

/// How a [RoutingView] presents the routes it renders.
enum OutletMode {
  /// A page-based [Navigator]: the matched chain becomes a stack, with back
  /// gestures, transitions and its own history.
  stack,

  /// Just the current route's widget, swapped in place. For a tab body or a
  /// detail pane that has no history of its own.
  replace,
}

/// The routing outlet: where a route's children are rendered.
///
/// Put one in the view of a route declared with
/// [ChildRouting.outlet] or [ChildRouting.branches] and its matched children
/// appear there — the
/// equivalent of Angular's `<router-outlet>`, except that in
/// [OutletMode.stack] the outlet is a real [Navigator], so the children form
/// a navigable stack rather than a single swapped widget.
///
/// A route whose children use the default [ChildRouting.stack] needs no
/// outlet at all: its children are pushed onto the same navigator it lives
/// on.
class RoutingView extends StatefulWidget {
  /// Creates an outlet.
  const RoutingView({
    super.key,
    this.mode = OutletMode.stack,
    this.empty,
    this.observers = const [],
  });

  /// Whether this outlet keeps a stack or swaps a single child.
  final OutletMode mode;

  /// Shown when no child route is active — an empty detail pane, say.
  /// Without it, an empty outlet renders nothing.
  final WidgetBuilder? empty;

  /// Observers for this outlet's [Navigator], in [OutletMode.stack].
  final List<NavigatorObserver> observers;

  @override
  State<RoutingView> createState() => _RoutingViewState();
}

class _RoutingViewState extends State<RoutingView> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final Map<String, GlobalKey<NavigatorState>> _branchNavigatorKeys = {};
  final Map<String, HeroController> _branchHeroControllers = {};

  /// Its own, because a [HeroController] cannot be shared between
  /// navigators and nested outlets each have one.
  late final HeroController _heroController =
      MaterialApp.createMaterialHeroController();

  RouterService? _service;
  int? _depth;
  int? _ownerActivationId;
  bool _isRoot = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = RouterScope.of(context).service;
    final outlet = OutletScope.maybeOf(context);
    final depth = outlet?.depth ?? 0;
    final ownerActivationId = outlet?.ownerActivationId;
    final isRoot = outlet?.isRoot ?? false;
    if (identical(service, _service) &&
        depth == _depth &&
        ownerActivationId == _ownerActivationId &&
        isRoot == _isRoot) {
      return;
    }

    _service?.unregisterOutlet(this);
    _service = service;
    _depth = depth;
    _ownerActivationId = ownerActivationId;
    _isRoot = isRoot;
  }

  @override
  void dispose() {
    _service?.unregisterOutlet(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = RouterScope.of(context);
    final outlet = OutletScope.maybeOf(context);
    if (outlet == null) {
      throw FlutterError(
        'RoutingView must be used below the Router created by RouterModule.',
      );
    }

    final slots = _slotsFor(scope.service, outlet);
    if (slots.isEmpty) {
      final fallback = widget.empty;
      if (fallback != null) return fallback(context);
      assert(_reportEmptyOutlet(scope.service, outlet));
      return const SizedBox.shrink();
    }

    if (widget.mode == OutletMode.replace) {
      return _contentFor(context, scope.service, slots.last, outlet.depth);
    }

    final ownerId = outlet.ownerActivationId;
    final branches = ownerId == null
        ? null
        : scope.service.branchesForOutlet(ownerId);
    if (branches != null) {
      return _buildBranches(context, scope.service, branches, outlet.depth);
    }

    _registerNavigator(scope.service, _navigatorKey, ownerId);

    return HeroControllerScope(
      controller: _heroController,
      child: Navigator(
        key: _navigatorKey,
        observers: widget.observers,
        onDidRemovePage: scope.service.handlePageRemoved,
        pages: [
          for (final slot in slots)
            _pageFor(context, scope.service, slot, outlet.depth),
        ],
      ),
    );
  }

  Widget _buildBranches(
    BuildContext context,
    RouterService service,
    NavigationBranchOutlet outlet,
    int depth,
  ) {
    final activeKey = _branchNavigatorKeys.putIfAbsent(
      outlet.activeBranch,
      GlobalKey<NavigatorState>.new,
    );
    _registerNavigator(service, activeKey, _ownerActivationId);

    return IndexedStack(
      index: outlet.names.indexOf(outlet.activeBranch),
      children: [
        for (final name in outlet.names)
          if (outlet.navigators[name] case final navigator?)
            HeroControllerScope(
              controller: _branchHeroControllers.putIfAbsent(
                name,
                MaterialApp.createMaterialHeroController,
              ),
              child: Navigator(
                key: _branchNavigatorKeys.putIfAbsent(
                  name,
                  GlobalKey<NavigatorState>.new,
                ),
                observers: name == outlet.activeBranch
                    ? widget.observers
                    : const [],
                onDidRemovePage: service.handlePageRemoved,
                pages: [
                  for (final page in navigator.pages)
                    _pageFor(context, service, _OutletSlot(page), depth),
                ],
              ),
            )
          else
            const SizedBox.shrink(),
      ],
    );
  }

  void _registerNavigator(
    RouterService service,
    GlobalKey<NavigatorState> key,
    int? ownerActivationId,
  ) {
    service.registerOutlet(this, key, ownerActivationId);
  }

  /// An outlet with nothing in it means the route table has a hole: the
  /// shell matched but none of its children did. Blank screens are a bad way
  /// to learn that, so say it in debug, and name the route to fix.
  ///
  /// Legitimately-empty outlets (an unselected detail pane) pass `empty` and
  /// never reach here.
  bool _reportEmptyOutlet(RouterService service, OutletScope outlet) {
    final ownerId = outlet.ownerActivationId;
    if (outlet.isRoot || ownerId == null) return true;
    final parent = service.activationForOutlet(ownerId)?.match.route;
    if (parent == null) return true;

    throw FlutterError.fromParts([
      ErrorSummary(
        'No child route matched ${service.currentUri} in this RoutingView.',
      ),
      ErrorDescription(
        '"${parent.debugPath}" declares childRouting: ChildRouting.outlet and '
        'matched, but none of its children matched the rest of the URL, so '
        'the outlet has nothing to render.',
      ),
      ErrorHint(
        'Declare what "${service.currentUri}" should show. Either an index '
        'child that '
        'renders at the parent\'s own URL:\n'
        "  ModuleRoute(path: '', builder: (route) => TodosModule())\n"
        'or a redirect to a real child, which changes the URL too:\n'
        "  RedirectRoute(path: '', to: '/todos')\n"
        'Pass `empty:` to RoutingView if an empty outlet is intended here.',
      ),
    ]);
  }

  /// What this outlet renders, resolved from the runtime navigation tree.
  List<_OutletSlot> _slotsFor(RouterService service, OutletScope outlet) {
    if (!outlet.isRoot && outlet.ownerActivationId == null) return const [];
    return [
      for (final page in service.pagesForOutlet(outlet.ownerActivationId))
        _OutletSlot(page),
    ];
  }

  Page<Object?> _pageFor(
    BuildContext context,
    RouterService service,
    _OutletSlot slot,
    int depth,
  ) {
    final activation = slot.activation;
    if (activation == null) {
      return MaterialPage<Object?>(
        key: ValueKey('modulith_router_error#${slot.frame.id}'),
        name: slot.frame.uri.toString(),
        child: service.buildError(context, slot.frame.uri),
      );
    }

    final content = _contentFor(context, service, slot, depth);
    final builder = activation.match.definition.pageBuilder;
    if (builder != null) return builder(context, activation.route, content);

    return MaterialPage<Object?>(
      key: activation.pageKey,
      name: activation.match.matchedPath,
      child: content,
    );
  }

  Widget _contentFor(
    BuildContext context,
    RouterService service,
    _OutletSlot slot,
    int depth,
  ) {
    final activation = slot.activation;
    if (activation == null) return service.buildError(context, slot.frame.uri);

    final definition = activation.match.definition;
    final child = switch (definition) {
      // The module instance comes from the activation, never from build:
      // handing ModuleWidget a new instance would dispose the scope.
      ModuleRoute() => ModuleWidget(module: activation.module!),
      ViewRoute(:final builder) => Builder(
        builder: (context) => builder(context, activation.route),
      ),
      RedirectRoute() => const SizedBox.shrink(),
    };

    return ActivatedRouteScope(
      route: activation.route,
      child: OutletScope(
        ownerActivationId: activation.opensNavigationBoundary
            ? activation.id
            : null,
        depth: depth + 1,
        child: child,
      ),
    );
  }
}

class _OutletSlot {
  const _OutletSlot(this.page);

  final NavigationPage page;

  RouteFrame get frame => page.frame;

  /// `null` for an error page whose frame matched nothing.
  RouteActivation? get activation => page.activation;
}
