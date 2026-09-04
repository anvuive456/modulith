import 'package:modulith/modulith.dart';

class DashboardController extends Controller {
  late final mountedAt = createSignal<DateTime?>(null);

  @override
  void init() {
    mountedAt.value = DateTime.now();
  }
}
