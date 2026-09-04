import 'package:flutter/widgets.dart';
import 'package:modulith/modulith.dart';

import 'stopwatch_controller.dart';
import 'stopwatch_page.dart';

class StopwatchModule extends Module {
  @override
  Widget get view => const StopwatchPage();

  @override
  List<Provider<Controller>> get controllers => [
    Provider<StopwatchController>.singleton(create: StopwatchController.new),
  ];
}
