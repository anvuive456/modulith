import 'package:flutter/widgets.dart';
import 'package:modulith/modulith.dart';

import 'todo_service.dart';

class TodoController extends Controller {
  late final TodoService _service = injectService<TodoService>();
  late final loading = createSignal<bool>(true);
  late final todos = createSignal<List<String>>(const []);

  /// Owned here, not by the view: the page is a plain [ModularWidget] with
  /// no `State` to hold it, and this way the draft text survives a rebuild.
  final input = TextEditingController();

  @override
  void init() {
    super.init();
    addDisposeCallback(input.dispose);
    // Deferred to init() (not the constructor) so the fetch only starts
    // once this module is actually mounted on screen.
    _load();
  }

  Future<void> _load() async {
    final items = await _service.fetchInitialTodos();
    // The screen can be popped while the fetch is in flight, which disposes
    // this controller; bail out instead of touching dead state.
    if (isDisposed) return;
    todos.value = items;
    loading.value = false;
  }

  /// Adds whatever is currently in [input] and clears it.
  void submit() {
    add(input.text);
    input.clear();
  }

  void add(String text) {
    if (text.trim().isEmpty) return;
    todos.value = [...todos.value, text.trim()];
  }

  void removeAt(int index) {
    final next = [...todos.value]..removeAt(index);
    todos.value = next;
  }
}
