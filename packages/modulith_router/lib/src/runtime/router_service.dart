import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:modulith/modulith.dart';

import '../flutter/route_information_parser.dart';
import '../flutter/router_delegate.dart';
import '../model/route_definition.dart';
import '../model/route_error.dart';
import '../model/route_match.dart';
import '../model/route_matcher.dart';
import '../model/router_state.dart';
import 'activated_route.dart';
import 'activation.dart';
import 'guards.dart';
import 'navigation_result.dart';

enum _NavigationKind { go, push, replace }

/// The router itself: route table, navigation pipeline, and the
/// [RouterConfig] the app hands to `MaterialApp.router`.
///
/// It is an ordinary `Service`, so it is resolved through the module scope
/// (`injectService<RouterService>()` from a controller, `context.router`
/// from a widget) and can be replaced with a fake in tests — there is no
/// global router singleton to reach around.
///
/// Reactive state lives on `RouterController`, not here: a `Service` must
/// not own `Signal`s.
class RouterService extends Service {
  /// Creates the router for [routes].
  ///
  /// [initialLocation] is used only when the platform has no deep link of
  /// its own. [guards] run before the guards of every matched route.
  RouterService({
    required List<RouteDefinition> routes,
    String initialLocation = '/',
    List<RouteGuard> guards = const [],
    RouteErrorBuilder? errorBuilder,
    RouteInformationProvider? routeInformationProvider,
    BackButtonDispatcher? backButtonDispatcher,
    Widget? splash,
    int maxRedirects = 5,
  }) : _routeTable = routes,
       _defaultLocation = initialLocation,
       _globalGuards = guards,
       _notFoundBuilder = errorBuilder,
       _externalProvider = routeInformationProvider,
       _backButton = backButtonDispatcher,
       _splashScreen = splash,
       _redirectLimit = maxRedirects;

  final List<RouteDefinition> _routeTable;
  final String _defaultLocation;
  final List<RouteGuard> _globalGuards;
  final RouteErrorBuilder? _notFoundBuilder;
  final RouteInformationProvider? _externalProvider;
  final BackButtonDispatcher? _backButton;
  final Widget? _splashScreen;
  final int _redirectLimit;

  final _RouterChanges _changes = _RouterChanges();
  final List<RouteFrame> _frames = [];
  final List<_OutletRegistration> _outlets = [];
  final List<DeactivationGuard> _deactivationGuards = [];

  late final RouteMatcher _matcher;
  late final ModulithRouterDelegate _delegate;

  /// What the app passes to `MaterialApp.router`.
  late final RouterConfig<RouterState> config;

  int _revision = 0;
  int _generation = 0;
  int _nextActivationId = 0;
  int _nextFrameId = 0;
  bool _isNavigating = false;
  Object? _pendingPopResult;

  @override
  void init() {
    _matcher = RouteMatcher(_routeTable);
    _delegate = ModulithRouterDelegate(service: this, splash: _splashScreen);

    final provider =
        _externalProvider ??
        PlatformRouteInformationProvider(
          initialRouteInformation: RouteInformation(uri: _resolveInitialUri()),
        );

    config = RouterConfig<RouterState>(
      routeInformationProvider: provider,
      routeInformationParser: const ModulithRouteInformationParser(),
      routerDelegate: _delegate,
      backButtonDispatcher: _backButton ?? RootBackButtonDispatcher(),
    );

    addDisposeCallback(() {
      for (final frame in _frames) {
        frame.completer?.complete(null);
      }
      _frames.clear();
      _delegate.dispose();
      if (_externalProvider == null) {
        (provider as PlatformRouteInformationProvider).dispose();
      }
      _changes.dispose();
    });
  }

  // ---------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------

  /// The live stack, oldest frame first. Read-only.
  List<RouteFrame> get frames => _frames;

  /// Bumped on every change to [frames]; outlets rebuild on it.
  int get revision => _revision;

  /// The compiled route table.
  RouteMatcher get matcher => _matcher;

  /// The configuration reported to the platform, or `null` before the first
  /// navigation resolves.
  RouterState? get currentState => _frames.isEmpty
      ? null
      : RouterState([
          for (final frame in _frames)
            RouteEntry(uri: frame.uri, extra: frame.extra),
        ]);

  /// Where the router currently is.
  Uri get currentUri =>
      _frames.isEmpty ? Uri.parse(_defaultLocation) : _frames.last.uri;

  /// The name of the deepest active route, if it has one.
  String? get activeRouteName =>
      _frames.isEmpty ? null : _frames.last.leaf?.match.definition.name;

  /// Whether a navigation is waiting on a guard.
  bool get isNavigating => _isNavigating;

  /// Whether [popRoute] would find something to pop.
  ///
  /// Computed from the router's own model rather than by asking a
  /// [NavigatorState], so it is already correct when listeners are notified,
  /// before any widget has rebuilt.
  bool get canPop {
    var rootPages = 0;
    for (final frame in _frames) {
      rootPages += frame.isError ? 1 : frame.segments.first.length;
      for (var i = 1; i < frame.segments.length; i++) {
        if (frame.segments[i].length > 1) return true;
      }
    }
    return rootPages > 1;
  }

  /// Notified when the stack or [isNavigating] changes.
  Listenable get changes => _changes;

  /// Subscribes [listener] to [changes].
  void addListener(VoidCallback listener) => _changes.addListener(listener);

  /// Unsubscribes [listener] from [changes].
  void removeListener(VoidCallback listener) =>
      _changes.removeListener(listener);

  // ---------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------

  /// Navigates to [location], replacing the whole stack.
  Future<NavigationResult> go(String location, {Object? extra}) => _navigate(
    uri: _resolve(location),
    kind: _NavigationKind.go,
    extra: extra,
  );

  /// [go] for a named route.
  Future<NavigationResult> goNamed(
    String name, {
    Map<String, String> pathParams = const {},
    Map<String, String> queryParameters = const {},
    Object? extra,
  }) => _navigate(
    uri: uriFor(name, pathParams: pathParams, queryParameters: queryParameters),
    kind: _NavigationKind.go,
    extra: extra,
  );

  /// Pushes [location] on top of the current stack and waits for the value
  /// it is popped with.
  ///
  /// Returns `null` when a guard blocked the navigation, or when the screen
  /// was dismissed without a result (system back, swipe).
  Future<T?> push<T extends Object?>(String location, {Object? extra}) async {
    final completer = Completer<Object?>();
    final result = await _navigate(
      uri: _resolve(location),
      kind: _NavigationKind.push,
      extra: extra,
      completer: completer,
    );
    if (!result.isSuccess) {
      if (!completer.isCompleted) completer.complete(null);
      return null;
    }
    return await completer.future as T?;
  }

  /// [push] for a named route.
  Future<T?> pushNamed<T extends Object?>(
    String name, {
    Map<String, String> pathParams = const {},
    Map<String, String> queryParameters = const {},
    Object? extra,
  }) => push<T>(
    uriFor(
      name,
      pathParams: pathParams,
      queryParameters: queryParameters,
    ).toString(),
    extra: extra,
  );

  /// Replaces the topmost frame with [location].
  Future<NavigationResult> replace(String location, {Object? extra}) =>
      _navigate(
        uri: _resolve(location),
        kind: _NavigationKind.replace,
        extra: extra,
      );

  /// Pops the deepest outlet that has something to pop, handing [result] to
  /// whoever is awaiting a [push].
  Future<bool> pop<T extends Object?>([T? result]) {
    _pendingPopResult = result;
    return popRoute();
  }

  /// Re-runs matching and guards on the current URL — what to call after a
  /// login changes what the guards would decide.
  Future<NavigationResult> refresh() =>
      _navigate(uri: currentUri, kind: _NavigationKind.go);

  /// Builds the URL of a named route.
  Uri uriFor(
    String name, {
    Map<String, String> pathParams = const {},
    Map<String, String> queryParameters = const {},
  }) => _matcher.uriFor(
    name,
    pathParams: pathParams,
    queryParameters: queryParameters,
  );

  /// Registers a check asked before any navigation away from the screen that
  /// registered it. Returns the callback that removes it again.
  ///
  /// Call this from the controller that owns the unsaved state, and register
  /// the remover with `addDisposeCallback`, so the guard's lifetime is
  /// exactly that screen's lifetime.
  VoidCallback registerDeactivationGuard(DeactivationGuard guard) {
    _deactivationGuards.add(guard);
    return () => _deactivationGuards.remove(guard);
  }

  // ---------------------------------------------------------------------
  // Wiring used by the delegate and by RoutingView
  // ---------------------------------------------------------------------

  /// Applies a configuration coming from the platform (deep link, browser
  /// back/forward, restoration).
  @internal
  Future<void> applyPlatformState(RouterState state) async {
    if (currentState == state) return;
    await _navigate(
      uri: _normalize(state.uri),
      kind: _NavigationKind.go,
      extra: state.entries.last.extra,
    );
  }

  /// Pops the deepest outlet with more than one page.
  @internal
  Future<bool> popRoute() async {
    final outlets = [..._outlets]..sort((a, b) => b.depth.compareTo(a.depth));
    for (final outlet in outlets) {
      final navigator = outlet.navigatorKey.currentState;
      if (navigator == null || !navigator.canPop()) continue;
      return navigator.maybePop();
    }
    _pendingPopResult = null;
    return false;
  }

  /// Registers an outlet's [Navigator] so back navigation can reach it.
  @internal
  void registerOutlet(
    Object token,
    GlobalKey<NavigatorState> navigatorKey,
    int depth,
  ) {
    _outlets
      ..removeWhere((outlet) => identical(outlet.token, token))
      ..add(_OutletRegistration(token, navigatorKey, depth));
  }

  /// Removes an outlet registered with [registerOutlet].
  @internal
  void unregisterOutlet(Object token) =>
      _outlets.removeWhere((outlet) => identical(outlet.token, token));

  /// Brings the router's model back in line after a [Navigator] removed a
  /// page — a system back, a swipe back, or our own [pop].
  ///
  /// Removing a page removes everything below it in that chain, because a
  /// child route cannot be shown without its parent.
  @internal
  void handlePageRemoved(Page<Object?> page) {
    for (var index = 0; index < _frames.length; index++) {
      final frame = _frames[index];

      if (frame.isError) {
        if (page.key == ValueKey('modulith_router_error#${frame.id}')) {
          _dropFrames(index);
          return;
        }
        continue;
      }

      final position = frame.activations.indexWhere(
        (activation) => activation.pageKey == page.key,
      );
      if (position < 0) continue;

      if (position == 0) {
        _dropFrames(index);
        return;
      }

      final kept = frame.activations.sublist(0, position);
      _completeFrames(_frames.sublist(index + 1));
      _frames.removeRange(index, _frames.length);
      _frames.add(
        RouteFrame(
          id: frame.id,
          uri: Uri.parse(kept.last.match.matchedPath),
          activations: kept,
          extra: frame.extra,
          completer: frame.completer,
        ),
      );
      _pendingPopResult = null;
      _publish();
      return;
    }
  }

  /// The screen shown for a URL nothing matched.
  @internal
  Widget buildError(BuildContext context, Uri uri) {
    final error = RouteError(uri: uri, message: 'No route matches $uri');
    final builder = _notFoundBuilder;
    if (builder != null) return builder(context, error);
    return Material(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            error.message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Pipeline
  // ---------------------------------------------------------------------

  Future<NavigationResult> _navigate({
    required Uri uri,
    required _NavigationKind kind,
    Object? extra,
    Completer<Object?>? completer,
  }) async {
    final generation = ++_generation;
    _setNavigating(true);

    try {
      var target = uri;
      var redirects = 0;
      var redirected = false;
      final visited = <String>[uri.toString()];

      while (true) {
        final matches = _matcher.match(target);

        if (matches == null) {
          _apply(kind, target, const [], extra, completer);
          return NavigationResult(
            redirected
                ? NavigationOutcome.redirected
                : NavigationOutcome.completed,
            target,
          );
        }

        final redirect = _redirectTarget(matches, target);
        if (redirect != null) {
          target = _normalize(target.resolve(redirect));
          redirected = true;
          if (++redirects > _redirectLimit) {
            throw StateError(
              'Redirect loop after $_redirectLimit hops: '
              '${visited.join(' → ')} → $target',
            );
          }
          visited.add(target.toString());
          continue;
        }

        if (!await _runDeactivationGuards()) {
          return NavigationResult(NavigationOutcome.blocked, target);
        }
        if (generation != _generation) {
          return NavigationResult(NavigationOutcome.superseded, target);
        }

        final decision = await _runGuards(matches, target, extra);
        if (generation != _generation) {
          return NavigationResult(NavigationOutcome.superseded, target);
        }

        switch (decision) {
          case AllowGuardResult():
            _apply(kind, target, matches, extra, completer);
            return NavigationResult(
              redirected
                  ? NavigationOutcome.redirected
                  : NavigationOutcome.completed,
              target,
            );
          case BlockGuardResult():
            return NavigationResult(NavigationOutcome.blocked, target);
          case RedirectGuardResult(:final location):
            target = _normalize(target.resolve(location));
            redirected = true;
            if (++redirects > _redirectLimit) {
              throw StateError(
                'Redirect loop after $_redirectLimit hops: '
                '${visited.join(' → ')} → $target',
              );
            }
            visited.add(target.toString());
        }
      }
    } finally {
      if (generation == _generation) _setNavigating(false);
    }
  }

  String? _redirectTarget(List<RouteMatch> matches, Uri uri) {
    final leaf = matches.last;
    final definition = leaf.definition;
    if (definition is! RedirectRoute) return null;
    return definition.target(
      RedirectContext(uri: uri, pathParams: leaf.pathParams),
    );
  }

  Future<bool> _runDeactivationGuards() async {
    for (final guard in [..._deactivationGuards]) {
      if (!await guard()) return false;
    }
    return true;
  }

  Future<GuardResult> _runGuards(
    List<RouteMatch> matches,
    Uri uri,
    Object? extra,
  ) async {
    for (final guard in _globalGuards) {
      final result = await guard.canActivate(
        _guardContext(uri, matches, matches.last, extra),
      );
      if (result is! AllowGuardResult) return result;
    }
    for (final match in matches) {
      for (final guard in match.definition.guards) {
        final result = await guard.canActivate(
          _guardContext(uri, matches, match, extra),
        );
        if (result is! AllowGuardResult) return result;
      }
    }
    return GuardResult.allow;
  }

  GuardContext _guardContext(
    Uri uri,
    List<RouteMatch> matches,
    RouteMatch match,
    Object? extra,
  ) => GuardContext(
    uri: uri,
    matches: matches,
    match: match,
    extra: extra,
    resolve: _resolveService,
  );

  S _resolveService<S extends Service>({String? name}) =>
      injectService<S>(name: name);

  void _apply(
    _NavigationKind kind,
    Uri uri,
    List<RouteMatch> matches,
    Object? extra,
    Completer<Object?>? completer,
  ) {
    switch (kind) {
      case _NavigationKind.go:
        final base = _frames.isEmpty ? null : _frames.first;
        final frame = _buildFrame(
          uri: uri,
          matches: matches,
          previous: base,
          extra: extra,
        );
        _completeFrames(_frames);
        _frames
          ..clear()
          ..add(frame);
      case _NavigationKind.push:
        _frames.add(
          _buildFrame(
            uri: uri,
            matches: matches,
            previous: null,
            extra: extra,
            completer: completer,
          ),
        );
      case _NavigationKind.replace:
        final base = _frames.isEmpty ? null : _frames.removeLast();
        _frames.add(
          _buildFrame(
            uri: uri,
            matches: matches,
            previous: base,
            extra: extra,
            completer: base?.completer,
          ),
        );
    }
    _publish();
  }

  /// Builds the activations for one frame, reusing those of [previous] as
  /// far as the chain agrees and each route's [RouteReuse] allows.
  ///
  /// Reuse stops for good at the first activation that cannot be kept: what
  /// follows it depends on it, so it has to be rebuilt too.
  RouteFrame _buildFrame({
    required Uri uri,
    required List<RouteMatch> matches,
    required RouteFrame? previous,
    Object? extra,
    Completer<Object?>? completer,
  }) {
    final activations = <RouteActivation>[];
    var reusing = previous != null;
    ActivatedRoute? parent;

    for (var index = 0; index < matches.length; index++) {
      final match = matches[index];
      RouteActivation? reused;

      if (reusing && index < previous!.activations.length) {
        final candidate = previous.activations[index];
        if (_canReuse(candidate, match)) {
          reused = candidate;
        } else {
          reusing = false;
        }
      } else {
        reusing = false;
      }

      if (reused != null) {
        reused.update(match: match, uri: uri, extra: extra);
        activations.add(reused);
        parent = reused.route;
        continue;
      }

      final route = ActivatedRoute(
        match: match,
        uri: uri,
        parent: parent,
        extra: extra,
      );
      final definition = match.definition;
      activations.add(
        RouteActivation(
          id: _nextActivationId++,
          match: match,
          route: route,
          module: definition is ModuleRoute ? definition.builder(route) : null,
        ),
      );
      parent = route;
    }

    return RouteFrame(
      id: previous?.id ?? _nextFrameId++,
      uri: uri,
      activations: List.unmodifiable(activations),
      extra: extra,
      completer: completer,
    );
  }

  bool _canReuse(RouteActivation activation, RouteMatch match) {
    if (activation.match.route.id != match.route.id) return false;
    return switch (match.definition.reuse) {
      RouteReuse.never => false,
      RouteReuse.always => true,
      RouteReuse.byPathParams => mapEquals(
        activation.match.pathParams,
        match.pathParams,
      ),
    };
  }

  void _dropFrames(int from) {
    if (from == 0 && _frames.length == 1) return;
    final removed = _frames.sublist(from);
    _frames.removeRange(from, _frames.length);
    _completeFrames(removed);
    _publish();
  }

  /// Completes the futures of every popped frame. Only the topmost one gets
  /// the value handed to [pop]; anything below it was dismissed, not
  /// answered.
  void _completeFrames(List<RouteFrame> removed) {
    for (var index = 0; index < removed.length; index++) {
      final isTop = index == removed.length - 1;
      final completer = removed[index].completer;
      if (completer != null && !completer.isCompleted) {
        completer.complete(isTop ? _pendingPopResult : null);
      }
    }
    _pendingPopResult = null;
  }

  void _setNavigating(bool value) {
    if (_isNavigating == value) return;
    _isNavigating = value;
    _notifyChanges();
  }

  void _publish() {
    _revision++;
    _delegate.notify();
    _notifyChanges();
  }

  void _notifyChanges() {
    if (isDisposed) return;
    // A page removed mid-frame (an exit animation finishing during a build)
    // would otherwise notify listeners while the tree is being built.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!isDisposed) _changes.notify();
      });
      return;
    }
    _changes.notify();
  }

  Uri _resolve(String location) => _normalize(currentUri.resolve(location));

  /// Drops scheme and host: the router only ever deals in path, query and
  /// fragment, so states stay comparable whatever the platform hands over.
  Uri _normalize(Uri uri) => Uri(
    path: uri.path.isEmpty ? '/' : uri.path,
    queryParameters: uri.queryParameters.isEmpty ? null : uri.queryParameters,
    fragment: uri.fragment.isEmpty ? null : uri.fragment,
  );

  Uri _resolveInitialUri() {
    final platformRoute =
        WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    return _normalize(
      Uri.parse(platformRoute == '/' ? _defaultLocation : platformRoute),
    );
  }
}

/// The router's own notifier, kept separate from the delegate's: a change to
/// `isNavigating` should reach a controller without making the `Router`
/// rebuild the whole tree.
class _RouterChanges extends ChangeNotifier {
  void notify() => notifyListeners();
}

class _OutletRegistration {
  _OutletRegistration(this.token, this.navigatorKey, this.depth);

  final Object token;
  final GlobalKey<NavigatorState> navigatorKey;
  final int depth;
}
