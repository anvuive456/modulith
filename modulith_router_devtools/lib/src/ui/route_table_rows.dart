import '../model/router_models.dart';

/// One line of the route table, already flattened and indented.
class RouteRow {
  /// Creates a row for [node].
  const RouteRow({required this.node, required this.depth});

  /// The route this row shows.
  final RouteNodeData node;

  /// How deep to indent it.
  final int depth;
}

/// Flattens [roots] depth first, keeping only what [query] asks for.
///
/// A route is kept when it matches, and so are its ancestors — a match three
/// levels down is meaningless without the routes it hangs off.
List<RouteRow> flattenRouteTable(
  List<RouteNodeData> roots, {
  String query = '',
}) {
  final needle = query.trim().toLowerCase();
  final rows = <RouteRow>[];

  bool matches(RouteNodeData node) =>
      needle.isEmpty ||
      node.debugPath.toLowerCase().contains(needle) ||
      node.path.toLowerCase().contains(needle) ||
      (node.name?.toLowerCase().contains(needle) ?? false);

  bool visit(RouteNodeData node, int depth) {
    final index = rows.length;
    rows.add(RouteRow(node: node, depth: depth));

    var keptAChild = false;
    for (final child in node.children) {
      keptAChild = visit(child, depth + 1) || keptAChild;
    }
    if (matches(node) || keptAChild) return true;

    // Nothing here or below was asked for: take this row back out, and with
    // it the rows of the children that were only kept provisionally.
    rows.removeRange(index, rows.length);
    return false;
  }

  for (final root in roots) {
    visit(root, 0);
  }
  return rows;
}
