import 'package:flutter_test/flutter_test.dart';
import 'package:modulith_router/modulith_router.dart';

void main() {
  group('RoutePattern.parse', () {
    test('reads literals, parameters and wildcards', () {
      final pattern = RoutePattern.parse('users/:id/*/**');

      expect(pattern.segments.map((segment) => segment.kind), [
        RouteSegmentKind.literal,
        RouteSegmentKind.parameter,
        RouteSegmentKind.wildcard,
        RouteSegmentKind.catchAll,
      ]);
      expect(pattern.parameterNames, ['id']);
    });

    test('treats surrounding slashes as noise', () {
      expect(RoutePattern.parse('/').isPathless, isTrue);
      expect(RoutePattern.parse('').isPathless, isTrue);
      expect(RoutePattern.parse('/users/').segments, hasLength(1));
    });

    test('rejects `**` anywhere but last', () {
      expect(
        () => RoutePattern.parse('**/details'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects an empty parameter name', () {
      expect(
        () => RoutePattern.parse('users/:'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('RoutePattern.expand', () {
    test('substitutes parameters', () {
      expect(RoutePattern.parse('users/:id').expand({'id': '42'}), [
        'users',
        '42',
      ]);
    });

    test('names the missing parameter', () {
      expect(
        () => RoutePattern.parse('users/:id').expand(const {}),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('id'),
          ),
        ),
      );
    });

    test('refuses to invent a value for a wildcard', () {
      expect(
        () => RoutePattern.parse('files/**').expand(const {}),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('RoutePattern.compareTo', () {
    test('sorts literal before parameter before wildcard', () {
      final patterns = [
        RoutePattern.parse('**'),
        RoutePattern.parse(':id'),
        RoutePattern.parse('*'),
        RoutePattern.parse('new'),
      ]..sort((a, b) => a.compareTo(b));

      expect(patterns.map((pattern) => pattern.raw), ['new', ':id', '*', '**']);
    });

    test('sorts the longer pattern first when prefixes tie', () {
      expect(
        RoutePattern.parse('users/new').compareTo(RoutePattern.parse('users')),
        lessThan(0),
      );
    });
  });
}
