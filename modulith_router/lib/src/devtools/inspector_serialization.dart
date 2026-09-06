/// Turns the router's model into the JSON the DevTools extension reads.
///
/// Two rules hold everywhere in this file, because a debugging tool that
/// crashes the app it is debugging is worse than no tool at all:
///
/// * **Nothing throws.** Anything that comes from application code — an
///   `extra`, a `toString()` — goes through [describeValue], which answers
///   with a description even when the object misbehaves.
/// * **Nothing is retained.** Every function returns plain maps and lists.
///   Holding a `RouteActivation` in a log would keep a disposed module and
///   its whole scope alive.
library;

import 'package:flutter/foundation.dart';

import '../model/route_definition.dart';
import '../model/route_match.dart';
import '../model/route_matcher.dart';
import '../runtime/activation.dart';
import '../runtime/guards.dart';
import '../runtime/navigation_tree.dart';
import '../runtime/router_observer.dart';
import '../runtime/router_service.dart';

/// How many characters of a `toString()` are worth sending.
const int _maxStringLength = 200;

/// How many entries of a collection are worth sending.
const int _maxCollectionLength = 20;

/// Describes a value that came from application code — an `extra`, mostly.
///
/// Primitives survive as themselves so the UI can show them; anything else
/// becomes `TodoArgs#a1b2c`, which identifies the object without pretending
/// to serialize it.
Object? describeValue(Object? value) {
  try {
    if (value == null || value is bool || value is num) return value;
    if (value is String) return _truncate(value);
    if (value is Enum) return value.name;
    if (value is Uri) return value.toString();
    if (value is Iterable) {
      return [
        for (final item in value.take(_maxCollectionLength))
          describeValue(item),
        if (value.length > _maxCollectionLength) '…',
      ];
    }
    if (value is Map) {
      return {
        for (final entry in value.entries.take(_maxCollectionLength))
          entry.key.toString(): describeValue(entry.value),
        if (value.length > _maxCollectionLength) '…': null,
      };
    }
    return describeIdentity(value);
  } catch (_) {
    // A broken `toString`, a getter that throws, a cyclic structure.
    return '<undescribable ${value.runtimeType}>';
  }
}

String _truncate(String value) => value.length <= _maxStringLength
    ? value
    : '${value.substring(0, _maxStringLength)}…';

String _kindOf(RouteDefinition definition) => switch (definition) {
  ModuleRoute() => 'module',
  ViewRoute() => 'view',
  RedirectRoute() => 'redirect',
};

List<String> _guardNames(List<RouteGuard> guards) => [
  for (final guard in guards) guard.runtimeType.toString(),
];

/// The router's current position, for the DevTools header.
Map<String, Object?> describeState(RouterService service, int routerId) => {
  'type': 'modulith_router.state',
  'routerId': routerId,
  'revision': service.revision,
  'currentUri': service.currentUri.toString(),
  'canPop': service.canPop,
  'isNavigating': service.isNavigating,
  'activeRouteName': service.activeRouteName,
  'activeBranchName': service.activeBranchName,
  'frameCount': service.frames.length,
};

/// The compiled route table, as a tree — what the app *can* route to,
/// independently of where it currently is.
Map<String, Object?> describeRouteTable(
  RouterService service,
  int routerId,
) => {
  'type': 'modulith_router.routeTable',
  'routerId': routerId,
  'globalGuards': _guardNames(service.globalGuards),
  'routes': [for (final route in service.matcher.roots) describeRoute(route)],
};

/// One node of the compiled route table, with its children.
Map<String, Object?> describeRoute(CompiledRoute route, {String? branch}) {
  final definition = route.definition;
  final json = <String, Object?>{
    'id': route.id,
    'kind': _kindOf(definition),
    'path': definition.path,
    'pattern': route.pattern.toString(),
    'debugPath': route.debugPath,
    'name': definition.name,
    'isPathless': route.pattern.isPathless,
    'params': [for (final parameter in route.pattern.parameterNames) parameter],
    'guards': _guardNames(definition.guards),
    'childRouting': definition.childRouting.name,
    'reuse': definition.reuse.name,
    'hasPageBuilder': definition.pageBuilder != null,
    // Set on a child of a branch host: which branch owns it.
    'branch': ?branch,
  };

  if (definition is RedirectRoute) {
    // A computed target depends on the URL that matched, so there is
    // nothing to show until a navigation actually resolves one.
    json['redirectTo'] = definition.redirect == null
        ? definition.target(
            RedirectContext(
              uri: Uri(path: '/'),
              pathParams: const {},
            ),
          )
        : null;
    json['isComputedRedirect'] = definition.redirect != null;
  }

  if (definition is ModuleRoute && definition.branches.isNotEmpty) {
    json['branchInitialization'] = definition.branchInitialization.name;
    json['branches'] = [
      for (final branch in definition.branches)
        {'name': branch.name, 'initialLocation': branch.initialLocation},
    ];
  }

  json['children'] = [
    for (final child in route.children)
      describeRoute(child, branch: _branchOf(definition, child)),
  ];
  return json;
}

/// Which branch of [definition] declared [child], or `null` when the parent
/// hosts no branches. Matched by identity, the way the router matches it.
String? _branchOf(RouteDefinition definition, CompiledRoute child) {
  if (definition is! ModuleRoute) return null;
  for (final branch in definition.branches) {
    for (final route in branch.routes) {
      if (identical(route, child.definition)) return branch.name;
    }
  }
  return null;
}

/// How many redirect hops a trace follows before calling it a loop.
const int _maxTracedRedirects = 5;

/// Matches [uri] without navigating, and explains the outcome: every route
/// the matcher tried, the chain it settled on, where a redirect would send
/// it, and which guards would run there.
///
/// Nothing here has a side effect on the router. The one piece of
/// application code it runs is a computed `RedirectRoute` target, which is a
/// pure function by contract — and if it throws anyway, that is reported
/// rather than propagated.
Map<String, Object?> describeMatchTrace(
  RouterService service,
  int routerId,
  Uri uri,
) {
  final attempts = <MatchAttempt>[];
  final matches = service.matcher.match(uri, trace: attempts);
  final matchedIds = {
    for (final match in matches ?? const <RouteMatch>[]) match.route.id,
  };

  final redirects = <Map<String, Object?>>[];
  var destination = uri;
  var resolved = matches;
  String? redirectError;
  var looped = false;

  while (resolved != null) {
    final definition = resolved.last.definition;
    if (definition is! RedirectRoute) break;
    if (redirects.length >= _maxTracedRedirects) {
      looped = true;
      break;
    }
    final String target;
    try {
      target = definition.target(
        RedirectContext(uri: destination, pathParams: resolved.last.pathParams),
      );
    } catch (error) {
      redirectError = '$error';
      break;
    }
    final next = destination.resolve(target);
    redirects.add({
      'from': destination.toString(),
      'to': next.toString(),
      'routePath': resolved.last.route.debugPath,
    });
    destination = next;
    resolved = service.matcher.match(next);
  }

  return {
    'type': 'modulith_router.matchTrace',
    'routerId': routerId,
    'uri': uri.toString(),
    'segments': [
      for (final segment in uri.pathSegments)
        if (segment.isNotEmpty) segment,
    ],
    'isMatch': matches != null,
    'chain': [
      for (final match in matches ?? const <RouteMatch>[])
        {
          'routeId': match.route.id,
          'debugPath': match.route.debugPath,
          'pattern': match.route.pattern.toString(),
          'kind': _kindOf(match.definition),
          'name': match.definition.name,
          'matchedPath': match.matchedPath,
          'params': Map<String, String>.of(match.pathParams),
        },
    ],
    'attempts': [
      for (final attempt in attempts)
        {
          'routeId': attempt.route.id,
          'debugPath': attempt.route.debugPath,
          'pattern': attempt.route.pattern.toString(),
          'depth': attempt.depth,
          'outcome': attempt.outcome.name,
          'consumedUpTo': attempt.consumedUpTo,
          // A route can consume its segments and still be abandoned, because
          // nothing under it took the rest of the URL.
          'inChain': matchedIds.contains(attempt.route.id),
        },
    ],
    'redirects': redirects,
    'redirectError': redirectError,
    'redirectLoop': looped,
    'destination': destination.toString(),
    'destinationIsMatch': resolved != null,
    // The guards of where the navigation would end up, in the order the
    // pipeline would run them: the router's own first, then root to leaf.
    'guards': [
      for (final guard in service.globalGuards)
        {
          'guard': guard.runtimeType.toString(),
          'routePath': null,
          'isGlobal': true,
        },
      for (final match in resolved ?? const <RouteMatch>[])
        for (final guard in match.definition.guards)
          {
            'guard': guard.runtimeType.toString(),
            'routePath': match.route.debugPath,
            'isGlobal': false,
          },
    ],
  };
}

/// The live navigation state: the frames the router owns, and the tree of
/// concrete navigators they were materialized into.
Map<String, Object?> describeNavigationTree(
  RouterService service,
  NavigationTree navigation,
  int routerId,
) => {
  'type': 'modulith_router.navigationTree',
  'routerId': routerId,
  'revision': service.revision,
  'currentUri': service.currentUri.toString(),
  'frames': [for (final frame in service.frames) describeFrame(frame)],
  'root': describeNavigator(navigation, navigation.root),
};

/// One navigation transaction. A frame is not a page: `go` rewrites the one
/// frame the stack has, `push` adds one, and each frame can own several
/// pages across several navigators.
Map<String, Object?> describeFrame(RouteFrame frame) => {
  'id': frame.id,
  'uri': frame.uri.toString(),
  'isError': frame.isError,
  'renderStart': frame.renderStart,
  'anchorActivationId': frame.anchorActivationId,
  'awaitsResult': frame.completer != null && !frame.completer!.isCompleted,
  'extra': describeValue(frame.extra),
  'activations': [for (final activation in frame.activations) activation.id],
  'segments': [
    for (final segment in frame.segments)
      [for (final activation in segment) activation.id],
  ],
};

/// One concrete `Navigator` and the pages it owns.
Map<String, Object?> describeNavigator(
  NavigationTree navigation,
  NavigatorNode node,
) => {
  'ownerActivationId': node.ownerActivationId,
  'pages': [
    for (final page in node.pages) describePage(navigation, node, page),
  ],
};

/// One page, with whatever it opens below it: a nested outlet, or a set of
/// persistent branches.
Map<String, Object?> describePage(
  NavigationTree navigation,
  NavigatorNode owner,
  NavigationPage page,
) {
  final key = page.pageKey;
  final activation = page.activation;
  final json = <String, Object?>{
    'pageKey': key is ValueKey<String> ? key.value : key.toString(),
    'frameId': page.frame.id,
    'segmentIndex': page.segmentIndex,
    'isError': activation == null,
    'uri': page.frame.uri.toString(),
    'activation': activation == null ? null : describeActivation(activation),
  };
  if (activation == null) return json;

  if (activation.opensOutlet) {
    final child = owner.children[activation.id];
    json['outlet'] = child == null
        ? null
        : describeNavigator(navigation, child);
  }
  if (activation.opensBranches) {
    json['branches'] = describeBranches(navigation, activation.id);
  }
  return json;
}

/// The persistent branches hosted by one activation, the ones in the
/// background included — their retained stacks are the part of the router
/// nothing else can show.
Map<String, Object?>? describeBranches(
  NavigationTree navigation,
  int ownerActivationId,
) {
  final outlet = navigation.branchesFor(ownerActivationId);
  if (outlet == null) return null;
  final state = navigation.branchStates[ownerActivationId];
  return {
    'ownerActivationId': ownerActivationId,
    'active': outlet.activeBranch,
    'names': outlet.names,
    'outlets': [
      for (final name in outlet.names)
        if (outlet.navigators[name] case final navigator?)
          {
            'name': name,
            'isActive': name == outlet.activeBranch,
            'retainedFrames': state?.histories[name]?.length ?? 0,
            'navigator': describeNavigator(navigation, navigator),
          }
        else
          {
            'name': name,
            'isActive': false,
            'retainedFrames': 0,
            'navigator': null,
          },
    ],
  };
}

/// One live route activation: what the module behind a page was built with.
Map<String, Object?> describeActivation(RouteActivation activation) {
  final route = activation.route;
  final match = activation.match;
  return {
    'id': activation.id,
    'routeId': match.route.id,
    'routePath': match.route.debugPath,
    'kind': _kindOf(match.definition),
    'name': route.name,
    'matchedPath': route.matchedPath,
    'uri': route.uri.value.toString(),
    'params': Map<String, String>.of(route.params.value),
    'query': Map<String, String>.of(route.query.value),
    'extra': describeValue(route.extra),
    'module': activation.module?.runtimeType.toString(),
    'childRouting': match.definition.childRouting.name,
    'reuse': match.definition.reuse.name,
    'guards': _guardNames(match.definition.guards),
    'opensOutlet': activation.opensOutlet,
    'opensBranches': activation.opensBranches,
  };
}

/// One [RouterEvent], for the timeline.
///
/// The chain a [RouteMatched] carries is flattened to the leaf's declared
/// path: the whole chain is already in the navigation tree, and a log entry
/// that held the matches would hold the routes they point at.
Map<String, Object?> describeEvent(RouterEvent event) {
  final json = <String, Object?>{
    'timestampUs': event.timestamp.microsecondsSinceEpoch,
    'navigationId': switch (event) {
      NavigationEvent(:final navigationId) => navigationId,
      StackChanged(:final navigationId) => navigationId,
    },
  };
  switch (event) {
    case NavigationStarted():
      json.addAll({
        'event': 'navigationStarted',
        'kind': event.kind.name,
        'from': event.from.toString(),
        'to': event.to.toString(),
        'extra': describeValue(event.extra),
      });
    case RouteMatched():
      json.addAll({
        'event': 'routeMatched',
        'uri': event.uri.toString(),
        'isMatch': event.isMatch,
        'routePath': event.matches?.last.route.debugPath,
        'routeId': event.matches?.last.route.id,
        'depth': event.matches?.length,
      });
    case RedirectApplied():
      json.addAll({
        'event': 'redirectApplied',
        'from': event.from.toString(),
        'to': event.to.toString(),
        'source': event.source.name,
      });
    case GuardEvaluated():
      json.addAll({
        'event': 'guardEvaluated',
        'guard': event.guardType.toString(),
        'routePath': event.routePath,
        'isGlobal': event.isGlobal,
        'durationUs': event.duration.inMicroseconds,
        ...describeGuardResult(event.result),
      });
    case DeactivationBlocked():
      json.addAll({
        'event': 'deactivationBlocked',
        'uri': event.uri.toString(),
      });
    case NavigationEnded():
      json.addAll({
        'event': 'navigationEnded',
        'outcome': event.outcome.name,
        'uri': event.uri.toString(),
        'durationUs': event.duration.inMicroseconds,
      });
    case StackChanged():
      json.addAll({
        'event': 'stackChanged',
        'revision': event.revision,
        'uri': event.uri.toString(),
      });
  }
  return json;
}

/// What a guard answered, and where it sent the navigation.
Map<String, Object?> describeGuardResult(GuardResult result) =>
    switch (result) {
      AllowGuardResult() => {'result': 'allow'},
      BlockGuardResult() => {'result': 'block'},
      RedirectGuardResult(:final location) => {
        'result': 'redirect',
        'target': location,
      },
    };
