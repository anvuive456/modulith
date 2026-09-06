import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';

import '../model/router_models.dart';
import '../router_controller.dart';
import 'route_table_rows.dart';

/// The compiled route table, and a URL tester that says what the router
/// would do with a location — which routes it would try, where a redirect
/// would take it, and which guards would run there.
///
/// Nothing here navigates: matching a URL is a pure question, so it can be
/// asked of a running app without moving it.
class RouteTableTab extends StatefulWidget {
  /// Shows the table of [controller]'s selected router.
  const RouteTableTab({super.key, required this.controller});

  /// The extension's state.
  final RouterExtensionController controller;

  @override
  State<RouteTableTab> createState() => _RouteTableTabState();
}

class _RouteTableTabState extends State<RouteTableTab> {
  final _url = TextEditingController();
  final _filter = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: defaultSpacing,
            vertical: denseSpacing,
          ),
          child: Row(
            children: [
              Expanded(
                child: DevToolsTextField(
                  controller: _url,
                  labelText: 'Test a URL',
                  hintText: '/users/42',
                  onSubmitted: controller.testUrl,
                ),
              ),
              const SizedBox(width: denseSpacing),
              DevToolsButton(
                label: 'Match',
                onPressed: () => controller.testUrl(_url.text),
              ),
            ],
          ),
        ),
        const Divider(height: 0),
        Expanded(
          child: SplitPane(
            axis: Axis.horizontal,
            initialFractions: const [0.5, 0.5],
            minSizes: const [240, 240],
            children: [
              RoundedOutlinedBorder(
                clip: true,
                child: Column(
                  children: [
                    AreaPaneHeader(
                      title: const Text('Route table'),
                      actions: [
                        SizedBox(
                          width: 180,
                          child: DevToolsTextField(
                            controller: _filter,
                            labelText: 'Filter',
                            onChanged: controller.filterRoutes,
                          ),
                        ),
                      ],
                    ),
                    Expanded(child: _RouteTree(controller: controller)),
                  ],
                ),
              ),
              RoundedOutlinedBorder(
                clip: true,
                child: Column(
                  children: [
                    const AreaPaneHeader(title: Text('Match trace')),
                    Expanded(child: _TracePanel(controller: controller)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RouteTree extends StatelessWidget {
  const _RouteTree({required this.controller});

  final RouterExtensionController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        controller.routeTable,
        controller.routeFilter,
        controller.trace,
      ]),
      builder: (context, _) {
        final table = controller.routeTable.value;
        if (table == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = flattenRouteTable(
          table.routes,
          query: controller.routeFilter.value,
        );
        if (rows.isEmpty) {
          return Center(
            child: Text(
              'No route matches the filter.',
              style: theme.subtleTextStyle,
            ),
          );
        }
        final matched = controller.trace.value?.matchedRouteIds ?? const {};
        return ListView.builder(
          primary: false,
          itemCount: rows.length + (table.globalGuards.isEmpty ? 0 : 1),
          itemBuilder: (context, index) {
            if (table.globalGuards.isNotEmpty) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: denseSpacing,
                    vertical: densePadding,
                  ),
                  child: Text(
                    'Global guards: ${table.globalGuards.join(', ')}',
                    style: theme.subtleTextStyle,
                  ),
                );
              }
              index -= 1;
            }
            final row = rows[index];
            return _RouteLine(
              node: row.node,
              depth: row.depth,
              isMatched: matched.contains(row.node.id),
            );
          },
        );
      },
    );
  }
}

class _RouteLine extends StatelessWidget {
  const _RouteLine({
    required this.node,
    required this.depth,
    required this.isMatched,
  });

  final RouteNodeData node;
  final int depth;
  final bool isMatched;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: defaultRowHeight,
      padding: EdgeInsets.only(left: depth * 16 + denseSpacing),
      color: isMatched ? theme.colorScheme.selectedRowBackgroundColor : null,
      child: Row(
        children: [
          Icon(_iconFor(node), size: defaultIconSize),
          const SizedBox(width: denseSpacing),
          Flexible(
            child: Text(
              node.isPathless ? '(pathless)' : node.pattern,
              overflow: TextOverflow.ellipsis,
              style: theme.fixedFontStyle,
            ),
          ),
          if (node.name case final name?) ...[
            const SizedBox(width: denseSpacing),
            RoundedLabel(labelText: name, tooltipText: 'Route name'),
          ],
          if (node.branch case final branch?) ...[
            const SizedBox(width: denseSpacing),
            RoundedLabel(
              labelText: 'branch: $branch',
              tooltipText: 'Declared by this branch of its parent',
            ),
          ],
          if (node.childRouting != 'stack') ...[
            const SizedBox(width: denseSpacing),
            RoundedLabel(labelText: node.childRouting),
          ],
          if (node.guards.isNotEmpty) ...[
            const SizedBox(width: denseSpacing),
            RoundedLabel(
              labelText: node.guards.join(', '),
              tooltipText: 'Guards on this route',
            ),
          ],
          if (node.kind == 'redirect') ...[
            const SizedBox(width: denseSpacing),
            Text(
              node.isComputedRedirect
                  ? '→ computed per navigation'
                  : '→ ${node.redirectTo}',
              style: theme.subtleTextStyle,
            ),
          ],
          const SizedBox(width: denseSpacing),
        ],
      ),
    );
  }

  static IconData _iconFor(RouteNodeData node) => switch (node.kind) {
    'module' => Icons.widgets_outlined,
    'redirect' => Icons.subdirectory_arrow_right,
    _ => Icons.crop_square,
  };
}

class _TracePanel extends StatelessWidget {
  const _TracePanel({required this.controller});

  final RouterExtensionController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([controller.trace, controller.traceError]),
      builder: (context, _) {
        final error = controller.traceError.value;
        if (error != null) {
          return _Centered(text: error, style: theme.errorTextStyle);
        }
        final trace = controller.trace.value;
        if (trace == null) {
          return _Centered(
            text:
                'Type a URL above to see which routes the table would try, '
                'where a redirect would send it, and which guards would run.',
            style: theme.subtleTextStyle,
          );
        }
        return ListView(
          primary: false,
          padding: const EdgeInsets.all(denseSpacing),
          children: [
            _Headline(trace: trace),
            if (trace.isMatch) ...[
              _Block(
                title: 'Matched chain',
                lines: [
                  for (final match in trace.chain)
                    '${match.debugPath}  →  ${match.matchedPath}'
                        '${match.params.isEmpty ? '' : '  ${match.params}'}',
                ],
              ),
            ] else
              _Block(
                title: 'Routes tried',
                lines: [
                  for (final attempt in trace.attempts)
                    '${'  ' * attempt.depth}${attempt.debugPath}  —  '
                        '${attempt.outcome == 'patternMismatch' ? 'pattern did not fit' : 'consumed ${attempt.consumedUpTo} segment${attempt.consumedUpTo == 1 ? '' : 's'}, abandoned'}',
                ],
                empty: 'The table is empty.',
              ),
            if (trace.redirects.isNotEmpty)
              _Block(
                title: 'Redirects',
                lines: [
                  for (final hop in trace.redirects)
                    '${hop.from}  →  ${hop.to}   (${hop.routePath})',
                  if (trace.redirectLoop) 'Stopped: this is going in circles.',
                ],
              ),
            if (trace.redirectError case final failure?)
              _Block(title: 'Redirect failed', lines: [failure]),
            _Block(
              title: 'Guards that would run',
              lines: [
                for (final guard in trace.guards)
                  '${guard.guard}${guard.isGlobal ? '  (global)' : '  on ${guard.routePath}'}',
              ],
              empty: 'None — nothing would be checked.',
            ),
          ],
        );
      },
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.trace});

  final MatchTraceData trace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final landed = trace.destination != trace.uri;
    final ok = trace.isMatch && trace.destinationIsMatch;
    return Padding(
      padding: const EdgeInsets.only(bottom: defaultSpacing),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.report_gmailerrorred,
            size: defaultIconSize,
            color: ok ? theme.colorScheme.primary : theme.colorScheme.error,
          ),
          const SizedBox(width: denseSpacing),
          Expanded(
            child: Text(
              ok
                  ? landed
                        ? '${trace.uri} lands on ${trace.destination}'
                        : '${trace.uri} matches'
                  : trace.isMatch
                  ? '${trace.uri} redirects to ${trace.destination}, which '
                        'matches nothing'
                  : 'No route matches ${trace.uri}',
              style: theme.regularTextStyle,
            ),
          ),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.title, required this.lines, this.empty});

  final String title;
  final List<String> lines;
  final String? empty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: defaultSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.boldTextStyle),
          const SizedBox(height: densePadding),
          if (lines.isEmpty && empty != null)
            Text(empty!, style: theme.subtleTextStyle)
          else
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: densePadding),
                child: SelectableText(line, style: theme.fixedFontStyle),
              ),
        ],
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(defaultSpacing),
      child: Text(text, textAlign: TextAlign.center, style: style),
    ),
  );
}
