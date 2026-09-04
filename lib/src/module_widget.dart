import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'module.dart';
import 'module_scope.dart';
import 'module_provider.dart';
import 'provider.dart';

/// Mounts a [Module] into the widget tree: opens a scope its descendants
/// resolve controllers and services from, nested under the nearest ancestor
/// module if there is one, and drives its lifecycle:
///
/// - Creates and initializes singleton controllers before [Module.onInit].
/// - Calls [Module.onDispose] before disposing provider-owned instances.
class ModuleWidget extends StatefulWidget {
  /// Mounts [module], optionally replacing some of its providers.
  const ModuleWidget({
    super.key,
    required this.module,
    this.overrides = const [],
  });

  /// The module to mount.
  final Module module;

  /// Providers replacing the ones [module] declares, matched by type and
  /// name. Meant for tests:
  /// ```dart
  /// await tester.pumpWidget(
  ///   ModuleWidget(
  ///     module: TodoModule(),
  ///     overrides: [
  ///       Provider<TodoService>.singleton(create: FakeTodoService.new),
  ///     ],
  ///   ),
  /// );
  /// ```
  /// They apply to this module only, not to its children — override a child
  /// module's providers on its own [ChildModuleView]. An override matching
  /// no declared provider throws, so a stale one can't pass silently.
  final List<Provider<Object>> overrides;

  @override
  State<ModuleWidget> createState() => _ModuleWidgetState();
}

class _ModuleWidgetState extends State<ModuleWidget> {
  ModuleScope? _moduleScope;
  ModuleScope? _parentScope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final parent = ModuleProvider.maybeOf(context)?.moduleScope;
    if (_moduleScope == null || !identical(parent, _parentScope)) {
      _replaceScope(parent);
    }
  }

  @override
  void didUpdateWidget(ModuleWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.module, widget.module) ||
        !listEquals(oldWidget.overrides, widget.overrides)) {
      _replaceScope(_parentScope);
    }
  }

  @override
  void dispose() {
    _moduleScope?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = _moduleScope!;
    return ModuleProvider(moduleScope: scope, child: scope.module.view);
  }

  void _replaceScope(ModuleScope? parent) {
    _moduleScope?.dispose();

    final next = ModuleScope(
      module: widget.module,
      parent: parent,
      overrides: widget.overrides,
    );
    next.initialize();
    _parentScope = parent;
    _moduleScope = next;
  }
}

/// Renders the child module of type [M] declared in the nearest ancestor
/// module's [Module.children], giving it its own scope nested under the
/// parent module (so the child can still resolve the parent's
/// controllers/services).
///
/// The child is found by type; when a parent declares more than one child of
/// the same type, give each a [Module.name] and select it with [name].
class ChildModuleView<M extends Module> extends StatelessWidget {
  /// Mounts the declared child module of type [M] whose [Module.name]
  /// matches [name].
  const ChildModuleView({super.key, this.name, this.overrides = const []});

  /// The [Module.name] of the child to mount, for parents that declare
  /// several children of type [M].
  final String? name;

  /// Providers replacing the ones the child module declares. See
  /// [ModuleWidget.overrides].
  final List<Provider<Object>> overrides;

  @override
  Widget build(BuildContext context) {
    final parent = ModuleProvider.of(context).moduleScope;
    return ModuleWidget(
      module: parent.childModule<M>(name: name),
      overrides: overrides,
    );
  }
}
