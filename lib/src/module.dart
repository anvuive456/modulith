import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'module_scope.dart';
import 'provider.dart';
import 'service.dart';

/// A unit of the app: a view plus the controllers, services and child
/// modules that belong to it.
///
/// Every declaration below is read exactly once, when the module is mounted
/// by a `ModuleWidget`. A [Module] must therefore stay stateless — the same
/// instance can be mounted more than once, and each mount gets its own
/// [ModuleScope].
abstract class Module {
  /// Distinguishes several declared children of the same type, matched by
  /// `ChildModuleView<M>(name: ...)`. Leave it `null` unless a parent
  /// declares more than one child of this module's type.
  String? get name => null;

  /// Child modules that can be mounted with `ChildModuleView`.
  ///
  /// Return fresh instances here: a [Module] instance backs exactly one
  /// live scope, so the same object can't be mounted twice at once.
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
