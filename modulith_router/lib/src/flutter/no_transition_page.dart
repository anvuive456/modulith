import 'package:flutter/widgets.dart';

/// A page that does not transition when pushed or popped.
class NoTransitionPage extends Page<void> {
  /// Creates a [NoTransitionPage] with the given [child].
  const NoTransitionPage({
    required this.child,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  /// The child widget to display.
  final Widget child;

  @override
  Route<void> createRoute(BuildContext context) => _NoTransitionPageRoute(this);
}

class _NoTransitionPageRoute extends PageRoute<void> {
  _NoTransitionPageRoute(NoTransitionPage page) : super(settings: page);

  NoTransitionPage get _page => settings as NoTransitionPage;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  bool get maintainState => true;

  @override
  bool get opaque => true;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => _page.child;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
