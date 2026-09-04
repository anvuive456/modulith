import 'package:flutter/material.dart';
import 'package:modulith/modulith.dart';

import '../../../core/settings_controller.dart';
import 'weather_controller.dart';

/// This is WeatherModule's view; it's mounted via ChildModuleView inside
/// DashboardPage, scoped under DashboardModule.
class WeatherWidget extends ModularWidget {
  const WeatherWidget({super.key});

  @override
  Widget build(ModuleContext context) {
    final controller = context.getController<WeatherController>();
    // SettingsController lives two levels up (WeatherModule ->
    // DashboardModule -> AppModule); getController walks the whole chain to
    // find it, even though DashboardModule doesn't own it either.
    final settings = context.getController<SettingsController>();

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SignalBuilder(
          signal: controller.loading,
          builder: (loading) {
            if (loading) {
              return const Center(child: CircularProgressIndicator());
            }
            return SignalBuilder(
              signal: controller.summary,
              builder: (summary) => SignalBuilder(
                signal: settings.username,
                builder: (name) => Text('Hi $name, today: $summary'),
              ),
            );
          },
        ),
      ),
    );
  }
}
