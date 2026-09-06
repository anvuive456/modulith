/// The payloads of `ext.modulith_router.*`, parsed into something the UI can
/// hold on to.
///
/// Parsing is deliberately forgiving: DevTools is often a version ahead of
/// the app it is attached to, or a version behind it, and a missing field
/// should cost one empty row rather than a red screen.
library;

/// One router mounted in the connected app.
class RouterHandle {
  const RouterHandle({
    required this.id,
    required this.currentUri,
    required this.routeCount,
    required this.frameCount,
  });

  factory RouterHandle.fromJson(Map<String, Object?> json) => RouterHandle(
    id: _int(json['id']),
    currentUri: _string(json['currentUri']),
    routeCount: _int(json['routeCount']),
    frameCount: _int(json['frameCount']),
  );

  final int id;
  final String currentUri;
  final int routeCount;
  final int frameCount;
}

/// Where the router is right now.
class RouterStateData {
  const RouterStateData({
    required this.routerId,
    required this.revision,
    required this.currentUri,
    required this.canPop,
    required this.isNavigating,
    required this.activeRouteName,
    required this.activeBranchName,
    required this.frameCount,
  });

  factory RouterStateData.fromJson(Map<String, Object?> json) =>
      RouterStateData(
        routerId: _int(json['routerId']),
        revision: _int(json['revision']),
        currentUri: _string(json['currentUri']),
        canPop: _bool(json['canPop']),
        isNavigating: _bool(json['isNavigating']),
        activeRouteName: json['activeRouteName'] as String?,
        activeBranchName: json['activeBranchName'] as String?,
        frameCount: _int(json['frameCount']),
      );

  final int routerId;
  final int revision;
  final String currentUri;
  final bool canPop;
  final bool isNavigating;
  final String? activeRouteName;
  final String? activeBranchName;
  final int frameCount;
}

/// The compiled route table: what the app can route to, whatever it is
/// showing now.
class RouteTableData {
  const RouteTableData({
    required this.routerId,
    required this.globalGuards,
    required this.routes,
  });

  factory RouteTableData.fromJson(Map<String, Object?> json) => RouteTableData(
    routerId: _int(json['routerId']),
    globalGuards: [
      for (final guard in _list(json['globalGuards'])) _string(guard),
    ],
    routes: [
      for (final route in _maps(json['routes'])) RouteNodeData.fromJson(route),
    ],
  );

  final int routerId;

  /// Guards that run before every navigation, ahead of any route's own.
  final List<String> globalGuards;
  final List<RouteNodeData> routes;
}

/// One declared route, compiled.
class RouteNodeData {
  const RouteNodeData({
    required this.id,
    required this.kind,
    required this.path,
    required this.pattern,
    required this.debugPath,
    required this.name,
    required this.isPathless,
    required this.params,
    required this.guards,
    required this.childRouting,
    required this.reuse,
    required this.branch,
    required this.redirectTo,
    required this.isComputedRedirect,
    required this.branches,
    required this.children,
  });

  factory RouteNodeData.fromJson(Map<String, Object?> json) => RouteNodeData(
    id: _int(json['id']),
    kind: _string(json['kind']),
    path: _string(json['path']),
    pattern: _string(json['pattern']),
    debugPath: _string(json['debugPath']),
    name: json['name'] as String?,
    isPathless: _bool(json['isPathless']),
    params: [for (final param in _list(json['params'])) _string(param)],
    guards: [for (final guard in _list(json['guards'])) _string(guard)],
    childRouting: _string(json['childRouting']),
    reuse: _string(json['reuse']),
    branch: json['branch'] as String?,
    redirectTo: json['redirectTo'] as String?,
    isComputedRedirect: _bool(json['isComputedRedirect']),
    branches: [
      for (final branch in _maps(json['branches']))
        (
          name: _string(branch['name']),
          initial: _string(branch['initialLocation']),
        ),
    ],
    children: [
      for (final child in _maps(json['children']))
        RouteNodeData.fromJson(child),
    ],
  );

  final int id;

  /// `module`, `view` or `redirect`.
  final String kind;

  /// The path as declared, relative to the parent.
  final String path;
  final String pattern;

  /// The full path from the root, e.g. `/users/:id`.
  final String debugPath;
  final String? name;

  /// Whether this route consumes nothing — a shell.
  final bool isPathless;
  final List<String> params;
  final List<String> guards;
  final String childRouting;
  final String reuse;

  /// The branch that declared this route, when its parent hosts branches.
  final String? branch;

  /// Where a `RedirectRoute` with a fixed target sends navigation.
  final String? redirectTo;

  /// Whether a `RedirectRoute` computes its target per navigation, in which
  /// case there is nothing to show until one resolves.
  final bool isComputedRedirect;

  /// The branches this route hosts, if any.
  final List<({String name, String initial})> branches;
  final List<RouteNodeData> children;
}

/// What matching a URL would do, without doing it.
class MatchTraceData {
  const MatchTraceData({
    required this.uri,
    required this.segments,
    required this.isMatch,
    required this.chain,
    required this.attempts,
    required this.redirects,
    required this.redirectError,
    required this.redirectLoop,
    required this.destination,
    required this.destinationIsMatch,
    required this.guards,
  });

  factory MatchTraceData.fromJson(Map<String, Object?> json) => MatchTraceData(
    uri: _string(json['uri']),
    segments: [for (final segment in _list(json['segments'])) _string(segment)],
    isMatch: _bool(json['isMatch']),
    chain: [
      for (final match in _maps(json['chain']))
        (
          routeId: _int(match['routeId']),
          debugPath: _string(match['debugPath']),
          matchedPath: _string(match['matchedPath']),
          kind: _string(match['kind']),
          params: _stringMap(match['params']),
        ),
    ],
    attempts: [
      for (final attempt in _maps(json['attempts']))
        (
          routeId: _int(attempt['routeId']),
          debugPath: _string(attempt['debugPath']),
          depth: _int(attempt['depth']),
          outcome: _string(attempt['outcome']),
          consumedUpTo: _int(attempt['consumedUpTo']),
          inChain: _bool(attempt['inChain']),
        ),
    ],
    redirects: [
      for (final hop in _maps(json['redirects']))
        (
          from: _string(hop['from']),
          to: _string(hop['to']),
          routePath: _string(hop['routePath']),
        ),
    ],
    redirectError: json['redirectError'] as String?,
    redirectLoop: _bool(json['redirectLoop']),
    destination: _string(json['destination']),
    destinationIsMatch: _bool(json['destinationIsMatch']),
    guards: [
      for (final guard in _maps(json['guards']))
        (
          guard: _string(guard['guard']),
          routePath: guard['routePath'] as String?,
          isGlobal: _bool(guard['isGlobal']),
        ),
    ],
  );

  /// The URL that was matched, resolved the way the router would resolve it.
  final String uri;
  final List<String> segments;
  final bool isMatch;

  /// The chain that matched, root first.
  final List<
    ({
      int routeId,
      String debugPath,
      String matchedPath,
      String kind,
      Map<String, String> params,
    })
  >
  chain;

  /// Every route the matcher tried, in order — the answer to "why does this
  /// URL not match?".
  final List<
    ({
      int routeId,
      String debugPath,
      int depth,
      String outcome,
      int consumedUpTo,
      bool inChain,
    })
  >
  attempts;

  /// The redirect hops between [uri] and [destination].
  final List<({String from, String to, String routePath})> redirects;

  /// What a computed redirect threw, if it did.
  final String? redirectError;

  /// Whether the hops were cut short because they were going in circles.
  final bool redirectLoop;

  /// Where the navigation would end up.
  final String destination;
  final bool destinationIsMatch;

  /// The guards that would run at [destination], in pipeline order.
  final List<({String guard, String? routePath, bool isGlobal})> guards;

  /// The ids of the routes that matched, for highlighting the table.
  Set<int> get matchedRouteIds => {for (final match in chain) match.routeId};
}

/// The live navigation state: frames, and the navigators they materialized
/// into.
class NavigationSnapshot {
  const NavigationSnapshot({
    required this.routerId,
    required this.revision,
    required this.currentUri,
    required this.frames,
    required this.root,
  });

  factory NavigationSnapshot.fromJson(Map<String, Object?> json) =>
      NavigationSnapshot(
        routerId: _int(json['routerId']),
        revision: _int(json['revision']),
        currentUri: _string(json['currentUri']),
        frames: [
          for (final frame in _maps(json['frames'])) FrameData.fromJson(frame),
        ],
        root: NavigatorData.fromJson(_map(json['root'])),
      );

  final int routerId;
  final int revision;
  final String currentUri;
  final List<FrameData> frames;
  final NavigatorData root;

  /// The frame with [id], or `null` when it is no longer on the stack.
  FrameData? frame(int id) {
    for (final frame in frames) {
      if (frame.id == id) return frame;
    }
    return null;
  }

  /// The page keyed [pageKey], wherever in the tree it hangs.
  PageData? page(String pageKey) => _findPage(root, pageKey);

  static PageData? _findPage(NavigatorData node, String pageKey) {
    for (final page in node.pages) {
      if (page.pageKey == pageKey) return page;
      final outlet = page.outlet;
      if (outlet != null) {
        final found = _findPage(outlet, pageKey);
        if (found != null) return found;
      }
      for (final branch in page.branches?.outlets ?? const <BranchData>[]) {
        final navigator = branch.navigator;
        if (navigator == null) continue;
        final found = _findPage(navigator, pageKey);
        if (found != null) return found;
      }
    }
    return null;
  }
}

/// One navigation transaction. `go` rewrites the single frame the stack has,
/// `push` adds one, and one frame can own pages in several navigators.
class FrameData {
  const FrameData({
    required this.id,
    required this.uri,
    required this.isError,
    required this.awaitsResult,
    required this.renderStart,
    required this.anchorActivationId,
    required this.extra,
    required this.activations,
  });

  factory FrameData.fromJson(Map<String, Object?> json) => FrameData(
    id: _int(json['id']),
    uri: _string(json['uri']),
    isError: _bool(json['isError']),
    awaitsResult: _bool(json['awaitsResult']),
    renderStart: _int(json['renderStart']),
    anchorActivationId: json['anchorActivationId'] as int?,
    extra: json['extra'],
    activations: [for (final id in _list(json['activations'])) _int(id)],
  );

  final int id;
  final String uri;
  final bool isError;

  /// Whether a `push` is still waiting for the value this frame is popped
  /// with.
  final bool awaitsResult;
  final int renderStart;
  final int? anchorActivationId;
  final Object? extra;
  final List<int> activations;
}

/// One concrete `Navigator` and the pages it owns.
class NavigatorData {
  const NavigatorData({required this.ownerActivationId, required this.pages});

  factory NavigatorData.fromJson(Map<String, Object?> json) => NavigatorData(
    ownerActivationId: json['ownerActivationId'] as int?,
    pages: [for (final page in _maps(json['pages'])) PageData.fromJson(page)],
  );

  /// The activation whose outlet owns this navigator, or `null` for the root.
  final int? ownerActivationId;
  final List<PageData> pages;
}

/// One page, plus whatever it opens below itself.
class PageData {
  const PageData({
    required this.pageKey,
    required this.frameId,
    required this.isError,
    required this.uri,
    required this.activation,
    required this.outlet,
    required this.branches,
  });

  factory PageData.fromJson(Map<String, Object?> json) {
    final activation = json['activation'];
    final outlet = json['outlet'];
    final branches = json['branches'];
    return PageData(
      pageKey: _string(json['pageKey']),
      frameId: _int(json['frameId']),
      isError: _bool(json['isError']),
      uri: _string(json['uri']),
      activation: activation == null
          ? null
          : ActivationData.fromJson(_map(activation)),
      outlet: outlet == null ? null : NavigatorData.fromJson(_map(outlet)),
      branches: branches == null ? null : BranchesData.fromJson(_map(branches)),
    );
  }

  final String pageKey;
  final int frameId;

  /// Whether this is the page shown for a URL nothing matched.
  final bool isError;
  final String uri;
  final ActivationData? activation;

  /// The navigator this page's `RoutingView` opens, for a route using
  /// `ChildRouting.outlet`.
  final NavigatorData? outlet;

  /// The persistent branches this page hosts, for `ChildRouting.branches`.
  final BranchesData? branches;
}

/// The persistent branches one page hosts.
class BranchesData {
  const BranchesData({
    required this.ownerActivationId,
    required this.active,
    required this.names,
    required this.outlets,
  });

  factory BranchesData.fromJson(Map<String, Object?> json) => BranchesData(
    ownerActivationId: _int(json['ownerActivationId']),
    active: _string(json['active']),
    names: [for (final name in _list(json['names'])) _string(name)],
    outlets: [
      for (final outlet in _maps(json['outlets'])) BranchData.fromJson(outlet),
    ],
  );

  final int ownerActivationId;
  final String active;
  final List<String> names;
  final List<BranchData> outlets;
}

/// One branch: the stack it is showing, or the stack it is keeping while in
/// the background.
class BranchData {
  const BranchData({
    required this.name,
    required this.isActive,
    required this.retainedFrames,
    required this.navigator,
  });

  factory BranchData.fromJson(Map<String, Object?> json) {
    final navigator = json['navigator'];
    return BranchData(
      name: _string(json['name']),
      isActive: _bool(json['isActive']),
      retainedFrames: _int(json['retainedFrames']),
      navigator: navigator == null
          ? null
          : NavigatorData.fromJson(_map(navigator)),
    );
  }

  final String name;
  final bool isActive;

  /// How many frames this branch is holding on to. Zero means it has never
  /// been visited.
  final int retainedFrames;
  final NavigatorData? navigator;
}

/// One live route activation — the module behind a page and what it was
/// built with.
class ActivationData {
  const ActivationData({
    required this.id,
    required this.routeId,
    required this.routePath,
    required this.kind,
    required this.name,
    required this.matchedPath,
    required this.uri,
    required this.params,
    required this.query,
    required this.extra,
    required this.module,
    required this.childRouting,
    required this.reuse,
    required this.guards,
    required this.opensOutlet,
    required this.opensBranches,
  });

  factory ActivationData.fromJson(Map<String, Object?> json) => ActivationData(
    id: _int(json['id']),
    routeId: _int(json['routeId']),
    routePath: _string(json['routePath']),
    kind: _string(json['kind']),
    name: json['name'] as String?,
    matchedPath: _string(json['matchedPath']),
    uri: _string(json['uri']),
    params: _stringMap(json['params']),
    query: _stringMap(json['query']),
    extra: json['extra'],
    module: json['module'] as String?,
    childRouting: _string(json['childRouting']),
    reuse: _string(json['reuse']),
    guards: [for (final guard in _list(json['guards'])) _string(guard)],
    opensOutlet: _bool(json['opensOutlet']),
    opensBranches: _bool(json['opensBranches']),
  );

  final int id;
  final int routeId;

  /// The declared path this activation came from, e.g. `/users/:id`.
  final String routePath;

  /// `module`, `view` or `redirect`.
  final String kind;
  final String? name;

  /// The part of the URL this route consumed, e.g. `/users/42`.
  final String matchedPath;
  final String uri;
  final Map<String, String> params;
  final Map<String, String> query;

  /// A description of the `extra` this activation was navigated with — never
  /// the object itself.
  final Object? extra;

  /// The mounted module's type, or `null` for a `ViewRoute`.
  final String? module;
  final String childRouting;
  final String reuse;
  final List<String> guards;
  final bool opensOutlet;
  final bool opensBranches;
}

int _int(Object? value) => value is int ? value : 0;

bool _bool(Object? value) => value is bool && value;

String _string(Object? value) => value is String ? value : '$value';

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

Map<String, String> _stringMap(Object? value) => value is Map
    ? {for (final entry in value.entries) '${entry.key}': _string(entry.value)}
    : const {};

List<Object?> _list(Object? value) => value is List ? value : const [];

List<Map<String, Object?>> _maps(Object? value) => [
  for (final item in _list(value)) _map(item),
];
