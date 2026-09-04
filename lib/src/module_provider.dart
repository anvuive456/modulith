import 'package:flutter/widgets.dart';

import 'module_scope.dart';

/// Exposes the [ModuleScope] of the nearest mounted module to its
/// descendants. Internal plumbing: views reach the scope through
/// [ModuleContext], not through this widget.
class ModuleProvider extends InheritedWidget {
  /// Scopes [child] to [moduleScope].
  const ModuleProvider({
    super.key,
    required this.moduleScope,
    required super.child,
  });

  /// The scope descendants resolve against.
  final ModuleScope moduleScope;

  @override
  bool updateShouldNotify(ModuleProvider oldWidget) {
    return !identical(moduleScope, oldWidget.moduleScope);
  }

  /// Returns the nearest [ModuleProvider], throwing if there is none.
  static ModuleProvider of(BuildContext context) {
    final provider = maybeOf(context);
    if (provider == null) {
      throw Exception(
        'No ModuleProvider found in context. Did you wrap your app with '
        'runModuleApp/ModuleWidget?',
      );
    }
    return provider;
  }

  /// Returns the nearest [ModuleProvider], or `null` if there is none.
  static ModuleProvider? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ModuleProvider>();
  }
}
