import 'package:flutter/widgets.dart';
import 'package:modulith/modulith.dart';

import 'todo_controller.dart';
import 'todo_page.dart';
import 'todo_service.dart';

class TodoModule extends Module {
  @override
  Widget get view => const TodoPage();

  @override
  List<Provider<Service>> get services => [
    Provider<TodoService>.singleton(create: TodoService.new),
  ];

  @override
  List<Provider<Controller>> get controllers => [
    Provider<TodoController>.singleton(create: TodoController.new),
  ];
}
