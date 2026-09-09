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
  const Provider.singleton({
    required this.create,
    this.name,
    this.dispose,
    this.exported = false,
  }) : lifetime = ProviderLifetime.singleton;

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
  const Provider.factory({
    required this.create,
    this.name,
    this.dispose,
    this.exported = false,
  }) : lifetime = ProviderLifetime.factory;

  /// Builds a new value.
  final T Function() create;

  /// Extra teardown for a value built by [create], run after
  /// `Controller.dispose` for controllers.
  final void Function(T value)? dispose;

  /// Distinguishes several providers registered for the same type.
  final String? name;

  /// Whether instances are shared across the module scope.
  final ProviderLifetime lifetime;

  /// Whether ancestor modules can resolve this provider too.
  ///
  /// Lookups normally only travel up the module tree, so a module can't
  /// reach what a module below it declares. Marking a provider `exported`
  /// hands it to the closest ancestor scope that declares this module —
  /// directly or through another module's [Module.children] — which then
  /// *owns* it:
  ///
  /// ```dart
  /// class RouterModule extends Module {
  ///   @override
  ///   List<Provider<Service>> get services => [
  ///     Provider<RouterService>.singleton(
  ///       create: RouterService.new,
  ///       exported: true,
  ///     ),
  ///   ];
  /// }
  ///
  /// class AppModule extends Module {
  ///   @override
  ///   List<Module> get children => [RouterModule()];
  ///   // A controller here can now `injectService<RouterService>()`.
  /// }
  /// ```
  ///
  /// What moving ownership up means:
  ///
  /// - the instance lives as long as the ancestor's scope, not as long as
  ///   the mount of the module that declares it, and is created there — so
  ///   it resolves even while the declaring module is not mounted at all;
  /// - it is attached to the ancestor's scope, so anything it injects has
  ///   to be resolvable from there: an exported provider can't depend on a
  ///   private provider of its own module;
  /// - it is overridden on the ancestor that owns it, not on the module
  ///   that declares it (see [ModuleScope]);
  /// - it collides with an ancestor's own registration of the same type and
  ///   name, and with a sibling exporting the same type and name — both
  ///   throw at mount, the way two registrations in one module already do.
  ///
  /// Only declared children are read this way. A module mounted some other
  /// way — a routed module built per navigation, say — has no declaring
  /// ancestor, so its exports stay local.
  final bool exported;

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
