import 'package:flutter/widgets.dart';
import 'package:modulith/modulith.dart';

import 'dashboard_controller.dart';
import 'dashboard_page.dart';
import 'weather/weather_module.dart';

class DashboardModule extends Module {
  @override
  Widget get view => const DashboardPage();

  @override
  List<Provider<Controller>> get controllers => [
    Provider<DashboardController>.singleton(create: DashboardController.new),
  ];

  @override
  List<Module> get children => [WeatherModule()];
}
