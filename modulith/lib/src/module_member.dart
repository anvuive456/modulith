import 'package:flutter/foundation.dart';

import 'controller.dart';
import 'module_scope.dart';
import 'service.dart';

/// What [Controller] and [Service] have in common: a module scope to
/// resolve from, an [init] hook that runs once the scope is active, and a
/// [dispose] that undoes it.
///
/// You extend [Controller] or [Service], not this class — the two exist so
/// a module can tell reactive state (controllers, which own [Signal]s) from
/// plain collaborators (services).
abstract class ModuleMember {
  final List<VoidCallback> _disposeCallbacks = [];
  ModuleScope? _scope;
  bool _disposed = false;

  /// Whether [dispose] has run, i.e. the owning module is gone.
  ///
  /// Check this before touching state from an async continuation:
  /// ```dart
  /// Future<void> _load() async {
  ///   final items = await _service.fetch();
  ///   if (isDisposed) return;
  ///   todos.value = items;
  /// }
  /// ```
  bool get isDisposed => _disposed;

  /// Binds this object to the scope that created it. Called by
  /// [ModuleScope]; a member can only be attached once.
  @internal
  void attachScope(ModuleScope scope) {
    if (_scope != null) {
      throw StateError('$runtimeType is already attached to a ModuleScope');
    }
    _scope = scope;
  }

  /// Unbinds this object from [scope] once that scope disposed it.
  @internal
  void detachScope(ModuleScope scope) {
    if (identical(_scope, scope)) _scope = null;
  }

  /// Resolves a controller from this object's module scope.
  ///
  /// A factory-provided controller resolved this way is owned by the caller
  /// and disposed together with it.
  @protected
  C injectController<C extends Controller>({String? name}) {
    return _requireScope().getController<C>(name: name, owner: this);
  }

  /// Resolves a service from this object's module scope.
  ///
  /// A factory-provided service resolved this way is owned by the caller
  /// and disposed together with it.
  @protected
  S injectService<S extends Service>({String? name}) {
    return _requireScope().getService<S>(name: name, owner: this);
  }

  /// Registers cleanup to run when this object is disposed, for things
  /// created outside the constructor — timers, stream subscriptions:
  /// ```dart
  /// @override
  /// void init() {
  ///   final sub = repository.updates.listen(_onUpdate);
  ///   addDisposeCallback(sub.cancel);
  /// }
  /// ```
  /// Callbacks run in reverse registration order. Registering one after
  /// disposal runs it right away, so the resource is still released.
  @protected
  void addDisposeCallback(VoidCallback callback) {
    if (_disposed) {
      callback();
      return;
    }
    _disposeCallbacks.add(callback);
  }

  /// Runs setup for this object. Called automatically right after it is
  /// created by its [Provider] and attached to the module scope (not from
  /// the constructor) — use this instead of the constructor for work that
  /// should only happen while the module is active, e.g. subscribing to a
  /// stream, starting a timer, or resolving dependencies with
  /// [injectController] / [injectService].
  void init() {}

  /// Runs the callbacks registered with [addDisposeCallback] and releases
  /// every factory instance this object injected. Called automatically when
  /// the owning module is unmounted.
  ///
  /// If overridden, call `super.dispose()` **last** (same convention as
  /// `State.dispose`) so this object's own state is still usable during
  /// your cleanup:
  /// ```dart
  /// @override
  /// void dispose() {
  ///   // your own cleanup
  ///   super.dispose();
  /// }
  /// ```
  @mustCallSuper
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    Object? firstError;
    StackTrace? firstStackTrace;
    void guarded(VoidCallback action) {
      try {
        action();
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    final callbacks = List.of(_disposeCallbacks);
    _disposeCallbacks.clear();
    for (final callback in callbacks.reversed) {
      guarded(callback);
    }
    guarded(() => _scope?.releaseOwnedBy(this));
    guarded(disposeOwnedResources);

    final error = firstError;
    if (error != null) {
      Error.throwWithStackTrace(error, firstStackTrace!);
    }
  }

  /// Releases what this kind of member owns beyond dispose callbacks — the
  /// signals of a [Controller], for instance. Runs last, after every
  /// callback registered with [addDisposeCallback], and a throw here can't
  /// skip the rest of the teardown.
  @protected
  @mustCallSuper
  void disposeOwnedResources() {}

  ModuleScope _requireScope() {
    return _scope ??
        (throw StateError(
          '$runtimeType has not been attached to a ModuleScope',
        ));
  }
}
