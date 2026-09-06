import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';

import '../model/router_models.dart';
import 'navigation_rows.dart';

/// The live navigator tree: which pages belong to which `Navigator`, what an
/// outlet opens, and what a branch is holding on to while in the background.
class NavigationTreeView extends StatelessWidget {
  /// Shows the tree of [snapshot].
  const NavigationTreeView({
    super.key,
    required this.snapshot,
    required this.selectedPageKey,
    required this.onPageSelected,
  });

  /// How far one level of nesting indents.
  static const double indent = 16;

  /// The tree to show.
  final NavigationSnapshot snapshot;

  /// The page currently shown in the details pane.
  final String? selectedPageKey;

  /// Called when a page row is tapped.
  final ValueChanged<String> onPageSelected;

  @override
  Widget build(BuildContext context) {
    final rows = flattenNavigation(snapshot);
    return ListView.builder(
      primary: false,
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return Padding(
          padding: EdgeInsets.only(left: row.depth * indent + denseSpacing),
          child: switch (row) {
            NavigatorRow() => _NavigatorLine(label: row.label),
            PageRow() => _PageLine(
              page: row.page,
              frame: snapshot.frame(row.page.frameId),
              isSelected: row.page.pageKey == selectedPageKey,
              onTap: () => onPageSelected(row.page.pageKey),
            ),
            BranchesRow() => _BranchesLine(branches: row.branches),
            BranchRow() => _BranchLine(branch: row.branch),
            EmptyRow() => _MutedLine(text: row.message),
          },
        );
      },
    );
  }
}

class _NavigatorLine extends StatelessWidget {
  const _NavigatorLine({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: defaultRowHeight,
      child: Row(
        children: [
          Icon(Icons.layers_outlined, size: defaultIconSize),
          const SizedBox(width: denseSpacing),
          Text(label, style: theme.subtleTextStyle),
        ],
      ),
    );
  }
}

class _PageLine extends StatelessWidget {
  const _PageLine({
    required this.page,
    required this.frame,
    required this.isSelected,
    required this.onTap,
  });

  final PageData page;
  final FrameData? frame;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activation = page.activation;
    final label = activation == null
        ? page.uri
        : '#${activation.id}  ${activation.matchedPath}';
    return InkWell(
      onTap: onTap,
      child: Container(
        height: defaultRowHeight,
        color: isSelected ? theme.colorScheme.selectedRowBackgroundColor : null,
        child: Row(
          children: [
            Icon(
              page.isError ? Icons.error_outline : Icons.article_outlined,
              size: defaultIconSize,
              color: page.isError ? theme.colorScheme.error : null,
            ),
            const SizedBox(width: denseSpacing),
            Flexible(
              child: Text(
                page.isError ? 'no route matched $label' : label,
                overflow: TextOverflow.ellipsis,
                style: theme.regularTextStyle,
              ),
            ),
            if (activation?.module case final module?) ...[
              const SizedBox(width: denseSpacing),
              RoundedLabel(labelText: module, tooltipText: 'Mounted module'),
            ],
            if (frame?.awaitsResult ?? false) ...[
              const SizedBox(width: denseSpacing),
              const RoundedLabel(
                labelText: 'awaits result',
                tooltipText:
                    'A push is waiting for the value this page is '
                    'popped with.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BranchesLine extends StatelessWidget {
  const _BranchesLine({required this.branches});

  final BranchesData branches;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: defaultRowHeight,
      child: Row(
        children: [
          Icon(Icons.call_split, size: defaultIconSize),
          const SizedBox(width: denseSpacing),
          Text(
            'branches (${branches.names.length})',
            style: theme.subtleTextStyle,
          ),
        ],
      ),
    );
  }
}

class _BranchLine extends StatelessWidget {
  const _BranchLine({required this.branch});

  final BranchData branch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = branch.isActive
        ? theme.regularTextStyle
        : theme.subtleTextStyle;
    return SizedBox(
      height: defaultRowHeight,
      child: Row(
        children: [
          Icon(
            branch.isActive
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            size: defaultIconSize,
            color: branch.isActive ? theme.colorScheme.primary : null,
          ),
          const SizedBox(width: denseSpacing),
          Text(branch.name, style: style),
          const SizedBox(width: denseSpacing),
          Text(
            branch.isActive
                ? 'active'
                : '${branch.retainedFrames} frame'
                      '${branch.retainedFrames == 1 ? '' : 's'} retained',
            style: theme.subtleTextStyle,
          ),
        ],
      ),
    );
  }
}

class _MutedLine extends StatelessWidget {
  const _MutedLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: defaultRowHeight,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(text, style: Theme.of(context).subtleTextStyle),
    ),
  );
}
