import 'package:flutter/material.dart';
import 'package:modulith/modulith.dart';

import 'todo_controller.dart';

class TodoPage extends ModularWidget {
  const TodoPage({super.key});

  @override
  Widget build(ModuleContext context) {
    final controller = context.getController<TodoController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Todo list')),
      body: Column(
        children: [
          Expanded(
            child: SignalBuilder(
              signal: controller.loading,
              builder: (loading) {
                if (loading) {
                  return const Center(child: CircularProgressIndicator());
                }
                return SignalBuilder(
                  signal: controller.todos,
                  builder: (todos) {
                    if (todos.isEmpty) {
                      return const Center(child: Text('No todos yet'));
                    }
                    return ListView.builder(
                      itemCount: todos.length,
                      itemBuilder: (context, index) => ListTile(
                        title: Text(todos[index]),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => controller.removeAt(index),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    // The TextEditingController lives on TodoController, so
                    // this page needs no State of its own.
                    controller: controller.input,
                    decoration: const InputDecoration(hintText: 'Add a todo'),
                    onSubmitted: (_) => controller.submit(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: controller.submit,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
