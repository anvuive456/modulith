import 'package:flutter/widgets.dart';
import 'package:modulith/modulith.dart';

import 'weather_controller.dart';
import 'weather_widget.dart';

class WeatherModule extends Module {
  @override
  Widget get view => const WeatherWidget();

  @override
  List<Provider<Controller>> get controllers => [
    Provider<WeatherController>.singleton(create: WeatherController.new),
  ];
}
