import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';

import 'src/ui/extension_body.dart';
import 'src/vm_service_router_client.dart';

void main() {
  runApp(const ModulithRouterExtension());
}

/// The DevTools extension for `modulith_router`.
///
/// The app it inspects registers `ext.modulith_router.*` from a debug build
/// only, so this tab is a debugging tool and says so when it finds nothing.
class ModulithRouterExtension extends StatelessWidget {
  /// Creates the extension.
  const ModulithRouterExtension({super.key});

  @override
  Widget build(BuildContext context) => const DevToolsExtension(
    child: RouterExtensionBody(client: VmServiceRouterClient()),
  );
}
