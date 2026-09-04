import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'module_provider.dart';
import 'module_scope.dart';
import 'service.dart';

/// The [BuildContext] a [ModularWidget] builds with: an ordinary build
/// context that can also resolve the enclosing module's controllers and
/// services.
///
/// Everything you'd normally do with a `BuildContext` — `Theme.of(context)`,
/// `Navigator.of(context)` — works as usual. The scope it resolves against
/// is a [ModuleScope].
abstract interface class ModuleContext implements BuildContext {
  /// Returns a controller of type [C]. Looks in the current module first,
  /// then walks up through ancestor modules until one is found.
  /// If [name] is provided, it must match the provider registration name.
  C getController<C extends Controller>({String? name});

  /// Returns a service of type [S]. Looks in the current module first,
  /// then walks up through ancestor modules until one is found.
  /// If [name] is provided, it must match the provider registration name.
  S getService<S extends Service>({String? name});
}

/// The base class for a module's views: `build` gets a [ModuleContext], so
/// a view reaches its controllers without a `State` of its own.
///
/// ```dart
/// class CounterPage extends ModularWidget {
///   const CounterPage({super.key});
///
///   @override
///   Widget build(ModuleContext context) {
///     final controller = context.getController<CounterController>();
///     return SignalBuilder(
///       signal: controller.count,
///       builder: (value) => Text('$value'),
///     );
///   }
/// }
/// ```
///
/// Factory instances resolved through the context last exactly one build:
/// the next build of this widget disposes the previous build's instances,
/// so a `build` method can't quietly pile them up.
///
/// State belongs in a [Controller] — including Flutter objects a view would
/// normally keep in a `State`, like a `TextEditingController` or a
/// `ScrollController`. Create them as controller fields and register their
/// teardown with `addDisposeCallback`:
/// ```dart
/// class SearchController extends Controller {
///   final input = TextEditingController();
///
///   @override
///   void init() => addDisposeCallback(input.dispose);
/// }
/// ```
abstract class ModularWidget extends Widget {
  /// Creates a module-aware widget.
  const ModularWidget({super.key});

  @override
  Element createElement() => _ModularElement(this);

  /// Builds the widget for the enclosing module scope.
  @protected
  Widget build(ModuleContext context);
}

class _ModularElement extends ComponentElement implements ModuleContext {
  _ModularElement(ModularWidget super.widget);

  ModuleScope? _moduleScope;

  @override
  Widget build() {
    final scope = ModuleProvider.of(this).moduleScope;
    // Whatever the previous build resolved from a factory provider is dead
    // now: nothing from that build can still be on screen.
    _moduleScope?.releaseOwnedBy(this);
    _moduleScope = scope;
    return (widget as ModularWidget).build(this);
  }

  @override
  C getController<C extends Controller>({String? name}) {
    return _requireScope().getController<C>(name: name, owner: this);
  }

  @override
  S getService<S extends Service>({String? name}) {
    return _requireScope().getService<S>(name: name, owner: this);
  }

  ModuleScope _requireScope() {
    return _moduleScope ?? ModuleProvider.of(this).moduleScope;
  }

  @override
  void update(ModularWidget newWidget) {
    // ComponentElement doesn't rebuild on its own; without this a
    // ModularWidget would ignore new values passed in by its parent.
    super.update(newWidget);
    assert(widget == newWidget);
    rebuild(force: true);
  }

  @override
  void unmount() {
    _moduleScope?.releaseOwnedBy(this);
    _moduleScope = null;
    super.unmount();
  }
}
