import 'package:flutter/material.dart';
import 'package:modulith/modulith.dart';

import 'counter_controller.dart';

class CounterPage extends ModularWidget {
  const CounterPage({super.key});

  @override
  Widget build(ModuleContext context) {
    final controller = context.getController<CounterController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Counter')),
      body: Center(
        child: SignalBuilder(
          signal: controller.count,
          builder: (value) =>
              Text('$value', style: Theme.of(context).textTheme.displayMedium),
        ),
      ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'decrement',
            onPressed: controller.decrement,
            child: const Icon(Icons.remove),
          ),
          const SizedBox(width: 12),
          FloatingActionButton(
            heroTag: 'reset',
            onPressed: controller.reset,
            child: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 12),
          FloatingActionButton(
            heroTag: 'increment',
            onPressed: controller.increment,
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
