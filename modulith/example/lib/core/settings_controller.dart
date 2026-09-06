import 'package:modulith/modulith.dart';

/// Registered once on [AppModule] and shared by every feature via
/// [ModuleContext.getController] (from a view) or `injectController` (from
/// another controller), both of which walk up the module tree — features
/// never need to own or re-declare this controller themselves.
///
/// This is a [Controller], not a [Service]: it holds reactive [Signal]
/// state. Both have the same lifecycle, but only [Controller] can create
/// signals — and only [Controller] disposes them — so a `Signal` built
/// inside a [Service] would be owned by nothing. [Signal]'s constructor is
/// `@internal` for exactly this reason, to catch that at analysis time.
class SettingsController extends Controller {
  late final darkMode = createSignal<bool>(false);
  late final username = createSignal<String>('Guest');

  void toggleDarkMode() => darkMode.value = !darkMode.value;

  void setUsername(String value) => username.value = value;
}
