import 'dart:async';

import 'package:devtools_app_shared/utils.dart';
import 'package:flutter/foundation.dart';

import 'model/router_models.dart';
import 'router_client.dart';

/// The state the extension shows, and the one place that decides when to ask
/// the app for more.
///
/// Events are only a signal: an event says the stack moved, and this
/// controller then pulls the tree that moved. A burst of navigations
/// therefore costs one refresh, not one per event.
class RouterExtensionController extends DisposableController
    with AutoDisposeControllerMixin {
  /// Watches the app through [client].
  RouterExtensionController(this.client);

  /// How long to wait for a burst of events to settle before refreshing.
  static const Duration refreshDelay = Duration(milliseconds: 50);

  /// How often the router's state is checked when no event has said to.
  ///
  /// Events are a fast path, not the mechanism: `dart:developer.postEvent` is
  /// a no-op on dart2js and depends on a `package:dwds` hook under DDC, so an
  /// extension that only listened would sit there stale against every web
  /// app. `getState` is a few fields, and a poll that finds the same revision
  /// costs one round trip and no rebuild.
  static const Duration pollInterval = Duration(seconds: 1);

  /// The app under inspection.
  final RouterClient client;

  /// Every router mounted in the app.
  final routers = ValueNotifier<List<RouterHandle>>(const []);

  /// The router being shown, or `null` when the app has none.
  final selectedRouterId = ValueNotifier<int?>(null);

  /// Where the selected router is.
  final state = ValueNotifier<RouterStateData?>(null);

  /// The selected router's frames and navigators.
  final navigation = ValueNotifier<NavigationSnapshot?>(null);

  /// The selected router's compiled route table.
  final routeTable = ValueNotifier<RouteTableData?>(null);

  /// The last URL tested against the route table, and what it would do.
  final trace = ValueNotifier<MatchTraceData?>(null);

  /// What went wrong with the last URL test, if anything.
  final traceError = ValueNotifier<String?>(null);

  /// Filters the route table by path or name.
  final routeFilter = ValueNotifier<String>('');

  /// The page the details pane is describing.
  final selectedPageKey = ValueNotifier<String?>(null);

  /// What went wrong with the last call, if anything.
  final error = ValueNotifier<String?>(null);

  /// Whether a refresh is in flight.
  final isRefreshing = ValueNotifier<bool>(false);

  StreamSubscription<Map<String, Object?>>? _events;
  Timer? _pendingRefresh;
  Timer? _poll;
  bool _refreshing = false;

  @override
  void init() {
    super.init();
    _events = client.events.listen(_onEvent);
    _poll = Timer.periodic(pollInterval, (_) => unawaited(_checkForChange()));
    unawaited(refresh());
  }

  /// Re-subscribes and refreshes — what to call when the app is replaced
  /// under us, which is what a hot restart looks like from here.
  void reconnect() {
    _events?.cancel();
    _events = client.events.listen(_onEvent);
    selectedRouterId.value = null;
    selectedPageKey.value = null;
    unawaited(refresh());
  }

  /// Shows router [routerId] instead of the current one.
  void selectRouter(int routerId) {
    if (selectedRouterId.value == routerId) return;
    selectedRouterId.value = routerId;
    selectedPageKey.value = null;
    unawaited(refresh());
  }

  /// Shows the page keyed [pageKey] in the details pane.
  void selectPage(String? pageKey) => selectedPageKey.value = pageKey;

  /// Narrows the route table to routes whose path or name contains [query].
  void filterRoutes(String query) => routeFilter.value = query;

  /// Asks the app what matching [location] would do — matching only, with no
  /// navigation and no guard actually run.
  Future<void> testUrl(String location) async {
    final routerId = selectedRouterId.value;
    if (routerId == null || location.trim().isEmpty) {
      trace.value = null;
      traceError.value = null;
      return;
    }
    try {
      trace.value = await client.matchTrace(routerId, location.trim());
      traceError.value = null;
    } catch (failure) {
      if (disposed) return;
      trace.value = null;
      traceError.value = '$failure';
    }
  }

  /// Pulls the router list, the state and the navigation tree.
  Future<void> refresh() async {
    if (_refreshing || disposed) return;
    _refreshing = true;
    isRefreshing.value = true;
    try {
      final handles = await client.listRouters();
      if (disposed) return;
      routers.value = handles;

      final selected = _resolveSelection(handles);
      selectedRouterId.value = selected;
      if (selected == null) {
        state.value = null;
        navigation.value = null;
        routeTable.value = null;
        error.value = null;
        return;
      }

      final nextState = await client.getState(selected);
      final nextNavigation = await client.getNavigationTree(selected);
      // The table only changes on a hot reload, but that is exactly when a
      // stale one would mislead, so it is pulled with the rest.
      final nextTable = await client.getRouteTable(selected);
      if (disposed) return;
      state.value = nextState;
      navigation.value = nextNavigation;
      routeTable.value = nextTable;
      error.value = null;
    } catch (failure) {
      if (disposed) return;
      error.value = '$failure';
    } finally {
      _refreshing = false;
      if (!disposed) isRefreshing.value = false;
    }
  }

  /// Keeps the current router selected while it is still there, and falls
  /// back to the first one when it is not — a router disposed with its
  /// module should not leave the UI pointing at nothing.
  int? _resolveSelection(List<RouterHandle> handles) {
    if (handles.isEmpty) return null;
    final current = selectedRouterId.value;
    for (final handle in handles) {
      if (handle.id == current) return current;
    }
    return handles.first.id;
  }

  /// Asks the router where it is, and pulls the rest only when that answer
  /// changed. This is what keeps the extension live against a web app, where
  /// no event ever arrives.
  Future<void> _checkForChange() async {
    final routerId = selectedRouterId.value;
    if (routerId == null || _refreshing || disposed) return;
    try {
      final next = await client.getState(routerId);
      if (disposed) return;
      final current = state.value;
      final unchanged =
          current != null &&
          current.revision == next.revision &&
          current.currentUri == next.currentUri &&
          current.isNavigating == next.isNavigating;
      if (unchanged) return;
      await refresh();
    } catch (_) {
      // The app went away — a hot restart, a disconnect. A full refresh says
      // so properly, and picks the app back up when it returns.
      if (!disposed) await refresh();
    }
  }

  void _onEvent(Map<String, Object?> event) {
    // Events arrive one per pipeline decision; a single `go` posts four or
    // more. Coalesce them into one refresh.
    _pendingRefresh?.cancel();
    _pendingRefresh = Timer(refreshDelay, () {
      if (!disposed) unawaited(refresh());
    });
  }

  @override
  void dispose() {
    _pendingRefresh?.cancel();
    _poll?.cancel();
    unawaited(_events?.cancel());
    routers.dispose();
    selectedRouterId.dispose();
    state.dispose();
    navigation.dispose();
    routeTable.dispose();
    trace.dispose();
    traceError.dispose();
    routeFilter.dispose();
    selectedPageKey.dispose();
    error.dispose();
    isRefreshing.dispose();
    super.dispose();
  }
}
