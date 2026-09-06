import 'package:flutter/foundation.dart';

import 'activation.dart';

/// Retained histories for one persistent branch outlet.
class NavigationBranchState {
  /// Creates branch state owned by [ownerActivationId].
  NavigationBranchState({
    required this.ownerActivationId,
    required this.branchNames,
    required this.activeBranch,
  });

  /// Activation whose `RoutingView` renders these branches.
  final int ownerActivationId;

  /// Branch declaration order.
  final List<String> branchNames;

  /// Currently visible branch.
  String activeBranch;

  /// Initialized branch histories.
  final Map<String, List<RouteFrame>> histories = {};
}

/// Materialized navigators for a branch outlet.
class NavigationBranchOutlet {
  /// Creates a materialized branch outlet.
  const NavigationBranchOutlet({
    required this.names,
    required this.activeBranch,
    required this.navigators,
  });

  /// Branch declaration order.
  final List<String> names;

  /// Currently visible branch.
  final String activeBranch;

  /// Initialized navigators by branch name.
  final Map<String, NavigatorNode> navigators;
}

/// The runtime navigation hierarchy materialized from route frames.
///
/// Frames retain URL-history and push-completion semantics. This tree is the
/// source of truth for which pages belong to each concrete `Navigator`.
class NavigationTree {
  /// Creates an empty navigation tree.
  NavigationTree() {
    rebuild();
  }

  /// Navigation transactions, oldest first.
  final List<RouteFrame> frames = [];

  /// The root navigator node.
  late NavigatorNode root;
  final Map<int?, NavigatorNode> _nodes = {};
  final Map<int, RouteActivation> _activations = {};
  final Map<LocalKey, NavigationPage> _pagesByKey = {};

  /// Persistent branch histories keyed by their owning activation.
  final Map<int, NavigationBranchState> branchStates = {};

  final Map<int, NavigationBranchOutlet> _branchOutlets = {};

  /// Reconciles [frames] into navigator-owned page stacks.
  ///
  /// Returns the branch states whose host is no longer mounted. Their
  /// retained histories are dropped here, so whatever those frames still hold
  /// open — a pending `push` future, say — is the caller's to settle.
  List<NavigationBranchState> rebuild() {
    root = NavigatorNode.root();
    _nodes
      ..clear()
      ..[null] = root;
    _activations.clear();
    _pagesByKey.clear();

    final liveOwners = <int>{};

    for (final frame in frames) {
      var navigator = _nodes[frame.anchorActivationId];
      if (navigator == null) {
        throw StateError(
          'Frame ${frame.id} targets missing outlet activation '
          '${frame.anchorActivationId}.',
        );
      }

      if (frame.isError) {
        final page = NavigationPage.error(frame: frame);
        navigator.pages.add(page);
        _pagesByKey[page.pageKey] = page;
        continue;
      }

      for (
        var segmentIndex = 0;
        segmentIndex < frame.segments.length;
        segmentIndex++
      ) {
        final segment = frame.segments[segmentIndex];
        for (final activation in segment) {
          _activations[activation.id] = activation;
          final page = NavigationPage(
            frame: frame,
            segmentIndex: segmentIndex,
            activation: activation,
          );
          navigator!.pages.add(page);
          _pagesByKey[page.pageKey] = page;
        }

        if (segment.last.opensOutlet) {
          final owner = segment.last;
          final child = NavigatorNode(ownerActivationId: owner.id);
          navigator!.children[owner.id] = child;
          _nodes[owner.id] = child;
          navigator = child;
        } else if (segment.last.opensBranches) {
          final owner = segment.last;
          liveOwners.add(owner.id);
          final child = NavigatorNode(ownerActivationId: owner.id);
          navigator!.children[owner.id] = child;
          _nodes[owner.id] = child;
          navigator = child;
        }
      }
    }

    _retainNestedOwners(liveOwners);

    final discarded = <NavigationBranchState>[];
    branchStates.removeWhere((owner, state) {
      if (liveOwners.contains(owner)) return false;
      discarded.add(state);
      return true;
    });

    // An outlet nested in a retained history only gets its navigator once
    // that history is materialized, so states are taken in whatever order
    // makes their host available rather than in map order.
    _branchOutlets.clear();
    final pending = List.of(branchStates.values);
    while (pending.isNotEmpty) {
      final resolvable = pending
          .where((state) => _nodes.containsKey(state.ownerActivationId))
          .toList();
      if (resolvable.isEmpty) break;
      pending.removeWhere(resolvable.contains);
      for (final state in resolvable) {
        _buildBranchOutlet(state);
      }
    }

    return discarded;
  }

  /// A retained branch history can host branch outlets of its own. Their
  /// state has to survive with it: dropping it would rebuild those outlets
  /// from scratch the moment the branch goes to the background.
  void _retainNestedOwners(Set<int> liveOwners) {
    var changed = true;
    while (changed) {
      changed = false;
      for (final entry in branchStates.entries) {
        if (!liveOwners.contains(entry.key)) continue;
        for (final history in entry.value.histories.values) {
          for (final frame in history) {
            for (final activation in frame.activations) {
              if (activation.opensBranches && liveOwners.add(activation.id)) {
                changed = true;
              }
            }
          }
        }
      }
    }
  }

  void _buildBranchOutlet(NavigationBranchState state) {
    final activeNavigator = _nodes[state.ownerActivationId]!;
    final navigators = <String, NavigatorNode>{
      state.activeBranch: activeNavigator,
    };
    for (final entry in state.histories.entries) {
      if (entry.key == state.activeBranch) continue;
      final navigator = NavigatorNode(
        ownerActivationId: state.ownerActivationId,
      );
      navigators[entry.key] = navigator;
      _materializeBranchHistory(
        state.ownerActivationId,
        entry.value,
        navigator,
      );
    }
    _branchOutlets[state.ownerActivationId] = NavigationBranchOutlet(
      names: state.branchNames,
      activeBranch: state.activeBranch,
      navigators: navigators,
    );
  }

  void _materializeBranchHistory(
    int ownerActivationId,
    List<RouteFrame> history,
    NavigatorNode branchRoot,
  ) {
    for (final frame in history) {
      NavigatorNode? navigator;
      if (frame.anchorActivationId == null ||
          frame.anchorActivationId == ownerActivationId) {
        navigator = branchRoot;
      } else {
        navigator = _nodes[frame.anchorActivationId];
      }
      if (navigator == null) continue;

      final ownerIndex = frame.activations.indexWhere(
        (activation) => activation.id == ownerActivationId,
      );
      final start = frame.renderStart > ownerIndex + 1
          ? frame.renderStart
          : ownerIndex + 1;
      for (final activation in frame.activations.skip(start)) {
        _activations[activation.id] = activation;
        final page = NavigationPage(
          frame: frame,
          segmentIndex: 0,
          activation: activation,
        );
        navigator!.pages.add(page);
        _pagesByKey[page.pageKey] = page;
        if (activation.opensNavigationBoundary) {
          final child = NavigatorNode(ownerActivationId: activation.id);
          navigator.children[activation.id] = child;
          _nodes[activation.id] = child;
          navigator = child;
        }
      }
    }
  }

  /// Pages rendered by the root navigator or by the outlet owned by
  /// [ownerActivationId].
  List<NavigationPage> pagesFor(int? ownerActivationId) =>
      _nodes[ownerActivationId]?.pages ?? const [];

  /// Materialized persistent branches owned by [ownerActivationId].
  NavigationBranchOutlet? branchesFor(int ownerActivationId) =>
      _branchOutlets[ownerActivationId];

  /// Looks up the activation that owns an outlet.
  RouteActivation? activation(int id) => _activations[id];

  /// Looks up the navigation page with [key].
  NavigationPage? pageForKey(LocalKey? key) =>
      key == null ? null : _pagesByKey[key];

  /// Whether a navigator on the visible path contains a page to pop.
  bool get canPop {
    for (final owner in activeNavigatorOwners) {
      if ((_nodes[owner]?.pages.length ?? 0) > 1) return true;
    }
    return false;
  }

  /// Navigator owners on the visible path, deepest first. `null` identifies
  /// the root navigator.
  Iterable<int?> get activeNavigatorOwners sync* {
    final path = <int?>[];
    NavigatorNode? navigator = root;
    while (navigator != null) {
      path.add(navigator.ownerActivationId);
      final top = navigator.pages.isEmpty
          ? null
          : navigator.pages.last.activation;
      navigator = top == null ? null : navigator.children[top.id];
    }
    yield* path.reversed;
  }
}

/// One concrete navigator and the page stack it owns.
class NavigatorNode {
  /// Creates the root navigator node.
  NavigatorNode.root() : ownerActivationId = null;

  /// Creates a navigator owned by one outlet activation.
  NavigatorNode({required this.ownerActivationId});

  /// The outlet activation that owns this navigator, or `null` for root.
  final int? ownerActivationId;

  /// Pages currently mounted in this navigator.
  final List<NavigationPage> pages = [];

  /// Child navigators keyed by the page activation that opens each outlet.
  final Map<int, NavigatorNode> children = {};
}

/// A rendered page and the frame transaction that owns it.
class NavigationPage {
  /// Creates a page backed by one route activation.
  const NavigationPage({
    required this.frame,
    required this.segmentIndex,
    required this.activation,
  });

  /// Creates the error page for an unmatched frame.
  const NavigationPage.error({required this.frame})
    : segmentIndex = 0,
      activation = null;

  /// The navigation transaction that owns this page.
  final RouteFrame frame;

  /// The frame segment from which this page was materialized.
  final int segmentIndex;

  /// The rendered activation, or `null` for an error page.
  final RouteActivation? activation;

  /// Stable identity used by Flutter's page-based Navigator.
  LocalKey get pageKey =>
      activation?.pageKey ?? ValueKey('modulith_router_error#${frame.id}');
}
