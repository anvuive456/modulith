import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:vm_service/vm_service.dart';

import 'model/router_models.dart';
import 'router_client.dart';

/// The [RouterClient] that talks to a real app over the VM service.
///
/// This is the only file that touches `serviceManager`, which is what keeps
/// the rest of the extension testable off the web.
class VmServiceRouterClient extends RouterClient {
  /// Creates a client over the extension's `serviceManager`.
  const VmServiceRouterClient();

  static const String _prefix = 'ext.modulith_router.';

  @override
  Future<List<RouterHandle>> listRouters() async {
    final json = await _call('listRouters');
    return [
      for (final router in (json['routers'] as List? ?? const []))
        RouterHandle.fromJson((router as Map).cast<String, Object?>()),
    ];
  }

  @override
  Future<RouterStateData> getState(int routerId) async =>
      RouterStateData.fromJson(await _call('getState', routerId: routerId));

  @override
  Future<NavigationSnapshot> getNavigationTree(int routerId) async =>
      NavigationSnapshot.fromJson(
        await _call('getNavigationTree', routerId: routerId),
      );

  @override
  Future<RouteTableData> getRouteTable(int routerId) async =>
      RouteTableData.fromJson(await _call('getRouteTable', routerId: routerId));

  @override
  Future<MatchTraceData> matchTrace(int routerId, String location) async =>
      MatchTraceData.fromJson(
        await _call(
          'matchTrace',
          routerId: routerId,
          args: {'location': location},
        ),
      );

  @override
  Stream<Map<String, Object?>> get events {
    final service = serviceManager.service;
    if (service == null) return const Stream.empty();
    return service.onExtensionEvent
        .where((event) => event.extensionKind == RouterClient.eventKind)
        .map(
          (event) =>
              event.extensionData?.data.cast<String, Object?>() ??
              const <String, Object?>{},
        );
  }

  Future<Map<String, Object?>> _call(
    String method, {
    int? routerId,
    Map<String, String> args = const {},
  }) async {
    final Response response = await serviceManager
        .callServiceExtensionOnMainIsolate(
          '$_prefix$method',
          args: {if (routerId != null) 'routerId': '$routerId', ...args},
        );
    return response.json?.cast<String, Object?>() ?? const {};
  }
}
