import 'package:modulith/modulith.dart';

class CounterController extends Controller {
  late final count = createSignal<int>(0);

  void increment() => count.value++;
  void decrement() => count.value--;
  void reset() => count.value = 0;
}
