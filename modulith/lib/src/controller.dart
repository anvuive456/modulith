import 'package:flutter/foundation.dart';

import 'module_member.dart';
import 'signal.dart';

/// Holds a module's reactive state and the logic that drives it.
///
/// A controller is created by its module's [Provider], attached to the
/// owning [ModuleScope], then initialized via [init]. Everything it
/// creates through [createSignal] or registers through [addDisposeCallback]
/// is torn down in [dispose].
abstract class Controller extends ModuleMember {
  final List<Signal<Object?>> _signals = [];

  /// Creates a [Signal] owned by this controller. Every signal created this
  /// way is disposed automatically when the controller is (see [dispose]).
  ///
  /// Called after the controller was disposed — typically a
  /// `late final s = createSignal(...)` field touched for the first time
  /// from a late async callback — it returns an already-disposed signal
  /// instead of one nothing owns, so the write that follows is a no-op.
  Signal<T> createSignal<T>(T initialValue) {
    final signal = Signal<T>(initialValue);
    if (isDisposed) {
      signal.dispose();
      return signal;
    }
    _signals.add(signal);
    return signal;
  }

  @override
  @protected
  @mustCallSuper
  void disposeOwnedResources() {
    for (final signal in _signals) {
      signal.dispose();
    }
    _signals.clear();
    super.disposeOwnedResources();
  }
}
