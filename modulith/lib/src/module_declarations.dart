import 'package:meta/meta.dart';

import 'controller.dart';
import 'module.dart';
import 'provider.dart';
import 'service.dart';

/// What a [Module] declares, read exactly once per module instance.
///
/// [Module.children], [Module.controllers] and [Module.services] are plain
/// getters, so every read builds new objects. That was harmless while a
/// module's declarations were only ever read by its own scope, but an
/// exported provider is picked up by an ancestor scope *before* the module
/// that declares it is mounted, and the two reads have to agree on object
/// identity: otherwise the ancestor would hoist one `Provider` while the
/// module kept an identical twin and built a second instance from it.
///
/// Caching the first read per module instance keeps them the same objects,
/// and turns "declarations are read once" from a documented convention into
/// something the code actually guarantees.
@internal
final class ModuleDeclarations {
  ModuleDeclarations._(this.children, this.controllers, this.services);

  /// The declarations of [module], reading its getters on the first call
  /// and reusing that result afterwards.
  factory ModuleDeclarations.of(Module module) {
    final cached = _cache[module];
    if (cached != null) return cached;

    final declarations = ModuleDeclarations._(
      List.unmodifiable(module.children),
      List.unmodifiable(module.controllers),
      List.unmodifiable(module.services),
    );
    _cache[module] = declarations;
    return declarations;
  }

  // Weak, so a module that is never mounted again takes its declarations
  // with it.
  static final Expando<ModuleDeclarations> _cache = Expando(
    'modulith.declarations',
  );

  final List<Module> children;
  final List<Provider<Controller>> controllers;
  final List<Provider<Service>> services;
}
