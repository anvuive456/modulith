import 'package:meta/meta.dart';

/// How long a value created by a [Provider] lives.
enum ProviderLifetime {
  /// One instance per module scope, created eagerly (controllers) or on
  /// first lookup (services) and disposed when the module unmounts.
  singleton,

  /// A new instance per lookup, owned by whoever resolved it — see
  /// [Provider.factory] for the exact lifetime rules.
  factory,
}

/// Describes how a value owned by a module is created and disposed.
final class Provider<T extends Object> {
  /// Registers a single instance shared by the whole module scope.
  const Provider.singleton({required this.create, this.name, this.dispose})
    : lifetime = ProviderLifetime.singleton;

  /// Registers a value rebuilt on every lookup.
  ///
  /// A factory instance is owned by whoever resolved it, not by the module:
  ///
  /// - resolved through a [ModuleContext]: disposed when that widget
  ///   rebuilds or leaves the tree, so a build method can't accumulate them;
  /// - resolved through `injectController` / `injectService`: disposed with
  ///   the controller or service that asked for it;
  /// - resolved straight from a [ModuleScope]: disposed with the module,
  ///   unless released earlier via [ModuleScope.release].
  const Provider.factory({required this.create, this.name, this.dispose})
    : lifetime = ProviderLifetime.factory;

  /// Builds a new value.
  final T Function() create;

  /// Extra teardown for a value built by [create], run after
  /// `Controller.dispose` for controllers.
  final void Function(T value)? dispose;

  /// Distinguishes several providers registered for the same type.
  final String? name;

  /// Whether instances are shared across the module scope.
  final ProviderLifetime lifetime;

  /// Whether this provider is a [ProviderLifetime.singleton].
  bool get isSingleton => lifetime == ProviderLifetime.singleton;

  /// The type this provider is registered under.
  ///
  /// Lookups match this type exactly, so register against the type callers
  /// ask for: `Provider<AuthService>.singleton(create: FirebaseAuth.new)` is
  /// resolvable as `getService<AuthService>()`, not as `getService<FirebaseAuth>()`.
  Type get valueType => T;

  /// Whether a lookup for `R` matches this provider.
  @internal
  bool provides<R extends Object>() => this is Provider<R>;

  /// Builds a value, hiding [T] from the scope that tracks it.
  @internal
  Object createValue() => create();

  /// Runs [dispose] for a value built by [createValue].
  @internal
  void disposeValue(Object value) => dispose?.call(value as T);
}
