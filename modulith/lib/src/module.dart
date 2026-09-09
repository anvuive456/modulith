import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'module_scope.dart';
import 'provider.dart';
import 'service.dart';

/// A unit of the app: a view plus the controllers, services and child
/// modules that belong to it.
///
/// Every declaration below is read exactly once per instance, and the result
/// is reused for every later read — including the one an ancestor scope does
/// to collect [Provider.exported] providers, which happens before this module
/// is mounted. A [Module] must therefore stay stateless: the same instance
/// can be mounted more than once, and each mount gets its own [ModuleScope].
abstract class Module {
  /// Distinguishes several declared children of the same type, matched by
  /// `ChildModuleView<M>(name: ...)`. Leave it `null` unless a parent
  /// declares more than one child of this module's type.
  String? get name => null;

  /// Child modules that can be mounted with `ChildModuleView`.
  ///
  /// Return fresh instances here: a [Module] instance backs exactly one
  /// live scope, so the same object can't be mounted twice at once.
  ///
  /// This tree is also what [Provider.exported] travels up. A provider a
  /// child (or a child of a child) exports is owned by this module's scope,
  /// which makes it resolvable from this module's own controllers and
  /// services — the one way a lookup reaches downwards.
  List<Module> get children => const [];

  /// Controllers owned by this module.
  List<Provider<Controller>> get controllers => const [];

  /// Services owned by this module.
  List<Provider<Service>> get services => const [];

  /// The widget this module renders.
  Widget get view;

  /// Called after singleton controllers have been created and initialized.
  void onInit(ModuleScope scope) {}

  /// Called before provider-owned instances are disposed.
  void onDispose(ModuleScope scope) {}
}
