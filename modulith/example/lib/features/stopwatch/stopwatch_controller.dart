import 'dart:async';

import 'package:modulith/modulith.dart';

class StopwatchController extends Controller {
  late final elapsedSeconds = createSignal<int>(0);
  late final running = createSignal<bool>(true);
  Timer? _timer;

  @override
  void init() {
    super.init();
    // Started here, not in the constructor, so the timer only runs while
    // this module is actually mounted on screen — the constructor can run
    // well before that (e.g. when building the feature list).
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsedSeconds.value++;
    });
  }

  void toggle() {
    running.value = !running.value;
    if (running.value) {
      _startTimer();
    } else {
      _timer?.cancel();
    }
  }

  void reset() => elapsedSeconds.value = 0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose(); // disposes elapsedSeconds and running
  }
}
