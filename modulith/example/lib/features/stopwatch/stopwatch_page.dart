import 'package:flutter/material.dart';
import 'package:modulith/modulith.dart';

import 'stopwatch_controller.dart';

class StopwatchPage extends ModularWidget {
  const StopwatchPage({super.key});

  @override
  Widget build(ModuleContext context) {
    final controller = context.getController<StopwatchController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Stopwatch')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SignalBuilder(
              signal: controller.elapsedSeconds,
              builder: (seconds) {
                final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
                final secs = (seconds % 60).toString().padLeft(2, '0');
                return Text(
                  '$minutes:$secs',
                  style: Theme.of(context).textTheme.displayMedium,
                );
              },
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SignalBuilder(
                  signal: controller.running,
                  builder: (running) => FilledButton(
                    onPressed: controller.toggle,
                    child: Text(running ? 'Pause' : 'Resume'),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: controller.reset,
                  child: const Text('Reset'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
