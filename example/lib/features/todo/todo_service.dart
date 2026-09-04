import 'package:modulith/modulith.dart';

/// A fake repository: simulates a network/database round trip.
class TodoService extends Service {
  Future<List<String>> fetchInitialTodos() async {
    await Future.delayed(const Duration(milliseconds: 600));
    return const ['Read the README', 'Try the Stopwatch feature'];
  }
}
