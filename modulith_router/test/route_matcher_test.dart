import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modulith_router/modulith_router.dart';

ViewRoute view(
  String path, {
  String? name,
  List<RouteDefinition> children = const [],
  ChildRouting childRouting = ChildRouting.stack,
}) => ViewRoute(
  path: path,
  name: name,
  children: children,
  childRouting: childRouting,
  builder: (context, route) => const SizedBox.shrink(),
);

List<String> pathsOf(List<RouteMatch>? matches) =>
    (matches ?? []).map((match) => match.route.debugPath).toList();

void main() {
  group('matching', () {
    test('returns the whole chain, root first', () {
      final matcher = RouteMatcher([
        view('users', children: [view(':id')]),
      ]);

      final matches = matcher.match(Uri.parse('/users/42'));

      expect(pathsOf(matches), ['/users', '/users/:id']);
      expect(matches!.last.pathParams, {'id': '42'});
      expect(matches.last.matchedPath, '/users/42');
      expect(matches.first.matchedPath, '/users');
    });

    test('prefers a literal over a parameter, whatever the declaration '
        'order', () {
      final matcher = RouteMatcher([
        view('users', children: [view(':id'), view('new')]),
      ]);

      expect(pathsOf(matcher.match(Uri.parse('/users/new'))), [
        '/users',
        '/users/new',
      ]);
      expect(pathsOf(matcher.match(Uri.parse('/users/42'))), [
        '/users',
        '/users/:id',
      ]);
    });

    test('falls back to `**` only when nothing else fits', () {
      final matcher = RouteMatcher([view('users'), view('**', name: 'oops')]);

      expect(pathsOf(matcher.match(Uri.parse('/users'))), ['/users']);
      expect(pathsOf(matcher.match(Uri.parse('/nope/deeper'))), ['/**']);
      expect(
        matcher.match(Uri.parse('/nope/deeper'))!.last.pathParams['**'],
        'nope/deeper',
      );
    });

    test('lands on a pathless shell\'s index child at the root URL', () {
      final matcher = RouteMatcher([
        view(
          '',
          childRouting: ChildRouting.outlet,
          children: [view(''), view('settings')],
        ),
      ]);

      expect(pathsOf(matcher.match(Uri.parse('/'))), ['/', '/']);
      expect(pathsOf(matcher.match(Uri.parse('/settings'))), [
        '/',
        '/settings',
      ]);
    });

    test('accumulates parameters down the chain', () {
      final matcher = RouteMatcher([
        view('teams/:team', children: [view('users/:user')]),
      ]);

      final matches = matcher.match(Uri.parse('/teams/7/users/42'));

      expect(matches!.last.pathParams, {'team': '7', 'user': '42'});
      expect(matches.first.pathParams, {'team': '7'});
    });

    test('ignores the query string', () {
      final matcher = RouteMatcher([view('users')]);

      expect(pathsOf(matcher.match(Uri.parse('/users?q=ana'))), ['/users']);
    });

    test('returns null when leftover segments have nowhere to go', () {
      final matcher = RouteMatcher([view('users')]);

      expect(matcher.match(Uri.parse('/users/42')), isNull);
      expect(matcher.match(Uri.parse('/teams')), isNull);
    });
  });

  group('table validation', () {
    test('rejects two siblings with the same pattern', () {
      expect(
        () => RouteMatcher([view('users'), view('users')]),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('same path'),
          ),
        ),
      );
    });

    test('rejects a duplicate route name', () {
      expect(
        () => RouteMatcher([view('a', name: 'x'), view('b', name: 'x')]),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('named "x"'),
          ),
        ),
      );
    });

    test('rejects a parameter that would shadow an ancestor\'s', () {
      expect(
        () => RouteMatcher([
          view('teams/:id', children: [view('users/:id')]),
        ]),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('already captures'),
          ),
        ),
      );
    });
  });

  group('uriFor', () {
    test('builds a nested path with parameters and query', () {
      final matcher = RouteMatcher([
        view('teams/:team', children: [view('users/:user', name: 'user')]),
      ]);

      expect(
        matcher.uriFor(
          'user',
          pathParams: {'team': '7', 'user': '42'},
          queryParameters: {'tab': 'profile'},
        ),
        Uri.parse('/teams/7/users/42?tab=profile'),
      );
    });

    test('lists the known names when asked for one that does not exist', () {
      final matcher = RouteMatcher([view('users', name: 'users')]);

      expect(
        () => matcher.uriFor('nope'),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('users'),
          ),
        ),
      );
    });
  });
}
