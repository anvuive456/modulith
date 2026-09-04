import 'package:modulith/modulith.dart';

import 'router_service.dart';

/// The reactive projection of the router's state.
///
/// Signals live here and not on [RouterService] because a `Service` has no
/// business owning them — `createSignal` belongs to a `Controller`, which is
/// what disposes them. The router's own state stays in the service; this
/// controller only mirrors the few values a UI watches.
///
/// Every value is a type with real value equality, so a `Signal` only
/// notifies when that value actually changed — navigating from `/users?q=a`
/// to `/users?q=b` does not rebuild a widget watching [canPop].
class RouterController extends Controller {
  late final RouterService _service;

  /// The current location.
  late final uri = createSignal<Uri>(Uri.parse('/'));

  /// Whether there is anything to go back to.
  late final canPop = createSignal<bool>(false);

  /// Whether a navigation is waiting on an async guard — enough to show a
  /// spinner or disable a button while a redirect is being decided.
  late final isNavigating = createSignal<bool>(false);

  /// The name of the deepest active route, for analytics or for deriving a
  /// tab index.
  late final activeRouteName = createSignal<String?>(null);

  /// The router itself, for navigating from a controller that already has
  /// this one injected.
  RouterService get router => _service;

  @override
  void init() {
    _service = injectService<RouterService>();
    _service.addListener(_sync);
    addDisposeCallback(() => _service.removeListener(_sync));
    _sync();
  }

  void _sync() {
    uri.value = _service.currentUri;
    canPop.value = _service.canPop;
    isNavigating.value = _service.isNavigating;
    activeRouteName.value = _service.activeRouteName;
  }
}
