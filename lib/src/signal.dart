import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// A minimal observable value, rendered with [SignalBuilder].
///
/// Listeners are notified only when the new value is different
/// (`!=`) from the current one. When the value is mutated in place — a list
/// or a model object kept at the same identity — call [refresh] instead.
class Signal<T> with ChangeNotifier {
  /// Prefer `Controller.createSignal` instead of this constructor: a
  /// [Signal] made this way isn't tracked by anything, so nothing disposes
  /// it. In particular, never create one inside a `Service` — [Service] has
  /// no dispose hook of its own, so the signal (and its listeners) would
  /// leak for as long as the service is alive. This is `@internal` so any
  /// use from outside this package is flagged by the analyzer.
  @internal
  Signal(this._value);

  T _value;
  bool _disposed = false;

  /// Whether this signal has been disposed, i.e. its owning controller is
  /// gone. Writes to a disposed signal are ignored.
  bool get isDisposed => _disposed;

  /// The current value.
  T get value => _value;

  /// Sets the value and notifies listeners if it actually changed.
  ///
  /// Writing to a disposed signal is a no-op rather than an error, so async
  /// work that finishes after its module unmounted doesn't crash. Prefer
  /// cancelling that work in `Controller.dispose` — or bailing out on
  /// `Controller.isDisposed` — over relying on this.
  set value(T newValue) {
    if (_disposed || _value == newValue) return;
    _value = newValue;
    notifyListeners();
  }

  /// Notifies listeners without changing [value], for state mutated in
  /// place (e.g. `todos.value.add(item)` followed by `todos.refresh()`).
  void refresh() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}

/// Rebuilds [builder] whenever [signal] changes.
class SignalBuilder<T> extends StatelessWidget {
  /// Creates a builder bound to [signal].
  const SignalBuilder({super.key, required this.signal, required this.builder});

  /// The signal listened to.
  final Signal<T> signal;

  /// Builds the subtree for the signal's current value.
  final Widget Function(T value) builder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: signal,
      builder: (context, _) => builder(signal.value),
    );
  }
}
