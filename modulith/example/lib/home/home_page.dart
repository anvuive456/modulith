import 'package:flutter/material.dart';
import 'package:modulith/modulith.dart';

import '../core/settings_controller.dart';
import '../features/counter/counter_module.dart';
import '../features/dashboard/dashboard_module.dart';
import '../features/profile/profile_module.dart';
import '../features/stopwatch/stopwatch_module.dart';
import '../features/todo/todo_module.dart';
import 'feature_entry.dart';

class HomePage extends ModularWidget {
  const HomePage({super.key});

  static final _features = [
    FeatureEntry(
      title: 'Counter',
      subtitle: 'A single controller driving a Signal',
      icon: Icons.add_circle_outline,
      moduleBuilder: CounterModule.new,
    ),
    FeatureEntry(
      title: 'Todo list',
      subtitle: 'Controller + Service, async init()',
      icon: Icons.checklist,
      moduleBuilder: TodoModule.new,
    ),
    FeatureEntry(
      title: 'Profile',
      subtitle: 'Reads a Controller shared from the app module',
      icon: Icons.person_outline,
      moduleBuilder: ProfileModule.new,
    ),
    FeatureEntry(
      title: 'Stopwatch',
      subtitle: 'Timer started in init(), cancelled in dispose()',
      icon: Icons.timer_outlined,
      moduleBuilder: StopwatchModule.new,
    ),
    FeatureEntry(
      title: 'Dashboard',
      subtitle: 'Nests a child module with ChildModuleView',
      icon: Icons.dashboard_outlined,
      moduleBuilder: DashboardModule.new,
    ),
  ];

  @override
  Widget build(ModuleContext context) {
    final settings = context.getController<SettingsController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter Modular Example'),
        actions: [
          SignalBuilder(
            signal: settings.darkMode,
            builder: (isDark) => IconButton(
              tooltip: 'Toggle dark mode',
              icon: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
              onPressed: settings.toggleDarkMode,
            ),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _features.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final feature = _features[index];
          return ListTile(
            leading: Icon(feature.icon),
            title: Text(feature.title),
            subtitle: Text(feature.subtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ModuleWidget(module: feature.moduleBuilder()),
              ),
            ),
          );
        },
      ),
    );
  }
}
