import 'package:meta/meta.dart';

import 'controller.dart';
import 'module.dart';
import 'module_member.dart';
import 'provider.dart';
import 'service.dart';

/// Runtime scope for one mounted [Module]: what its controllers and services
/// are resolved from, and what owns them until the module unmounts.
///
/// Provider and child declarations are captured once when the scope is
/// created. Instances belong to the scope that declares their provider, even
/// when they are resolved from a nested scope.
final class ModuleScope {
  /// Creates a scope for [module], nested under [parent] if there is one.
  ///
  /// Each entry in [overrides] replaces a provider declared by [module] with
  /// the same type and name — the hook for swapping in fakes from a test.
  /// An override that matches nothing is an error, so a stale test double
  /// fails loudly instead of being silently ignored.
  ModuleScope({
    required this.module,
    this.parent,
    List<Provider<Object>> overrides = const [],
  }) : children = List.unmodifiable(module.children),
       _controllerProviders = _applyOverrides(module.controllers, overrides),
       _serviceProviders = _applyOverrides(module.services, overrides) {
    _controllerIndex = _indexProviders(_controllerProviders, 'controller');
    _serviceIndex = _indexProviders(_serviceProviders, 'service');
    _childIndex = _indexChildren(children, module);
    _validateOverrides(overrides);
  }

  /// The module this scope was created for.
  final Module module;

  /// The enclosing scope, if this module is nested inside another one.
  final ModuleScope? parent;

  /// The child modules declared by [module], mountable with
  /// `ChildModuleView`.
  final List<Module> children;

  final List<Provider<Controller>> _controllerProviders;
  final List<Provider<Service>> _serviceProviders;

  // Declaration-order lists are what a lookup falls back to; these indexes
  // make the common exact-type case a single map read.
  late final Map<(Type, String?), Provider<Controller>> _controllerIndex;
  late final Map<(Type, String?), Provider<Service>> _serviceIndex;
  late final Map<(Type, String?), Module> _childIndex;

  // Where a given lookup landed, so the walk up the module tree happens
  // once per (type, name) instead of once per call. Declarations never
  // change after construction, so an entry can't go stale — but the scope
  // it points at can be disposed, which is re-checked on every read.
  final Map<(Type, String?), _Resolution> _controllerResolutions = {};
  final Map<(Type, String?), _Resolution> _serviceResolutions = {};

  final Map<Provider<Object>, Object> _singletons = {};
  final Set<Provider<Object>> _creating = {};
  final List<_OwnedInstance> _ownedInstances = [];

  bool _active = false;
  bool _moduleInitialized = false;
  bool _disposing = false;
  bool _disposingInstances = false;
  bool _disposed = false;

  /// The scope currently mounting a given [Module] instance, so the same
  /// instance can't back two live scopes at once.
  static final Expando<ModuleScope> _activeMounts = Expando(
    'modulith.activeMount',
  );

  /// Activates this scope and eagerly creates singleton controllers.
  @internal
  void initialize() {
    if (_active || _disposed) {
      throw StateError(
        'Module scope for ${module.runtimeType} cannot be initialized',
      );
    }

    final mounted = _activeMounts[module];
    if (mounted != null && mounted._isUsable) {
      throw StateError(
        '${module.runtimeType} is already mounted somewhere else. A Module '
        'instance backs exactly one live scope: give each mount its own '
        'instance (a `children` getter that returns new modules, or a fresh '
        'one per route).',
      );
    }
    _activeMounts[module] = this;

    _active = true;
    try {
      for (final provider in _controllerProviders) {
        if (provider.isSingleton) {
          _readProvider(provider, null);
        }
      }
      module.onInit(this);
      _moduleInitialized = true;
    } catch (_) {
      try {
        _disposeOwnedInstances();
      } finally {
        _active = false;
        _clearMount();
      }
      rethrow;
    }
  }

  /// Resolves a controller, looking in this module first and then walking up
  /// through ancestor modules.
  ///
  /// When the match is a factory provider, [owner] takes ownership of the
  /// new instance: it is disposed by [releaseOwnedBy], instead of living
  /// until the declaring module unmounts.
  C getController<C extends Controller>({String? name, Object? owner}) {
    return _resolve<C>(kind: _MemberKind.controller, name: name, owner: owner);
  }

  /// Resolves a service, looking in this module first and then walking up
  /// through ancestor modules. See [getController] for [owner].
  S getService<S extends Service>({String? name, Object? owner}) {
    return _resolve<S>(kind: _MemberKind.service, name: name, owner: owner);
  }

  /// Returns the child module of type [M] declared in [Module.children],
  /// matching [name] if given. Used by `ChildModuleView`.
  M childModule<M extends Module>({String? name}) {
    final exact = _childIndex[(M, name)];
    if (exact is M) return exact;
    for (final child in children) {
      if (child is M && child.name == name) return child;
    }
    throw StateError(
      name == null
          ? 'Child module of type $M not found in ${module.runtimeType}.children'
          : 'Child module of type $M named "$name" not found in '
                '${module.runtimeType}.children',
    );
  }

  /// Disposes a factory instance early, wherever in the module chain it is
  /// tracked. Returns whether it was found.
  ///
  /// Only needed for instances resolved straight from a [ModuleScope];
  /// widgets and module members release what they resolved on their own.
  /// Singletons belong to their module and are never released this way.
  bool release(Object instance) {
    ModuleScope? scope = this;
    while (scope != null) {
      final released = scope._releaseLocal(
        (owned) =>
            !owned.provider.isSingleton && identical(owned.value, instance),
      );
      if (released) return true;
      scope = scope.parent;
    }
    return false;
  }

  /// Disposes every factory instance resolved with `owner: owner`, in this
  /// scope and every ancestor scope.
  void releaseOwnedBy(Object owner) {
    ModuleScope? scope = this;
    while (scope != null) {
      scope._releaseLocal((owned) => identical(owned.owner, owner));
      scope = scope.parent;
    }
  }

  /// Tears down this scope: [Module.onDispose] first, then every instance
  /// this scope owns, in reverse creation order.
  @internal
  void dispose() {
    if (_disposed || _disposing) return;
    _disposing = true;

    Object? firstError;
    StackTrace? firstStackTrace;

    if (_moduleInitialized) {
      try {
        module.onDispose(this);
      } catch (error, stackTrace) {
        firstError = error;
        firstStackTrace = stackTrace;
      }
    }

    try {
      _disposeOwnedInstances();
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }

    _active = false;
    _disposing = false;
    _disposed = true;
    _clearMount();
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  bool get _isUsable => _active && !_disposed;

  void _clearMount() {
    if (identical(_activeMounts[module], this)) _activeMounts[module] = null;
  }

  T _resolve<T extends Object>({
    required _MemberKind kind,
    required String? name,
    required Object? owner,
  }) {
    _ensureActive();

    final key = (T, name);
    final cache = _resolutionsFor(kind);
    final resolution = cache[key] ??= _lookup<T>(kind, name, key);

    final declaring = resolution.scope;
    if (!declaring._isUsable) {
      throw StateError(
        '${kind.label} of type $T is declared by ${declaring.module.runtimeType},'
        ' whose module scope has already been disposed',
      );
    }
    return declaring._readProvider(resolution.provider, owner) as T;
  }

  _Resolution _lookup<T extends Object>(
    _MemberKind kind,
    String? name,
    (Type, String?) key,
  ) {
    ModuleScope? scope = this;
    while (scope != null) {
      final exact = scope._indexFor(kind)[key];
      if (exact != null) return _Resolution(scope, exact);
      // A provider registered under a subtype of T still satisfies the
      // lookup; that can only be found by scanning.
      for (final provider in scope._providersFor(kind)) {
        if (provider.name == name && provider.provides<T>()) {
          return _Resolution(scope, provider);
        }
      }
      scope = scope.parent;
    }

    throw StateError(
      name == null
          ? '${kind.label} of type $T not found'
          : '${kind.label} "$name" of type $T not found',
    );
  }

  Map<(Type, String?), Provider<Object>> _indexFor(_MemberKind kind) {
    return kind == _MemberKind.controller ? _controllerIndex : _serviceIndex;
  }

  List<Provider<Object>> _providersFor(_MemberKind kind) {
    return kind == _MemberKind.controller
        ? _controllerProviders
        : _serviceProviders;
  }

  Map<(Type, String?), _Resolution> _resolutionsFor(_MemberKind kind) {
    return kind == _MemberKind.controller
        ? _controllerResolutions
        : _serviceResolutions;
  }

  Object _readProvider(Provider<Object> provider, Object? owner) {
    _ensureActive();

    if (provider.isSingleton) {
      final cached = _singletons[provider];
      if (cached != null) return cached;
    }

    if (_disposingInstances) {
      throw StateError(
        'Cannot create ${provider.valueType} while disposing '
        '${module.runtimeType}',
      );
    }

    if (!_creating.add(provider)) {
      final path = [
        ..._creating,
        provider,
      ].map((item) => item.valueType).join(' -> ');
      throw StateError('Circular dependency detected: $path');
    }

    Object? value;
    try {
      value = provider.createValue();
      if (value is ModuleMember) {
        value.attachScope(this);
        value.init();
      }

      _ownedInstances.add(
        _OwnedInstance(provider, value, provider.isSingleton ? null : owner),
      );
      if (provider.isSingleton) {
        _singletons[provider] = value;
      }
      return value;
    } catch (_) {
      if (value != null) {
        try {
          _disposeValue(provider, value);
        } catch (_) {
          // Tearing down a half-built value can fail on its own (a `late`
          // field that init() never got to assign, say). The original
          // failure is the useful one, so don't let this mask it.
        }
      }
      rethrow;
    } finally {
      _creating.remove(provider);
    }
  }

  /// Removes and disposes every tracked instance matching [test]. Returns
  /// whether anything matched.
  bool _releaseLocal(bool Function(_OwnedInstance owned) test) {
    // Nothing to do while this scope is tearing everything down anyway, and
    // touching the list there would fight with the teardown loop.
    if (_disposingInstances || _ownedInstances.isEmpty) return false;

    final matched = <_OwnedInstance>[];
    _ownedInstances.removeWhere((owned) {
      if (!test(owned)) return false;
      matched.add(owned);
      return true;
    });
    if (matched.isEmpty) return false;

    Object? firstError;
    StackTrace? firstStackTrace;
    for (final owned in matched.reversed) {
      try {
        _disposeValue(owned.provider, owned.value);
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
    return true;
  }

  void _disposeOwnedInstances() {
    // TODO: should we use record? Perhap (firstError, firstStackTrace)?
    Object? firstError;
    StackTrace? firstStackTrace;

    // Snapshot first: disposing a member can release the factory instances
    // it owns, which mutates this list re-entrantly.
    final owned = List.of(_ownedInstances);
    _ownedInstances.clear();
    _singletons.clear();

    _disposingInstances = true;
    try {
      for (final instance in owned.reversed) {
        try {
          _disposeValue(instance.provider, instance.value);
        } catch (error, stackTrace) {
          firstError ??= error;
          firstStackTrace ??= stackTrace;
        }
      }
    } finally {
      _disposingInstances = false;
    }

    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  void _disposeValue(Provider<Object> provider, Object value) {
    try {
      if (value is ModuleMember) value.dispose();
    } finally {
      try {
        provider.disposeValue(value);
      } finally {
        if (value is ModuleMember) value.detachScope(this);
      }
    }
  }

  void _ensureActive() {
    if (!_isUsable) {
      throw StateError(
        'Module scope for ${module.runtimeType} is not active',
      );
    }
  }

  void _validateOverrides(List<Provider<Object>> overrides) {
    for (final override in overrides) {
      final applied =
          _controllerProviders.any((p) => identical(p, override)) ||
          _serviceProviders.any((p) => identical(p, override));
      if (!applied) {
        throw StateError(
          'Override for ${_describe(override.valueType, override.name)} does '
          'not match any provider declared by ${module.runtimeType}',
        );
      }
    }
  }

  static Map<(Type, String?), Provider<T>> _indexProviders<T extends Object>(
    List<Provider<T>> providers,
    String typeLabel,
  ) {
    final index = <(Type, String?), Provider<T>>{};
    for (final provider in providers) {
      final key = (provider.valueType, provider.name);
      if (index.containsKey(key)) {
        throw StateError(
          'Duplicate $typeLabel provider for '
          '${_describe(provider.valueType, provider.name)}',
        );
      }
      index[key] = provider;
    }
    return index;
  }

  static Map<(Type, String?), Module> _indexChildren(
    List<Module> children,
    Module module,
  ) {
    final index = <(Type, String?), Module>{};
    for (final child in children) {
      final key = (child.runtimeType, child.name);
      if (index.containsKey(key)) {
        throw StateError(
          'Duplicate child module ${_describe(child.runtimeType, child.name)} '
          'in ${module.runtimeType}.children. Children are looked up by type, '
          'so give same-typed siblings distinct `name`s.',
        );
      }
      index[key] = child;
    }
    return index;
  }

  static List<Provider<T>> _applyOverrides<T extends Object>(
    List<Provider<T>> declared,
    List<Provider<Object>> overrides,
  ) {
    if (overrides.isEmpty) return List.unmodifiable(declared);
    return List.unmodifiable([
      for (final provider in declared)
        _overrideFor<T>(provider, overrides) ?? provider,
    ]);
  }

  static Provider<T>? _overrideFor<T extends Object>(
    Provider<T> declared,
    List<Provider<Object>> overrides,
  ) {
    for (final override in overrides) {
      if (override.valueType == declared.valueType &&
          override.name == declared.name &&
          override is Provider<T>) {
        return override;
      }
    }
    return null;
  }

  static String _describe(Type type, String? name) {
    return '$type${name == null ? '' : ' named "$name"'}';
  }
}

enum _MemberKind {
  controller('Controller'),
  service('Service');

  const _MemberKind(this.label);

  final String label;
}

final class _Resolution {
  const _Resolution(this.scope, this.provider);

  /// The scope that declares [provider] and owns what it builds.
  final ModuleScope scope;
  final Provider<Object> provider;
}

final class _OwnedInstance {
  const _OwnedInstance(this.provider, this.value, this.owner);

  final Provider<Object> provider;
  final Object value;

  /// Whoever resolved this factory instance, or `null` when the module
  /// itself owns it.
  final Object? owner;
}
