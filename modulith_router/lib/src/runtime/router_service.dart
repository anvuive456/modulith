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
import '../devtools/router_inspector.dart';
import '../model/router_state.dart';
import 'activated_route.dart';
import 'activation.dart';
import 'guards.dart';
import 'navigation_tree.dart';
import 'navigation_result.dart';
import 'router_observer.dart';

/// How [RouterService._apply] changes the stack. The public
/// [NavigationKind] an observer sees is wider: it also names the caller a
/// navigation came from.
enum _ApplyKind { go, push, replace }

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
  /// [observers] are told what the pipeline decides, in order.
  RouterService({
    required List<RouteDefinition> routes,
    String initialLocation = '/',
    List<RouteGuard> guards = const [],
    List<RouterObserver> observers = const [],
    RouteErrorBuilder? errorBuilder,
    RouteInformationProvider? routeInformationProvider,
    BackButtonDispatcher? backButtonDispatcher,
    Widget? splash,
    int maxRedirects = 5,
  }) : _routeTable = routes,
       _defaultLocation = initialLocation,
       _globalGuards = guards,
       // Growable: the DevTools inspector adds itself in debug builds.
       _navigationObservers = List.of(observers),
       _notFoundBuilder = errorBuilder,
       _externalProvider = routeInformationProvider,
       _backButton = backButtonDispatcher,
       _splashScreen = splash,
       _redirectLimit = maxRedirects;

  final List<RouteDefinition> _routeTable;
  final String _defaultLocation;
  final List<RouteGuard> _globalGuards;
  final List<RouterObserver> _navigationObservers;
  final RouteErrorBuilder? _notFoundBuilder;
  final RouteInformationProvider? _externalProvider;
  final BackButtonDispatcher? _backButton;
  final Widget? _splashScreen;
  final int _redirectLimit;

  final _RouterChanges _changes = _RouterChanges();
  final NavigationTree _navigation = NavigationTree();
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
  int _nextNavigationId = 0;
  bool _isNavigating = false;
  Object? _pendingPopResult;

  List<RouteFrame> get _frames => _navigation.frames;

  @override
  void init() {
    _matcher = RouteMatcher(_routeTable);
    _delegate = ModulithRouterDelegate(service: this, splash: _splashScreen);

    // Debug builds only: in a release build the assert is stripped, so
    // nothing observes, nothing is logged and no extension is registered.
    assert(() {
      final inspector = RouterInspector.attach(this, _navigation);
      _navigationObservers.add(inspector);
      addDisposeCallback(inspector.detach);
      return true;
    }());

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
        final completer = frame.completer;
        if (completer != null && !completer.isCompleted) {
          completer.complete(null);
        }
      }
      for (final state in _navigation.branchStates.values) {
        for (final history in state.histories.values) {
          _abandonFrames(history);
        }
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

  /// Pages owned by one concrete navigator in the runtime navigation tree.
  @internal
  List<NavigationPage> pagesForOutlet(int? ownerActivationId) =>
      _navigation.pagesFor(ownerActivationId);

  /// Resolves the activation that owns a nested outlet.
  @internal
  RouteActivation? activationForOutlet(int ownerActivationId) =>
      _navigation.activation(ownerActivationId);

  /// Persistent branches rendered by an outlet activation.
  @internal
  NavigationBranchOutlet? branchesForOutlet(int ownerActivationId) =>
      _navigation.branchesFor(ownerActivationId);

  /// Bumped on every change to [frames]; outlets rebuild on it.
  int get revision => _revision;

  /// The compiled route table.
  RouteMatcher get matcher => _matcher;

  /// The guards that run before every navigation. Read by the DevTools
  /// inspector, which shows them above the route table.
  @internal
  List<RouteGuard> get globalGuards => _globalGuards;

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

  /// The active persistent branch, or `null` outside a branch outlet.
  String? get activeBranchName {
    if (_frames.isEmpty) return null;
    final host = _branchHost(_frames.last.matches);
    return host?.branch.name;
  }

  /// Whether a navigation is waiting on a guard.
  bool get isNavigating => _isNavigating;

  /// Whether [popRoute] would find something to pop.
  ///
  /// Computed from the router's own model rather than by asking a
  /// [NavigatorState], so it is already correct when listeners are notified,
  /// before any widget has rebuilt.
  bool get canPop => _navigation.canPop;

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
  Future<NavigationResult> go(String location, {Object? extra}) =>
      _navigate(uri: _resolve(location), kind: _ApplyKind.go, extra: extra);

  /// [go] for a named route.
  Future<NavigationResult> goNamed(
    String name, {
    Map<String, String> pathParams = const {},
    Map<String, String> queryParameters = const {},
    Object? extra,
  }) => _navigate(
    uri: uriFor(name, pathParams: pathParams, queryParameters: queryParameters),
    kind: _ApplyKind.go,
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
      kind: _ApplyKind.push,
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
        kind: _ApplyKind.replace,
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
      _navigate(uri: currentUri, kind: _ApplyKind.go);

  /// Activates a persistent branch, restoring its last stack when available.
  Future<NavigationResult> switchBranch(
    String name, {
    bool reset = false,
  }) async {
    if (_frames.isEmpty) {
      throw StateError('Cannot switch branches before initial navigation.');
    }
    final current = _branchHost(_frames.last.matches);
    if (current == null) {
      throw StateError('The active route is not inside a branch outlet.');
    }
    RouteBranch? branch;
    for (final candidate in current.route.branches) {
      if (candidate.name == name) {
        branch = candidate;
        break;
      }
    }
    if (branch == null) {
      throw ArgumentError.value(name, 'name', 'Unknown navigation branch.');
    }

    final owner = _frames.last.activations[current.index];
    final state = _navigation.branchStates[owner.id];
    if (state == null) {
      throw StateError('The active branch outlet has not been initialized.');
    }

    final navigation = _nextNavigationId++;
    final watch = _isObserved ? (Stopwatch()..start()) : null;
    // Read before the active branch's history is written back: for anything
    // but a reset the two are different branches, and a reset ignores the
    // cache anyway.
    final cached = reset ? null : state.histories[name];
    final initialTarget = _normalize(Uri.parse(branch.initialLocation));
    if (watch != null) {
      _emit(
        NavigationStarted(
          navigationId: navigation,
          timestamp: DateTime.now(),
          kind: NavigationKind.switchBranch,
          from: currentUri,
          to: cached?.last.uri ?? initialTarget,
        ),
      );
    }

    if (!reset && state.activeBranch == name) {
      return _finish(
        navigation,
        watch,
        NavigationResult(NavigationOutcome.completed, currentUri),
      );
    }
    if (!await _runDeactivationGuards()) {
      if (watch != null) {
        _emit(
          DeactivationBlocked(
            navigationId: navigation,
            timestamp: DateTime.now(),
            uri: cached?.last.uri ?? initialTarget,
          ),
        );
      }
      return _finish(
        navigation,
        watch,
        NavigationResult(NavigationOutcome.blocked, currentUri),
      );
    }

    state.histories[state.activeBranch] = List.of(_frames);
    final resolved = cached == null
        ? _matchFollowingRedirects(initialTarget)
        : null;
    if (cached == null && watch != null) {
      _emit(
        RouteMatched(
          navigationId: navigation,
          timestamp: DateTime.now(),
          uri: initialTarget,
          matches: resolved?.matches,
        ),
      );
    }
    if (cached == null && resolved == null) {
      return _finish(
        navigation,
        watch,
        NavigationResult(NavigationOutcome.blocked, initialTarget),
      );
    }
    if (cached == null) {
      _requireBranchMatches(current.route, branch, resolved!.matches);
    }
    final targetMatches = cached?.last.matches ?? resolved!.matches;
    final targetUri = cached?.last.uri ?? resolved!.uri;
    final decision = await _runGuards(
      targetMatches,
      targetUri,
      null,
      navigation,
    );
    if (decision is BlockGuardResult) {
      return _finish(
        navigation,
        watch,
        NavigationResult(NavigationOutcome.blocked, targetUri),
      );
    }
    if (decision case RedirectGuardResult(:final location)) {
      final target = _resolve(location);
      if (watch != null) {
        _emit(
          RedirectApplied(
            navigationId: navigation,
            timestamp: DateTime.now(),
            from: targetUri,
            to: target,
            source: RedirectSource.guard,
          ),
        );
      }
      // The redirect is a navigation of its own, with its own id: it goes
      // through `go`, which reports what it decides.
      return _finish(navigation, watch, await go(location));
    }

    final history =
        cached ??
        [_buildBranchInitialFrame(owner, resolved!.uri, resolved.matches)];
    if (reset) _completeFrames(state.histories[name] ?? const []);
    state
      ..activeBranch = name
      ..histories[name] = history;
    _frames
      ..clear()
      ..addAll(history);
    _restoreActiveRoutes();
    // The restored stack can host branch outlets of its own, whose state was
    // dropped while this branch was in the background.
    _syncBranchStates();
    _publish(navigation);
    return _finish(
      navigation,
      watch,
      NavigationResult(NavigationOutcome.completed, currentUri),
    );
  }

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
      kind: _ApplyKind.go,
      extra: state.entries.last.extra,
      fromPlatform: true,
    );
  }

  /// Pops the deepest outlet with more than one page.
  @internal
  Future<bool> popRoute() async {
    for (final owner in _navigation.activeNavigatorOwners) {
      for (final outlet in _outlets) {
        if (outlet.ownerActivationId != owner) continue;
        final navigator = outlet.navigatorKey.currentState;
        if (navigator == null || !navigator.canPop()) break;
        return navigator.maybePop();
      }
    }
    _pendingPopResult = null;
    return false;
  }

  /// Registers an outlet's [Navigator] so back navigation can reach it.
  @internal
  void registerOutlet(
    Object token,
    GlobalKey<NavigatorState> navigatorKey,
    int? ownerActivationId,
  ) {
    _outlets
      ..removeWhere((outlet) => identical(outlet.token, token))
      ..add(_OutletRegistration(token, navigatorKey, ownerActivationId));
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
    final navigationPage = _navigation.pageForKey(page.key);
    if (navigationPage == null) return;
    final frame = navigationPage.frame;
    final index = _frames.indexWhere((candidate) => candidate.id == frame.id);
    if (index < 0) return;

    if (frame.isError) {
      _dropFrames(index);
      return;
    }

    final activation = navigationPage.activation!;
    final position = frame.renderedActivations.toList().indexOf(activation);

    if (position == 0) {
      _dropFrames(index);
      return;
    }

    final keptLength = frame.renderStart + position;
    final kept = frame.activations.sublist(0, keptLength);
    final keptMatches = frame.matches.sublist(0, keptLength);
    _completeFrames(_frames.sublist(index + 1));
    _frames.removeRange(index, _frames.length);
    _frames.add(
      RouteFrame(
        id: frame.id,
        uri: Uri.parse(kept.last.match.matchedPath),
        matches: keptMatches,
        activations: kept,
        renderStart: frame.renderStart,
        anchorActivationId: frame.anchorActivationId,
        extra: frame.extra,
        completer: frame.completer,
      ),
    );
    _pendingPopResult = null;
    _restoreActiveRoutes();
    _syncBranchStates();
    _publish();
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
    required _ApplyKind kind,
    Object? extra,
    Completer<Object?>? completer,
    bool fromPlatform = false,
  }) async {
    final generation = ++_generation;
    final navigation = _nextNavigationId++;
    final watch = _isObserved ? (Stopwatch()..start()) : null;
    if (watch != null) {
      _emit(
        NavigationStarted(
          navigationId: navigation,
          timestamp: DateTime.now(),
          kind: fromPlatform
              ? NavigationKind.platform
              : switch (kind) {
                  _ApplyKind.go => NavigationKind.go,
                  _ApplyKind.push => NavigationKind.push,
                  _ApplyKind.replace => NavigationKind.replace,
                },
          from: currentUri,
          to: uri,
          extra: extra,
        ),
      );
    }
    _setNavigating(true);

    try {
      var target = uri;
      var redirects = 0;
      var redirected = false;
      final visited = <String>[uri.toString()];

      while (true) {
        final matches = _matcher.match(target);
        if (watch != null) {
          _emit(
            RouteMatched(
              navigationId: navigation,
              timestamp: DateTime.now(),
              uri: target,
              matches: matches,
            ),
          );
        }

        if (matches == null) {
          _apply(kind, target, const [], extra, completer, navigation);
          return _finish(
            navigation,
            watch,
            NavigationResult(
              redirected
                  ? NavigationOutcome.redirected
                  : NavigationOutcome.completed,
              target,
            ),
          );
        }

        final redirect = _redirectTarget(matches, target);
        if (redirect != null) {
          final from = target;
          target = _normalize(target.resolve(redirect));
          redirected = true;
          if (watch != null) {
            _emit(
              RedirectApplied(
                navigationId: navigation,
                timestamp: DateTime.now(),
                from: from,
                to: target,
                source: RedirectSource.route,
              ),
            );
          }
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
          if (watch != null) {
            _emit(
              DeactivationBlocked(
                navigationId: navigation,
                timestamp: DateTime.now(),
                uri: target,
              ),
            );
          }
          return _finish(
            navigation,
            watch,
            NavigationResult(NavigationOutcome.blocked, target),
          );
        }
        if (generation != _generation) {
          return _finish(
            navigation,
            watch,
            NavigationResult(NavigationOutcome.superseded, target),
          );
        }

        final decision = await _runGuards(matches, target, extra, navigation);
        if (generation != _generation) {
          return _finish(
            navigation,
            watch,
            NavigationResult(NavigationOutcome.superseded, target),
          );
        }

        switch (decision) {
          case AllowGuardResult():
            _apply(kind, target, matches, extra, completer, navigation);
            return _finish(
              navigation,
              watch,
              NavigationResult(
                redirected
                    ? NavigationOutcome.redirected
                    : NavigationOutcome.completed,
                target,
              ),
            );
          case BlockGuardResult():
            return _finish(
              navigation,
              watch,
              NavigationResult(NavigationOutcome.blocked, target),
            );
          case RedirectGuardResult(:final location):
            final from = target;
            target = _normalize(target.resolve(location));
            redirected = true;
            if (watch != null) {
              _emit(
                RedirectApplied(
                  navigationId: navigation,
                  timestamp: DateTime.now(),
                  from: from,
                  to: target,
                  source: RedirectSource.guard,
                ),
              );
            }
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

  /// Reports [result] as the end of navigation [navigation] and hands it
  /// back, so every exit of the pipeline closes the navigation exactly once.
  NavigationResult _finish(
    int navigation,
    Stopwatch? watch,
    NavigationResult result,
  ) {
    if (watch != null) {
      _emit(
        NavigationEnded(
          navigationId: navigation,
          timestamp: DateTime.now(),
          outcome: result.outcome,
          uri: result.uri,
          duration: watch.elapsed,
        ),
      );
    }
    return result;
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
    int navigation,
  ) async {
    for (final guard in _globalGuards) {
      final result = await _runGuard(
        guard,
        _guardContext(uri, matches, matches.last, extra),
        navigation,
        null,
      );
      if (result is! AllowGuardResult) return result;
    }
    for (final match in matches) {
      for (final guard in match.definition.guards) {
        final result = await _runGuard(
          guard,
          _guardContext(uri, matches, match, extra),
          navigation,
          match.route.debugPath,
        );
        if (result is! AllowGuardResult) return result;
      }
    }
    return GuardResult.allow;
  }

  Future<GuardResult> _runGuard(
    RouteGuard guard,
    GuardContext context,
    int navigation,
    String? routePath,
  ) async {
    if (!_isObserved) return guard.canActivate(context);
    final watch = Stopwatch()..start();
    final result = await guard.canActivate(context);
    _emit(
      GuardEvaluated(
        navigationId: navigation,
        timestamp: DateTime.now(),
        guardType: guard.runtimeType,
        routePath: routePath,
        result: result,
        duration: watch.elapsed,
      ),
    );
    return result;
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
    _ApplyKind kind,
    Uri uri,
    List<RouteMatch> matches,
    Object? extra,
    Completer<Object?>? completer,
    int navigation,
  ) {
    switch (kind) {
      case _ApplyKind.go:
        final previousHost = _frames.isEmpty
            ? null
            : _branchHost(_frames.last.matches);
        final nextHost = _branchHost(matches);
        final changesBranch =
            previousHost != null &&
            nextHost != null &&
            identical(previousHost.route, nextHost.route) &&
            previousHost.branch.name != nextHost.branch.name;
        final base = _frames.isEmpty ? null : _frames.first;
        final frame = _buildFrame(
          id: base?.id ?? _nextFrameId++,
          uri: uri,
          matches: matches,
          previous: base,
          reuseCount: base == null ? 0 : _commonPrefixLength(base, matches),
          extra: extra,
        );
        if (!changesBranch) _completeFrames(_frames);
        _frames
          ..clear()
          ..add(frame);
      case _ApplyKind.push:
        _frames.add(_buildPushFrame(uri, matches, extra, completer));
      case _ApplyKind.replace:
        // Reuse is measured against the frame being replaced, not against the
        // one below it: the replacement takes that frame's place, so every
        // shell it had opened above the frame below stays as it is instead of
        // being torn down and built again.
        final base = _frames.isEmpty ? null : _frames.removeLast();
        final reuseCount = base == null
            ? 0
            : _commonPrefixLength(base, matches);
        // Rendering may not start deeper than the replaced frame did: the
        // pages in between belong to no other frame.
        final renderStart = base == null || reuseCount < base.renderStart
            ? reuseCount
            : base.renderStart;
        _frames.add(
          _buildFrame(
            id: base?.id ?? _nextFrameId++,
            uri: uri,
            matches: matches,
            previous: base,
            reuseCount: reuseCount,
            renderStart: renderStart,
            anchorActivationId: renderStart == 0
                ? null
                : _outletAnchor(base!, renderStart),
            extra: extra,
            completer: base?.completer,
          ),
        );
    }
    _syncBranchStates();
    _publish(navigation);
  }

  void _syncBranchStates() {
    if (_frames.isEmpty || _frames.last.isError) return;
    for (var index = 0; index < _frames.last.activations.length; index++) {
      final activation = _frames.last.activations[index];
      final definition = activation.match.definition;
      if (definition is! ModuleRoute || definition.branches.isEmpty) continue;
      final branch = _branchAt(definition, _frames.last.matches, index);
      if (branch == null) continue;
      final state = _navigation.branchStates.putIfAbsent(
        activation.id,
        () => NavigationBranchState(
          ownerActivationId: activation.id,
          branchNames: [for (final item in definition.branches) item.name],
          activeBranch: branch.name,
        ),
      );
      state
        ..activeBranch = branch.name
        ..histories[branch.name] = List.of(_frames);

      if (definition.branchInitialization == BranchInitialization.eager) {
        for (final item in definition.branches) {
          if (state.histories.containsKey(item.name)) continue;
          final uri = _normalize(Uri.parse(item.initialLocation));
          final resolved = _matchFollowingRedirects(uri);
          if (resolved == null) {
            throw StateError(
              'Initial location ${item.initialLocation} of branch '
              '"${item.name}" does not match a route.',
            );
          }
          _requireBranchMatches(definition, item, resolved.matches);
          state.histories[item.name] = [
            _buildBranchInitialFrame(
              activation,
              resolved.uri,
              resolved.matches,
            ),
          ];
        }
        _restoreActiveRoutes();
      }
    }
  }

  RouteFrame _buildBranchInitialFrame(
    RouteActivation owner,
    Uri uri,
    List<RouteMatch> matches,
  ) {
    final previous = _frames.last;
    final reuseCount = _commonPrefixLength(previous, matches);
    if (reuseCount == 0 ||
        previous.activations[reuseCount - 1].id != owner.id) {
      throw StateError('$uri does not belong to the selected branch outlet.');
    }
    return _buildFrame(
      id: _nextFrameId++,
      uri: uri,
      matches: matches,
      previous: previous,
      reuseCount: reuseCount,
    );
  }

  ({Uri uri, List<RouteMatch> matches})? _matchFollowingRedirects(Uri uri) {
    var target = uri;
    for (var redirects = 0; redirects <= _redirectLimit; redirects++) {
      final matches = _matcher.match(target);
      if (matches == null) return null;
      final redirect = _redirectTarget(matches, target);
      if (redirect == null) return (uri: target, matches: matches);
      target = _normalize(target.resolve(redirect));
    }
    throw StateError('Redirect loop while initializing branch at $uri.');
  }

  void _requireBranchMatches(
    ModuleRoute host,
    RouteBranch expected,
    List<RouteMatch> matches,
  ) {
    final matched = _branchHost(matches);
    if (matched == null ||
        !identical(matched.route, host) ||
        !identical(matched.branch, expected)) {
      throw StateError(
        'Initial location ${expected.initialLocation} does not belong to '
        'branch "${expected.name}".',
      );
    }
  }

  ({int index, ModuleRoute route, RouteBranch branch})? _branchHost(
    List<RouteMatch> matches,
  ) {
    for (var index = matches.length - 2; index >= 0; index--) {
      final definition = matches[index].definition;
      if (definition is! ModuleRoute || definition.branches.isEmpty) continue;
      final branch = _branchAt(definition, matches, index);
      if (branch != null) {
        return (index: index, route: definition, branch: branch);
      }
    }
    return null;
  }

  RouteBranch? _branchAt(
    ModuleRoute host,
    List<RouteMatch> matches,
    int hostIndex,
  ) {
    if (hostIndex + 1 >= matches.length) return null;
    final root = matches[hostIndex + 1].definition;
    for (final branch in host.branches) {
      if (branch.routes.any((route) => identical(route, root))) return branch;
    }
    return null;
  }

  RouteFrame _buildPushFrame(
    Uri uri,
    List<RouteMatch> matches,
    Object? extra,
    Completer<Object?>? completer,
  ) {
    final previous = _frames.isEmpty ? null : _frames.last;
    var reuseCount = previous == null
        ? 0
        : _commonPrefixLength(previous, matches);

    // Pushing the current location must still create a distinct top page.
    if (matches.isNotEmpty && reuseCount == matches.length) reuseCount--;

    return _buildFrame(
      id: _nextFrameId++,
      uri: uri,
      matches: matches,
      previous: previous,
      reuseCount: reuseCount,
      renderStart: reuseCount,
      anchorActivationId: reuseCount == 0
          ? null
          : _outletAnchor(previous!, reuseCount),
      extra: extra,
      completer: completer,
    );
  }

  int _commonPrefixLength(RouteFrame frame, List<RouteMatch> matches) {
    final length = frame.activations.length < matches.length
        ? frame.activations.length
        : matches.length;
    var index = 0;
    while (index < length &&
        _canReuse(frame.activations[index], matches[index])) {
      index++;
    }
    return index;
  }

  int? _outletAnchor(RouteFrame frame, int beforeIndex) {
    for (var index = beforeIndex - 1; index >= 0; index--) {
      final activation = frame.activations[index];
      if (activation.opensNavigationBoundary) return activation.id;
    }
    return null;
  }

  /// Builds the activations for one frame, reusing those of [previous] as
  /// far as the chain agrees and each route's [RouteReuse] allows.
  ///
  /// Reuse stops for good at the first activation that cannot be kept: what
  /// follows it depends on it, so it has to be rebuilt too.
  RouteFrame _buildFrame({
    required int id,
    required Uri uri,
    required List<RouteMatch> matches,
    required RouteFrame? previous,
    required int reuseCount,
    int renderStart = 0,
    int? anchorActivationId,
    Object? extra,
    Completer<Object?>? completer,
  }) {
    final activations = <RouteActivation>[];
    ActivatedRoute? parent;

    for (var index = 0; index < matches.length; index++) {
      final match = matches[index];
      RouteActivation? reused;

      if (previous != null && index < reuseCount) {
        reused = previous.activations[index];
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
      id: id,
      uri: uri,
      matches: List.unmodifiable(matches),
      activations: List.unmodifiable(activations),
      renderStart: renderStart,
      anchorActivationId: anchorActivationId,
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
    _restoreActiveRoutes();
    _syncBranchStates();
    _publish();
  }

  void _restoreActiveRoutes() {
    if (_frames.isEmpty) return;
    final frame = _frames.last;
    for (var index = 0; index < frame.activations.length; index++) {
      frame.activations[index].update(
        match: frame.matches[index],
        uri: frame.uri,
        extra: frame.extra,
      );
    }
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

  /// Completes the futures of frames that are dropped without being popped —
  /// a branch history whose outlet is gone, or the whole stack at dispose.
  /// Nothing answered them, so none of them gets the value handed to [pop].
  void _abandonFrames(List<RouteFrame> frames) {
    for (final frame in frames) {
      final completer = frame.completer;
      if (completer == null || completer.isCompleted) continue;
      if (_frames.contains(frame)) continue;
      completer.complete(null);
    }
  }

  /// Whether anything is watching. Every emission site checks this before
  /// building an event, so a router without observers pays nothing for the
  /// hook — not a stopwatch, not an allocation.
  bool get _isObserved => _navigationObservers.isNotEmpty;

  /// A broken observer must not break navigation, so one that throws is
  /// reported and the rest still get the event.
  void _emit(RouterEvent event) {
    for (final observer in _navigationObservers) {
      try {
        observer.onEvent(event);
      } catch (error, stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'modulith_router',
            context: ErrorDescription('while notifying $observer of $event'),
          ),
        );
      }
    }
  }

  void _setNavigating(bool value) {
    if (_isNavigating == value) return;
    _isNavigating = value;
    _notifyChanges();
  }

  /// [navigation] is the id of the navigation behind the change, or `null`
  /// when a [Navigator] removed a page on its own.
  void _publish([int? navigation]) {
    // A branch outlet the navigation just left for good takes its retained
    // histories with it; nothing will ever pop those frames again.
    for (final state in _navigation.rebuild()) {
      for (final history in state.histories.values) {
        _abandonFrames(history);
      }
    }
    _revision++;
    if (_isObserved) {
      _emit(
        StackChanged(
          timestamp: DateTime.now(),
          navigationId: navigation,
          revision: _revision,
          uri: currentUri,
        ),
      );
    }
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
  _OutletRegistration(this.token, this.navigatorKey, this.ownerActivationId);

  final Object token;
  final GlobalKey<NavigatorState> navigatorKey;
  final int? ownerActivationId;
}
