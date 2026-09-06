import 'model/router_models.dart';

/// The connected app's side of the extension, behind one seam.
///
/// Everything the UI knows about the app goes through here. The interface
/// deliberately pulls in nothing web-only, so the whole extension can be
/// driven from a fake in a plain `flutter test` — see
/// `VmServiceRouterClient` for the implementation that talks to a real app.
abstract class RouterClient {
  /// Allows `const` implementations.
  const RouterClient();

  /// The event kind `RouterInspector` posts under.
  static const String eventKind = 'modulith_router:event';

  /// Every router mounted in the app.
  Future<List<RouterHandle>> listRouters();

  /// Where router [routerId] is.
  Future<RouterStateData> getState(int routerId);

  /// The live frames and navigators of router [routerId].
  Future<NavigationSnapshot> getNavigationTree(int routerId);

  /// The compiled route table of router [routerId].
  Future<RouteTableData> getRouteTable(int routerId);

  /// What matching [location] would do in router [routerId], without doing
  /// it.
  Future<MatchTraceData> matchTrace(int routerId, String location);

  /// The router events the app posts, as they happen.
  Stream<Map<String, Object?>> get events;
}
