import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';

import '../model/router_models.dart';
import '../router_client.dart';
import '../router_controller.dart';
import 'navigation_tree_view.dart';
import 'page_details_view.dart';
import 'route_table_tab.dart';

/// The extension: a header saying where the router is, and the navigation
/// tree below it.
class RouterExtensionBody extends StatefulWidget {
  /// Watches the app through [client].
  const RouterExtensionBody({super.key, required this.client});

  /// The app under inspection.
  final RouterClient client;

  @override
  State<RouterExtensionBody> createState() => _RouterExtensionBodyState();
}

class _RouterExtensionBodyState extends State<RouterExtensionBody> {
  late RouterExtensionController _controller;

  @override
  void initState() {
    super.initState();
    _controller = RouterExtensionController(widget.client)..init();
  }

  @override
  void didUpdateWidget(RouterExtensionBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new client means a new app — a hot restart, or a reconnection.
    if (!identical(oldWidget.client, widget.client)) {
      _controller.dispose();
      _controller = RouterExtensionController(widget.client)..init();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _Header(controller: _controller),
      const Divider(height: 0),
      Expanded(child: _Body(controller: _controller)),
    ],
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final RouterExtensionController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: defaultSpacing,
        vertical: denseSpacing,
      ),
      child: Row(
        children: [
          ListenableBuilder(
            listenable: Listenable.merge([
              controller.routers,
              controller.selectedRouterId,
            ]),
            builder: (context, _) {
              final routers = controller.routers.value;
              final selected = controller.selectedRouterId.value;
              if (routers.length < 2) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: defaultSpacing),
                child: RoundedDropDownButton<int>(
                  value: selected,
                  isDense: true,
                  onChanged: (id) {
                    if (id != null) controller.selectRouter(id);
                  },
                  items: [
                    for (final router in routers)
                      DropdownMenuItem(
                        value: router.id,
                        child: Text('router #${router.id}'),
                      ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: ValueListenableBuilder<RouterStateData?>(
              valueListenable: controller.state,
              builder: (context, state, _) {
                if (state == null) {
                  return Text('—', style: theme.subtleTextStyle);
                }
                return Row(
                  children: [
                    Flexible(
                      child: Text(
                        state.currentUri,
                        overflow: TextOverflow.ellipsis,
                        style: theme.fixedFontStyle,
                      ),
                    ),
                    const SizedBox(width: defaultSpacing),
                    if (state.activeRouteName case final name?)
                      _Chip(label: 'name: $name'),
                    if (state.activeBranchName case final branch?)
                      _Chip(label: 'branch: $branch'),
                    if (state.canPop) const _Chip(label: 'can pop'),
                    if (state.isNavigating) const _Chip(label: 'navigating'),
                    _Chip(label: 'rev ${state.revision}'),
                  ],
                );
              },
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: controller.isRefreshing,
            builder: (context, isRefreshing, _) => DevToolsButton.iconOnly(
              icon: Icons.refresh,
              tooltip: 'Refresh',
              onPressed: isRefreshing ? null : () => controller.refresh(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.controller});

  final RouterExtensionController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        controller.navigation,
        controller.selectedPageKey,
        controller.error,
        controller.routers,
      ]),
      builder: (context, _) {
        final snapshot = controller.navigation.value;
        final selectedPageKey = controller.selectedPageKey.value;
        final error = controller.error.value;
        final routers = controller.routers.value;

        if (error != null) {
          return _Placeholder(
            icon: Icons.error_outline,
            title: 'The router did not answer',
            detail: error,
          );
        }
        if (routers.isEmpty) {
          return const _Placeholder(
            icon: Icons.explore_off_outlined,
            title: 'No router in this app',
            detail:
                'This tab needs a RouterModule mounted in a debug build. '
                'A release build registers no inspector.',
          );
        }
        if (snapshot == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return DefaultTabController(
          length: 2,
          child: Column(
            spacing: 10,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(text: 'Navigation'),
                    Tab(text: 'Route table'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _NavigationTab(
                      controller: controller,
                      snapshot: snapshot,
                      selectedPageKey: selectedPageKey,
                    ),
                    RouteTableTab(controller: controller),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NavigationTab extends StatelessWidget {
  const _NavigationTab({
    required this.controller,
    required this.snapshot,
    required this.selectedPageKey,
  });

  final RouterExtensionController controller;
  final NavigationSnapshot snapshot;
  final String? selectedPageKey;

  @override
  Widget build(BuildContext context) {
    final page = selectedPageKey == null
        ? null
        : snapshot.page(selectedPageKey!);
    return SplitPane(
      axis: Axis.horizontal,
      initialFractions: const [0.55, 0.45],
      minSizes: const [240, 240],
      children: [
        RoundedOutlinedBorder(
          clip: true,
          child: Column(
            children: [
              const AreaPaneHeader(title: Text('Navigation')),
              Expanded(
                child: NavigationTreeView(
                  snapshot: snapshot,
                  selectedPageKey: selectedPageKey,
                  onPageSelected: controller.selectPage,
                ),
              ),
            ],
          ),
        ),
        RoundedOutlinedBorder(
          clip: true,
          child: Column(
            children: [
              const AreaPaneHeader(title: Text('Details')),
              Expanded(
                child: PageDetailsView(
                  page: page,
                  frame: page == null ? null : snapshot.frame(page.frameId),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: denseSpacing),
    child: RoundedLabel(labelText: label),
  );
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(extraLargeSpacing),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: theme.colorScheme.outline),
            const SizedBox(height: defaultSpacing),
            Text(title, style: theme.boldTextStyle),
            const SizedBox(height: denseSpacing),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: theme.subtleTextStyle,
            ),
          ],
        ),
      ),
    );
  }
}
