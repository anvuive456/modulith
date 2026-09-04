import 'package:flutter/material.dart';
import 'package:modulith/modulith.dart';

import 'dashboard_controller.dart';
import 'weather/weather_module.dart';

class DashboardPage extends ModularWidget {
  const DashboardPage({super.key});

  @override
  Widget build(ModuleContext context) {
    final controller = context.getController<DashboardController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: Column(
        children: [
          SignalBuilder(
            signal: controller.mountedAt,
            builder: (time) {
              if (time == null) return const SizedBox.shrink();
              final formatted =
                  '${time.hour.toString().padLeft(2, '0')}:'
                  '${time.minute.toString().padLeft(2, '0')}:'
                  '${time.second.toString().padLeft(2, '0')}';
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Dashboard module mounted at $formatted'),
              );
            },
          ),
          // WeatherModule is declared in DashboardModule.children; this
          // mounts it right here, scoped under DashboardModule.
          const ChildModuleView<WeatherModule>(),
        ],
      ),
    );
  }
}
