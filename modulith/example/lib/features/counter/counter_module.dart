import 'package:flutter/widgets.dart';
import 'package:modulith/modulith.dart';

import 'counter_controller.dart';
import 'counter_page.dart';

class CounterModule extends Module {
  @override
  Widget get view => const CounterPage();

  @override
  List<Provider<Controller>> get controllers => [
    Provider<CounterController>.singleton(create: CounterController.new),
  ];
}
