import 'package:flutter/material.dart';
import 'package:modulith/modulith.dart';

import '../model/route_definition.dart';
import '../runtime/activation.dart';
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
/// [ChildRouting.outlet] and its matched children appear there — the
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

  /// Its own, because a [HeroController] cannot be shared between
  /// navigators and nested outlets each have one.
  late final HeroController _heroController =
      MaterialApp.createMaterialHeroController();

  RouterService? _service;
  int? _depth;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = RouterScope.of(context).service;
    final depth = OutletScope.maybeOf(context)?.depth ?? 0;
    if (identical(service, _service) && depth == _depth) return;

    _service?.unregisterOutlet(this);
    _service = service;
    _depth = depth;
    if (widget.mode == OutletMode.stack) {
      service.registerOutlet(this, _navigatorKey, depth);
    }
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

  /// An outlet with nothing in it means the route table has a hole: the
  /// shell matched but none of its children did. Blank screens are a bad way
  /// to learn that, so say it in debug, and name the route to fix.
  ///
  /// Legitimately-empty outlets (an unselected detail pane) pass `empty` and
  /// never reach here.
  bool _reportEmptyOutlet(RouterService service, OutletScope outlet) {
    final frameIndex = outlet.frameIndex;
    final segmentIndex = outlet.segmentIndex;
    if (frameIndex == null || segmentIndex == null || segmentIndex == 0) {
      return true;
    }
    if (frameIndex >= service.frames.length) return true;

    final frame = service.frames[frameIndex];
    if (segmentIndex > frame.segments.length) return true;
    final parent = frame.segments[segmentIndex - 1].last.match.route;

    throw FlutterError.fromParts([
      ErrorSummary('No child route matched ${frame.uri} in this RoutingView.'),
      ErrorDescription(
        '"${parent.debugPath}" declares childRouting: ChildRouting.outlet and '
        'matched, but none of its children matched the rest of the URL, so '
        'the outlet has nothing to render.',
      ),
      ErrorHint(
        'Declare what "${frame.uri}" should show. Either an index child that '
        'renders at the parent\'s own URL:\n'
        "  ModuleRoute(path: '', builder: (route) => TodosModule())\n"
        'or a redirect to a real child, which changes the URL too:\n'
        "  RedirectRoute(path: '', to: '/todos')\n"
        'Pass `empty:` to RoutingView if an empty outlet is intended here.',
      ),
    ]);
  }

  /// What this outlet renders: segment 0 of every frame at the root, one
  /// segment of one frame when nested.
  List<_OutletSlot> _slotsFor(RouterService service, OutletScope outlet) {
    final frames = service.frames;
    final slots = <_OutletSlot>[];

    if (outlet.frameIndex == null) {
      for (var index = 0; index < frames.length; index++) {
        final frame = frames[index];
        if (frame.isError) {
          slots.add(_OutletSlot(index, frame, 0, null));
          continue;
        }
        for (final activation in frame.segments.first) {
          slots.add(_OutletSlot(index, frame, 0, activation));
        }
      }
      return slots;
    }

    final frameIndex = outlet.frameIndex!;
    final segmentIndex = outlet.segmentIndex;
    if (segmentIndex == null || frameIndex >= frames.length) return slots;

    final frame = frames[frameIndex];
    if (segmentIndex >= frame.segments.length) return slots;
    for (final activation in frame.segments[segmentIndex]) {
      slots.add(_OutletSlot(frameIndex, frame, segmentIndex, activation));
    }
    return slots;
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
        frameIndex: slot.frameIndex,
        // Only a route that opens an outlet has children to hand down; for
        // anyone else this publishes "no slot here", so a misplaced
        // RoutingView renders empty instead of looping on its ancestors.
        segmentIndex: activation.opensOutlet ? slot.segmentIndex + 1 : null,
        depth: depth + 1,
        child: child,
      ),
    );
  }
}

class _OutletSlot {
  const _OutletSlot(
    this.frameIndex,
    this.frame,
    this.segmentIndex,
    this.activation,
  );

  final int frameIndex;
  final RouteFrame frame;
  final int segmentIndex;

  /// `null` for the error page of a frame that matched nothing.
  final RouteActivation? activation;
}
