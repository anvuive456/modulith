import 'package:modulith/modulith.dart';

class WeatherController extends Controller {
  late final loading = createSignal<bool>(true);
  late final summary = createSignal<String>('');

  @override
  void init() {
    super.init();
    _load();
  }

  Future<void> _load() async {
    await Future.delayed(const Duration(milliseconds: 800));
    if (isDisposed) return;
    summary.value = '☀️ 28°C, sunny';
    loading.value = false;
  }
}
