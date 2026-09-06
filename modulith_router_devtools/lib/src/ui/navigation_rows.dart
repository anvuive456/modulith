import '../model/router_models.dart';

/// One line of the navigation tree, already flattened and indented.
///
/// Flattening happens here rather than in the widget so that the shape of
/// the tree — what nests under what, and what a branch in the background
/// looks like — can be asserted without pumping anything.
sealed class NavigationRow {
  const NavigationRow({required this.depth});

  /// How deep to indent this row.
  final int depth;
}

/// A concrete `Navigator` and, with it, the start of a page stack.
final class NavigatorRow extends NavigationRow {
  /// Creates a navigator header labelled [label].
  const NavigatorRow({
    required super.depth,
    required this.navigator,
    required this.label,
  });

  /// The navigator this row heads.
  final NavigatorData navigator;

  /// `Navigator (root)`, or the outlet that owns it.
  final String label;
}

/// One page of a navigator's stack.
final class PageRow extends NavigationRow {
  /// Creates a row for [page].
  const PageRow({required super.depth, required this.page});

  /// The page this row shows.
  final PageData page;
}

/// The branch outlet one page hosts.
final class BranchesRow extends NavigationRow {
  /// Creates a row for a branch outlet.
  const BranchesRow({required super.depth, required this.branches});

  /// The branches hosted here.
  final BranchesData branches;
}

/// One branch, active or retained in the background.
final class BranchRow extends NavigationRow {
  /// Creates a row for [branch].
  const BranchRow({required super.depth, required this.branch});

  /// The branch this row shows.
  final BranchData branch;
}

/// A navigator with nothing in it — a branch never visited, or an outlet
/// whose child route has not been activated.
final class EmptyRow extends NavigationRow {
  /// Creates a row explaining why there is nothing here.
  const EmptyRow({required super.depth, required this.message});

  /// What to say.
  final String message;
}

/// Flattens [snapshot] into the rows the tree renders, depth first.
List<NavigationRow> flattenNavigation(NavigationSnapshot snapshot) {
  final rows = <NavigationRow>[];

  void visitPages(NavigatorData navigator, int depth) {
    if (navigator.pages.isEmpty) {
      rows.add(EmptyRow(depth: depth, message: 'no pages'));
      return;
    }
    for (final page in navigator.pages) {
      rows.add(PageRow(depth: depth, page: page));

      final outlet = page.outlet;
      if (outlet != null) {
        final owner = page.activation?.id;
        rows.add(
          NavigatorRow(
            depth: depth + 1,
            navigator: outlet,
            label: owner == null ? 'outlet' : 'outlet of #$owner',
          ),
        );
        visitPages(outlet, depth + 2);
      }

      final branches = page.branches;
      if (branches != null) {
        rows.add(BranchesRow(depth: depth + 1, branches: branches));
        for (final branch in branches.outlets) {
          rows.add(BranchRow(depth: depth + 2, branch: branch));
          final navigator = branch.navigator;
          if (navigator == null) {
            rows.add(
              EmptyRow(depth: depth + 3, message: 'not initialized yet'),
            );
          } else {
            visitPages(navigator, depth + 3);
          }
        }
      }
    }
  }

  rows.add(
    NavigatorRow(depth: 0, navigator: snapshot.root, label: 'Navigator (root)'),
  );
  visitPages(snapshot.root, 1);
  return rows;
}
