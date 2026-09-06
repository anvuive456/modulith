import 'package:flutter/material.dart';
import 'package:modulith/modulith.dart';

import '../core/settings_controller.dart';
import '../home/home_page.dart';

class AppModule extends Module {
  @override
  Widget get view => const AppView();

  @override
  List<Provider<Controller>> get controllers => [
    Provider<SettingsController>.singleton(create: SettingsController.new),
  ];
}

class AppView extends ModularWidget {
  const AppView({super.key});

  @override
  Widget build(ModuleContext context) {
    final settings = context.getController<SettingsController>();
    return SignalBuilder(
      signal: settings.darkMode,
      builder: (isDark) => MaterialApp(
        title: 'Flutter Modular Example',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
        home: const HomePage(),
      ),
    );
  }
}
