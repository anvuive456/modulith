// Verifies the barrel really hands over modulith's API too.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modulith_router/modulith_router.dart';

class CountController extends Controller {
  late final count = createSignal<int>(1);
}

class SoloModule extends Module {
  @override
  List<Provider<Controller>> get controllers => [
    Provider<CountController>.singleton(create: CountController.new),
  ];

  @override
  Widget get view => const SoloView();
}

class SoloView extends ModularWidget {
  const SoloView({super.key});

  @override
  Widget build(ModuleContext context) => SignalBuilder(
    signal: context.getController<CountController>().count,
    builder: (value) => Text('$value', textDirection: TextDirection.ltr),
  );
}

void main() {
  testWidgets('one import is enough for modules, controllers and signals', (
    tester,
  ) async {
    await tester.pumpWidget(ModuleWidget(module: SoloModule()));
    expect(find.text('1'), findsOneWidget);
  });
}
